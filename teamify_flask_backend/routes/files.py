"""Secure file upload/download with at-rest encryption and SHA-256 integrity."""
from __future__ import annotations

import io
import logging
import mimetypes
import os
import re
import unicodedata
import uuid
from datetime import datetime, timezone

from flask import Blueprint, current_app, jsonify, request, send_file
from flask_jwt_extended import get_jwt_identity

from middleware.auth import auth_required, get_project_role, _READ_ROLES
from models import db
from models.alert import Alert
from models.file_metadata import FileMetadata
from models.user import User
from utils.crypto import (
    InvalidToken,
    decrypt_bytes,
    encrypt_bytes,
    sha256_hex,
    verify_hash,
)

logger = logging.getLogger(__name__)

files_bp = Blueprint("files", __name__, url_prefix="/api/files")

# ── Security constants ─────────────────────────────────────────────────────────

# Hard size cap (10 MB). Flask's MAX_CONTENT_LENGTH catches oversized multi-part
# requests before they hit this handler; this is a double-check on the raw bytes.
MAX_UPLOAD_BYTES = 10 * 1024 * 1024  # 10 MB

# Allowlisted MIME prefixes. Client-supplied MIME is verified; we also sniff
# magic bytes to detect spoofed Content-Type headers.
ALLOWED_MIME_PREFIXES: tuple[str, ...] = (
    "image/",
    "audio/",
    "video/",
    "application/pdf",
    "text/plain",
    "text/csv",
    "application/vnd.openxmlformats-officedocument",  # .docx/.xlsx/.pptx
    "application/msword",
    "application/vnd.ms-excel",
    "application/vnd.ms-powerpoint",
    "application/zip",
)

# Blocked file extensions — executables, scripts, and other dangerous types.
BLOCKED_EXTENSIONS: frozenset[str] = frozenset(
    {
        ".exe", ".com", ".cmd", ".bat", ".sh", ".ps1", ".vbs", ".js", ".mjs",
        ".cjs", ".ts", ".py", ".rb", ".pl", ".php", ".apk", ".ipa", ".dmg",
        ".msi", ".dll", ".so", ".dylib", ".jar", ".class", ".war", ".ear",
        ".pif", ".scr", ".hta", ".lnk", ".reg", ".inf",
    }
)

# Magic-byte signatures of blocked executable formats:
# Each entry: (offset, bytes_to_match)
_BLOCKED_MAGIC: list[tuple[int, bytes]] = [
    (0, b"MZ"),          # Windows PE / DOS executable
    (0, b"\x7fELF"),     # Linux ELF binary
    (0, b"#!/"),         # Shell shebang  (#!/bin/sh, #!/usr/bin/env, …)
    (0, b"#!"),          # Broader shebang catch
    (0, b"PK\x03\x04"),  # ZIP — allowed only via MIME allowlist (double-check below)
]


def _upload_dir() -> str:
    path = os.getenv("UPLOAD_DIR", os.path.join("instance", "uploads"))
    os.makedirs(path, exist_ok=True)
    return path


def _is_allowed_mime(mime: str) -> bool:
    return any(mime.startswith(p) for p in ALLOWED_MIME_PREFIXES)


def _is_blocked_extension(filename: str) -> bool:
    """Return True when the filename ends with a blocked extension."""
    parts = filename.lower().rsplit(".", 1)
    ext = "." + parts[1] if len(parts) > 1 else ""
    return ext in BLOCKED_EXTENSIONS


def _has_blocked_magic(data: bytes) -> bool:
    """Return True if magic bytes indicate an executable / script payload."""
    for offset, magic in _BLOCKED_MAGIC:
        # Skip the ZIP magic-byte check — ZIP is allowed (e.g. .docx)
        if magic == b"PK\x03\x04":
            continue
        if data[offset : offset + len(magic)] == magic:
            return True
    # Catch shebangs up to 512 bytes in (some editors insert BOM)
    head = data[:512]
    if re.search(rb"^(?:\xef\xbb\xbf)?#!", head):
        return True
    return False


def _sanitize_filename(filename: str) -> str:
    """
    Return a safe filename:
    - Unicode normalised to NFKC
    - Non-ASCII stripped
    - Path separators / null bytes removed
    - Collapsed whitespace replaced with underscore
    - Truncated to 200 characters (preserving extension)
    """
    # Normalise unicode, strip non-printable / non-ASCII
    normalised = unicodedata.normalize("NFKC", filename)
    safe = re.sub(r"[^\w\s.\-]", "", normalised, flags=re.ASCII)
    # Remove path traversal sequences
    safe = safe.replace("..", "").replace("/", "").replace("\\", "").replace("\x00", "")
    safe = re.sub(r"\s+", "_", safe).strip("._")
    if not safe:
        safe = "upload"
    # Preserve extension, truncate stem
    parts = safe.rsplit(".", 1)
    if len(parts) > 1:
        root, ext = parts[0], "." + parts[1]
    else:
        root, ext = safe, ""
    ext = ext[:10]  # cap extension length
    max_stem = 200 - len(ext)
    return root[:max_stem] + ext


# ─── POST /api/files ─────────────────────────────────────────────────────────

@files_bp.route("", methods=["POST"])
@auth_required
def upload_file():
    """
    Upload a file. The bytes are SHA-256 hashed (original) and stored
    Fernet-encrypted on disk.
    ---
    tags: [Files]
    security: [{Bearer: []}]
    consumes: [multipart/form-data]
    parameters:
      - {in: formData, name: file, type: file, required: true}
    responses:
    responses:
      201:
        description: File stored
        schema:
          type: object
          properties:
            message:
              type: string
            file:
              type: object
      400:
        description: Validation error
        schema:
          type: object
          properties:
            error:
              type: string
      413:
        description: File too large
        schema:
          type: object
          properties:
            error:
              type: string
      415:
        description: Unsupported media type
        schema:
          type: object
          properties:
            error:
              type: string
    """
    if "file" not in request.files:
        return jsonify({"error": "Missing 'file' part"}), 400

    upload = request.files["file"]
    if not upload or not upload.filename:
        return jsonify({"error": "Empty file name"}), 400

    # ── 0. Sanitize filename BEFORE any further use ────────────────────────
    original_filename = _sanitize_filename(upload.filename)
    if not original_filename:
        return jsonify({"error": "Invalid filename"}), 400

    # ── 1. Extension allowlist — block executables / scripts ──────────────
    if _is_blocked_extension(original_filename):
        parts = original_filename.lower().rsplit(".", 1)
        ext = "." + parts[1] if len(parts) > 1 else ""
        logger.warning(
            "Blocked upload of dangerous extension '%s' by user %s",
            ext,
            get_jwt_identity(),
        )
        return jsonify({"error": f"Unsupported media type: File type '{ext}' is not allowed"}), 415

    # ── 1b. Admin-configured extension allowlist ─────────────────────────────
    allowed_exts = None
    try:
        from services.system_settings_service import get_allowed_file_extensions

        allowed_exts = get_allowed_file_extensions()
    except Exception:
        logger.warning("Could not load upload allowlist from system settings", exc_info=True)

    if allowed_exts:
        parts = original_filename.lower().rsplit(".", 1)
        ext = parts[1] if len(parts) > 1 else ""
        if ext not in allowed_exts:
            return jsonify({
                "error": f"Unsupported media type: '.{ext}' is not in the allowed file types list"
            }), 415

    # ── 2. Read body ───────────────────────────────────────────────────────
    raw = upload.read()
    if not raw:
        return jsonify({"error": "Empty file body"}), 400

    max_bytes = MAX_UPLOAD_BYTES
    try:
        from services.system_settings_service import get_upload_max_bytes

        max_bytes = min(MAX_UPLOAD_BYTES, get_upload_max_bytes())
    except Exception:
        logger.warning("Could not load upload size limit from system settings", exc_info=True)

    if len(raw) > max_bytes:
        limit_mb = max(1, max_bytes // (1024 * 1024))
        return jsonify({"error": f"File exceeds {limit_mb} MB limit"}), 413

    # ── 3. MIME validation (client-supplied header) ───────────────────────
    # Flutter/Dio often sends application/octet-stream for byte uploads.
    # Fall back to guessing from the sanitized filename in that case.
    mime = (upload.mimetype or "").split(";")[0].strip().lower()
    if not mime or mime == "application/octet-stream":
        guessed, _ = mimetypes.guess_type(original_filename)
        if guessed:
            mime = guessed.split(";")[0].strip().lower()
    if not mime:
        mime = "application/octet-stream"
    if not _is_allowed_mime(mime):
        logger.warning(
            "Blocked upload with MIME '%s' by user %s", mime, get_jwt_identity()
        )
        return jsonify({"error": f"Unsupported media type: {mime}"}), 415

    # ── 4. Magic-byte validation (detects spoofed MIME) ───────────────────
    if _has_blocked_magic(raw):
        logger.warning(
            "Blocked upload: magic bytes indicate executable, user %s filename '%s'",
            get_jwt_identity(),
            original_filename,
        )
        return jsonify({"error": "File content is not allowed (executable detected)"}), 415

    # ── 5. SHA-256 of original plaintext ──────────────────────────────────
    digest = sha256_hex(raw)

    # ── 6. Encrypt ────────────────────────────────────────────────────────
    try:
        ciphertext = encrypt_bytes(raw)
    except RuntimeError as exc:
        return jsonify({"error": str(exc)}), 500

    # ── 7. Write to server-generated path (never client-controlled) ───────
    file_id = uuid.uuid4()
    enc_filename = f"{file_id}.enc"
    enc_path = os.path.join(_upload_dir(), enc_filename)
    # O_EXCL prevents clobbering an existing file with the same UUID.
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    fd = os.open(enc_path, flags, 0o600)
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(ciphertext)
    except Exception:
        try:
            os.unlink(enc_path)
        except OSError:
            pass
        raise

    # ── 8. Persist metadata ────────────────────────────────────────────────
    try:
        owner_id = int(get_jwt_identity())
    except (ValueError, TypeError):
        os.unlink(enc_path)
        return jsonify({"error": "Invalid token identity"}), 401

    project_id = None
    project_id_raw = request.form.get("project_id", "").strip()
    if project_id_raw:
        try:
            project_id = int(project_id_raw)
        except ValueError:
            os.unlink(enc_path)
            return jsonify({"error": "Invalid project_id"}), 400
        from models.project import Project

        project = Project.query.get(project_id)
        if not project:
            os.unlink(enc_path)
            return jsonify({"error": "Project not found"}), 404
        if get_project_role(owner_id, project_id) not in _READ_ROLES:
            os.unlink(enc_path)
            return jsonify({"error": "Forbidden"}), 403

    meta = FileMetadata(
        owner_id=owner_id,
        project_id=project_id,
        original_filename=original_filename[:255],
        mime_type=mime[:127],
        size_bytes=len(raw),
        encrypted_path=enc_path,
        sha256_hash=digest,
        created_at=datetime.now(timezone.utc),
    )
    db.session.add(meta)
    db.session.commit()

    logger.info(
        "File uploaded: id=%s owner=%s filename='%s' mime=%s size=%d sha256=%s",
        meta.id,
        owner_id,
        original_filename,
        mime,
        len(raw),
        digest[:12],
    )
    return jsonify({"message": "File stored", "file": meta.to_dict()}), 201


# ─── GET /api/files ──────────────────────────────────────────────────────────

@files_bp.route("", methods=["GET"])
@auth_required
def list_files():
    """List file metadata. Use project_id to scope to a single project."""
    try:
        user_id = int(get_jwt_identity())
    except (ValueError, TypeError):
        return jsonify({"error": "Invalid token identity"}), 401

    project_id_str = request.args.get("project_id", "").strip()
    if project_id_str:
        try:
            project_id = int(project_id_str)
        except ValueError:
            return jsonify({"error": "Invalid project_id"}), 400
        from models.project import Project

        if not Project.query.get(project_id):
            return jsonify({"error": "Project not found"}), 404
        if get_project_role(user_id, project_id) not in _READ_ROLES:
            return jsonify({"error": "Forbidden"}), 403
        from models.chat import ChatRoom, Message

        files_by_project = {
            f.id: f
            for f in FileMetadata.query.filter_by(project_id=project_id).all()
        }
        room_ids = [
            r.id
            for r in ChatRoom.query.filter_by(project_id=project_id).all()
        ]
        if room_ids:
            chat_file_ids = {
                row[0]
                for row in db.session.query(Message.file_id)
                .filter(
                    Message.room_id.in_(room_ids),
                    Message.file_id.isnot(None),
                )
                .distinct()
                .all()
            }
            for fid in chat_file_ids:
                if fid in files_by_project:
                    continue
                meta = db.session.get(FileMetadata, fid)
                if meta:
                    if meta.project_id is None:
                        meta.project_id = project_id
                    files_by_project[fid] = meta
            try:
                db.session.commit()
            except Exception:
                db.session.rollback()
        files = sorted(
            files_by_project.values(),
            key=lambda f: f.created_at or datetime.min.replace(tzinfo=timezone.utc),
            reverse=True,
        )
    else:
        files = (
            FileMetadata.query.filter_by(owner_id=user_id, project_id=None)
            .order_by(FileMetadata.created_at.desc())
            .all()
        )
    return jsonify({"files": [f.to_dict() for f in files]}), 200


# ─── GET /api/files/<id> ─────────────────────────────────────────────────────

@files_bp.route("/<file_id>", methods=["GET"])
@auth_required
def download_file(file_id: str):
    """
    Download a file. The on-disk ciphertext is decrypted and the SHA-256 of the
    plaintext is verified against the hash stored at upload time.  A mismatch
    raises a `file_integrity_failure` Alert and returns HTTP 409.
    ---
    tags: [Files]
    security: [{Bearer: []}]
    parameters:
      - {in: path, name: file_id, type: string, required: true}
    responses:
    responses:
      200:
        description: Decrypted file stream
        produces:
          - application/octet-stream
        schema:
          type: file
      403:
        description: Not the owner
        schema:
          type: object
          properties:
            error:
              type: string
      404:
        description: Not found
        schema:
          type: object
          properties:
            error:
              type: string
      409:
        description: Integrity check failed
        schema:
          type: object
          properties:
            error:
              type: string
    """
    try:
        fid = int(file_id)
    except (ValueError, AttributeError):
        return jsonify({"error": "Invalid file_id"}), 400

    meta = FileMetadata.query.filter_by(id=fid).first()
    if not meta:
        return jsonify({"error": "Not Found"}), 404

    # Owner-or-admin only
    try:
        caller_id = int(get_jwt_identity())
    except (ValueError, TypeError):
        return jsonify({"error": "Invalid token identity"}), 401

    caller = User.query.filter_by(id=caller_id).first()
    is_admin = bool(caller and caller.role == "admin")
    if meta.owner_id != caller_id and not is_admin:
        if meta.project_id:
            if get_project_role(caller_id, meta.project_id) not in _READ_ROLES:
                return jsonify({"error": "Forbidden"}), 403
        else:
            return jsonify({"error": "Forbidden"}), 403

    # Read ciphertext from disk
    try:
        with open(meta.encrypted_path, "rb") as fh:
            ciphertext = fh.read()
    except FileNotFoundError:
        # The encrypted file is gone but the row exists → integrity failure.
        _raise_integrity_alert(meta, reason="encrypted file missing on disk")
        return jsonify({"error": "Integrity check failed"}), 409

    # Decrypt
    try:
        plaintext = decrypt_bytes(ciphertext)
    except InvalidToken:
        _raise_integrity_alert(meta, reason="ciphertext failed Fernet validation")
        return jsonify({"error": "Integrity check failed"}), 409

    # Verify SHA-256 (constant-time)
    if not verify_hash(meta.sha256_hash, plaintext):
        _raise_integrity_alert(meta, reason="SHA-256 hash mismatch on download")
        return jsonify({"error": "Integrity check failed"}), 409

    return send_file(
        io.BytesIO(plaintext),
        mimetype=meta.mime_type,
        as_attachment=True,
        download_name=meta.original_filename,
    )


# ─── DELETE /api/files/<id> ──────────────────────────────────────────────────

@files_bp.route("/<file_id>", methods=["DELETE"])
@auth_required
def delete_file(file_id: str):
    """Delete a file (owner or admin). Removes ciphertext from disk and DB row."""
    try:
        fid = int(file_id)
    except (ValueError, AttributeError):
        return jsonify({"error": "Invalid file_id"}), 400

    meta = FileMetadata.query.filter_by(id=fid).first()
    if not meta:
        return jsonify({"error": "Not Found"}), 404

    try:
        caller_id = int(get_jwt_identity())
    except (ValueError, TypeError):
        return jsonify({"error": "Invalid token identity"}), 401

    caller = User.query.filter_by(id=caller_id).first()
    is_admin = bool(caller and caller.role == "admin")
    if meta.owner_id != caller_id and not is_admin:
        return jsonify({"error": "Forbidden"}), 403

    if meta.encrypted_path and os.path.isfile(meta.encrypted_path):
        try:
            os.remove(meta.encrypted_path)
        except OSError as exc:
            logger.warning("Could not remove encrypted file %s: %s", meta.encrypted_path, exc)

    db.session.delete(meta)
    db.session.commit()
    return jsonify({"message": "File deleted", "id": fid}), 200


def _raise_integrity_alert(meta: FileMetadata, *, reason: str) -> None:
    """Persist a tamper-detection alert. Never raises."""
    try:
        alert = Alert(
            type="file_integrity_failure",
            description=(
                f"Integrity check failed for file {meta.id} "
                f"(owner={meta.owner_id}, name={meta.original_filename}): {reason}"
            ),
        )
        db.session.add(alert)
        db.session.commit()
    except Exception:
        db.session.rollback()
        try:
            current_app.logger.exception("Failed to write integrity alert")
        except Exception:
            pass
