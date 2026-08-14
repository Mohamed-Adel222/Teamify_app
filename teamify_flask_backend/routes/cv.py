"""
CV Routes  (/api/cv)

RBAC enforcement summary:
  POST   /api/cv                 – member creates/overwrites own CV
  GET    /api/cv/<id>            – member: own CV only | admin: any | guest: public CVs only
  PATCH  /api/cv/<id>            – member: own CV only | admin: any  | guest: 403
  GET    /api/cv/<id>/export/pdf – member: own CV only | admin: any  | guest: 403
                                   PDF delivered from RAM, never from disk.

IDOR protection:  every route resolves the CV's owner_id from the DB row
                  and compares it against the JWT identity before proceeding.
"""
from __future__ import annotations

import io
from functools import wraps
from typing import Any, cast

from flask import Blueprint, jsonify, request, send_file
from flask_jwt_extended import jwt_required, get_jwt_identity
from marshmallow import ValidationError

from app import limiter                          # module-level limiter (no circular import)
from middleware.auth import auth_required
from models import db
from models.cv import CV
from models.cv_download_token import CVDownloadToken
from models.user import User
from services.audit_log_service import log_security_event
from services.cv_ai_service import enhance_cv
from services.cv_pdf_service import build_cv_pdf
from validators.cv_validator import cv_create_schema

cv_bp = Blueprint("cv", __name__, url_prefix="/api/cv")


def _request_json() -> dict[str, Any]:
    payload = request.get_json(silent=True, force=True)
    return payload if isinstance(payload, dict) else {}


def _flatten_validation_messages(messages: Any) -> list[str]:
    """Turn Marshmallow nested error dicts into human-readable strings."""
    out: list[str] = []

    def walk(node: Any, prefix: str) -> None:
        if isinstance(node, dict):
            for key, val in node.items():
                path = f"{prefix}.{key}" if prefix else str(key)
                walk(val, path)
        elif isinstance(node, list):
            for item in node:
                if isinstance(item, str):
                    out.append(f"{prefix}: {item}" if prefix else item)
                else:
                    walk(item, prefix)
        elif isinstance(node, str):
            out.append(f"{prefix}: {node}" if prefix else node)

    walk(messages, "")
    return out


# ─── RBAC Helper ──────────────────────────────────────────────────────────────

def _resolve_caller() -> tuple[int, str]:
    """Return (user_id: int, role: str) for the current JWT identity."""
    uid  = int(get_jwt_identity())
    user = User.query.filter_by(id=uid).first()
    if not user:
        raise ValueError("User not found")
    return uid, user.role


def _can_write_cv(caller_id: int, caller_role: str, cv_owner_id: int) -> bool:
    """Returns True if the caller is allowed to create/update/delete this CV."""
    # SECURITY: admin has global write access; member only touches own CV; guest never writes.
    return caller_role == "admin" or (caller_role == "member" and caller_id == cv_owner_id)


def _can_read_cv(caller_id: int, caller_role: str, cv: CV) -> bool:
    """Returns True if the caller may read this CV (full detail)."""
    if caller_role == "admin":
        return True
    if caller_role == "member":
        return caller_id == cv.user_id
    # guest: only if the CV owner has set is_public = True
    if caller_role == "guest":
        return cv.is_public
    return False


# ─── POST /api/cv  — Create or replace own CV ─────────────────────────────────

@cv_bp.route("", methods=["POST"])
@jwt_required()
def create_or_update_cv():
    """
    Create (or fully replace) the authenticated user's CV.
    Runs AI enhancement (summary generation + relevance ranking) before saving.
    ---
    tags: [CV]
    security: [{Bearer: []}]
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
    responses:
      201:
        description: CV created / replaced successfully
      400:
        description: Validation error
      403:
        description: Guests cannot create CVs
    """
    try:
        caller_id, caller_role = _resolve_caller()
    except ValueError as exc:
        return jsonify({"error": "Unauthorized", "message": str(exc)}), 401

    # SECURITY: guests may never create or replace CVs
    if caller_role == "guest":
        return jsonify({"error": "Forbidden", "message": "Guests cannot create CVs."}), 403

    raw = _request_json()

    # Validate + sanitize via Marshmallow (XSS stripped inside schema's @pre_load)
    try:
        data = cast(dict[str, Any], cv_create_schema.load(raw))
    except ValidationError as err:
        flat = _flatten_validation_messages(err.messages)
        return jsonify({
            "error": "Validation Error",
            "message": flat[0] if flat else "Invalid CV data.",
            "messages": err.messages,
            "details": flat,
        }), 400

    # ── AI Enhancement ─────────────────────────────────────────────────────
    client_summary = data.get("summary")
    enhanced = enhance_cv(data)
    if client_summary:
        enhanced["summary"] = client_summary

    # ── Upsert: one CV per user ─────────────────────────────────────────────
    cv = CV.query.filter_by(user_id=caller_id).first()
    is_new = cv is None
    if is_new:
        cv = CV(user_id=caller_id)
        db.session.add(cv)

    cv.personal_info  = enhanced.get("personal_info", {})
    cv.summary        = enhanced.get("summary")
    cv.skills         = enhanced.get("skills", [])
    cv.experience     = enhanced.get("experience", [])
    cv.projects       = enhanced.get("projects", [])
    cv.education      = enhanced.get("education", [])
    cv.certifications = enhanced.get("certifications", [])
    cv.is_public      = enhanced.get("is_public", False)
    db.session.commit()

    log_security_event(
        "CV_GENERATED",
        user_id=caller_id,
        ip=request.remote_addr or "unknown",
        details={"cv_id": cv.id, "role": caller_role, "is_new": is_new},
    )

    return jsonify({"message": "CV saved successfully.", "cv": cv.to_dict()}), 201 if is_new else 200


# ─── GET /api/cv  — List readable CVs ─────────────────────────────────────────

@cv_bp.route("", methods=["GET"])
@jwt_required()
def list_cvs():
    """List CVs visible to the authenticated caller."""
    try:
        caller_id, caller_role = _resolve_caller()
    except ValueError as exc:
        return jsonify({"error": "Unauthorized", "message": str(exc)}), 401

    if caller_role == "admin":
        cvs = CV.query.order_by(CV.updated_at.desc()).all()
        return jsonify({"cvs": [cv.to_dict() for cv in cvs]}), 200

    if caller_role == "guest":
        cvs = CV.query.filter_by(is_public=True).order_by(CV.updated_at.desc()).all()
        return jsonify({"cvs": [cv.to_dict(public_only=True) for cv in cvs]}), 200

    cvs = CV.query.filter_by(user_id=caller_id).order_by(CV.updated_at.desc()).all()
    return jsonify({"cvs": [cv.to_dict() for cv in cvs]}), 200


# ─── GET /api/cv/<id>  — Read a CV ────────────────────────────────────────────

@cv_bp.route("/<int:cv_id>", methods=["GET"])
@jwt_required()
def get_cv(cv_id: int):
    """
    Retrieve a CV by ID.
    Members see only their own. Admins see any. Guests see public CVs only (redacted).
    ---
    tags: [CV]
    security: [{Bearer: []}]
    parameters:
      - in: path
        name: cv_id
        type: integer
        required: true
    responses:
      200:
        description: CV data
      403:
        description: Access denied (IDOR guard)
      404:
        description: CV not found
    """
    try:
        caller_id, caller_role = _resolve_caller()
    except ValueError as exc:
        return jsonify({"error": "Unauthorized", "message": str(exc)}), 401

    cv = CV.query.filter_by(id=cv_id).first()
    if not cv:
        return jsonify({"error": "Not Found", "message": "CV not found."}), 404

    # SECURITY: IDOR check — can this caller see this CV?
    if not _can_read_cv(caller_id, caller_role, cv):
        return jsonify({"error": "Forbidden", "message": "Access denied."}), 403

    # Guests receive a redacted public view
    public_only = (caller_role == "guest")
    return jsonify(cv.to_dict(public_only=public_only)), 200


# ─── GET /api/cv/by-user/<user_id>  — Read another member's CV ───────────────

def _can_view_member_cv(caller_role: str, cv: CV) -> bool:
    """Members and admins can view each other's CVs (talent discovery);
    guests only public ones."""
    if caller_role in ("admin", "member"):
        return True
    return cv.is_public


@cv_bp.route("/by-user/<int:user_id>", methods=["GET"])
@jwt_required()
def get_cv_by_user(user_id: int):
    """
    Retrieve the CV belonging to a given user (for profile views).
    ---
    tags: [CV]
    security: [{Bearer: []}]
    parameters:
      - in: path
        name: user_id
        type: integer
        required: true
    responses:
      200:
        description: CV data
      403:
        description: Access denied
      404:
        description: User has no CV
    """
    try:
        caller_id, caller_role = _resolve_caller()
    except ValueError as exc:
        return jsonify({"error": "Unauthorized", "message": str(exc)}), 401

    cv = CV.query.filter_by(user_id=user_id).first()
    if not cv:
        return jsonify({"error": "Not Found", "message": "This user has no CV."}), 404

    if not _can_view_member_cv(caller_role, cv):
        return jsonify({"error": "Forbidden", "message": "Access denied."}), 403

    public_only = caller_role == "guest" or caller_id != cv.user_id
    return jsonify(cv.to_dict(public_only=public_only)), 200


@cv_bp.route("/by-user/<int:user_id>/export/pdf", methods=["GET"])
@jwt_required()
@limiter.limit("5 per minute; 20 per hour")
def export_cv_pdf_by_user(user_id: int):
    """
    Generate and stream another member's CV as a PDF (profile download).
    ---
    tags: [CV]
    security: [{Bearer: []}]
    parameters:
      - in: path
        name: user_id
        type: integer
        required: true
    responses:
      200:
        description: PDF file download
      403:
        description: Forbidden
      404:
        description: User has no CV
    """
    try:
        caller_id, caller_role = _resolve_caller()
    except ValueError as exc:
        return jsonify({"error": "Unauthorized", "message": str(exc)}), 401

    if caller_role == "guest":
        return jsonify({"error": "Forbidden", "message": "Guests cannot export PDFs."}), 403

    cv = CV.query.filter_by(user_id=user_id).first()
    if not cv:
        return jsonify({"error": "Not Found", "message": "This user has no CV."}), 404

    try:
        pdf_buffer = build_cv_pdf(cv.to_dict())
    except Exception as exc:
        return jsonify({
            "error": "PDF Generation Failed",
            "message": str(exc),
        }), 500

    log_security_event(
        "CV_EXPORTED_PDF",
        user_id=caller_id,
        ip=request.remote_addr or "unknown",
        details={"cv_id": cv.id, "owner_id": cv.user_id, "role": caller_role},
    )

    owner_name = (cv.personal_info.get("full_name") or f"user_{cv.user_id}").replace(" ", "_")
    return send_file(
        pdf_buffer,
        mimetype="application/pdf",
        as_attachment=True,
        download_name=f"cv_{owner_name}.pdf",
    )


# ─── PATCH /api/cv/<id>  — Partial update ────────────────────────────────────

@cv_bp.route("/<int:cv_id>", methods=["PATCH"])
@jwt_required()
def update_cv(cv_id: int):
    """
    Partially update a CV (merge patch).
    Only the fields supplied are overwritten; omitted fields are preserved.
    ---
    tags: [CV]
    security: [{Bearer: []}]
    parameters:
      - in: path
        name: cv_id
        type: integer
        required: true
    responses:
      200:
        description: CV updated
      403:
        description: Forbidden (not owner or guest)
      404:
        description: CV not found
    """
    try:
        caller_id, caller_role = _resolve_caller()
    except ValueError as exc:
        return jsonify({"error": "Unauthorized", "message": str(exc)}), 401

    cv = CV.query.filter_by(id=cv_id).first()
    if not cv:
        return jsonify({"error": "Not Found", "message": "CV not found."}), 404

    # SECURITY: IDOR + role guard
    if not _can_write_cv(caller_id, caller_role, cv.user_id):
        return jsonify({"error": "Forbidden", "message": "You cannot edit this CV."}), 403

    raw = _request_json()

    # Validate only the supplied fields
    try:
        data = cast(dict[str, Any], cv_create_schema.load(raw, partial=True))
    except ValidationError as err:
        flat = _flatten_validation_messages(err.messages)
        return jsonify({
            "error": "Validation Error",
            "message": flat[0] if flat else "Invalid CV data.",
            "messages": err.messages,
            "details": flat,
        }), 400

    try:
        field_map = {
            "personal_info": "personal_info",
            "summary":       "summary",
            "skills":        "skills",
            "experience":    "experience",
            "projects":      "projects",
            "education":     "education",
            "certifications":"certifications",
            "is_public":     "is_public",
        }
        for key, col in field_map.items():
            if key in data:
                setattr(cv, col, data[key])

        if any(k in data for k in ("experience", "projects")):
            from services.cv_ai_service import rank_by_relevance
            ranked = rank_by_relevance(cv.to_dict())
            cv.experience = ranked["experience"]
            cv.projects   = ranked["projects"]

        db.session.commit()
    except Exception as exc:
        db.session.rollback()
        import logging
        logging.getLogger(__name__).error("update_cv error: %s", exc, exc_info=True)
        return jsonify({"error": "Update Failed", "message": str(exc)}), 500

    return jsonify({"message": "CV updated.", "cv": cv.to_dict()}), 200


# ─── DELETE /api/cv/<id>  — Remove own CV ─────────────────────────────────────

@cv_bp.route("/<int:cv_id>", methods=["DELETE"])
@jwt_required()
def delete_cv(cv_id: int):
    """Delete a CV. Members may only delete their own."""
    try:
        caller_id, caller_role = _resolve_caller()
    except ValueError as exc:
        return jsonify({"error": "Unauthorized", "message": str(exc)}), 401

    if caller_role == "guest":
        return jsonify({"error": "Forbidden", "message": "Guests cannot delete CVs."}), 403

    cv = CV.query.filter_by(id=cv_id).first()
    if not cv:
        return jsonify({"error": "Not Found", "message": "CV not found."}), 404

    if not _can_write_cv(caller_id, caller_role, cv.user_id):
        return jsonify({"error": "Forbidden", "message": "You cannot delete this CV."}), 403

    CVDownloadToken.query.filter_by(cv_id=cv_id).delete()
    db.session.delete(cv)
    db.session.commit()

    log_security_event(
        "CV_DELETED",
        user_id=caller_id,
        ip=request.remote_addr or "unknown",
        details={"cv_id": cv_id},
    )
    return jsonify({"message": "CV deleted."}), 200


# ─── GET /api/cv/<id>/export/pdf  — Secure PDF export ────────────────────────
#
# SECURITY: Rate-limited per IP (5 exports per minute) to prevent DoS /
# resource exhaustion from ReportLab's CPU-bound rendering loop.
# The PDF buffer lives entirely in RAM; no temp file is created.

@cv_bp.route("/<int:cv_id>/export/pdf", methods=["GET"])
@jwt_required()
@limiter.limit("5 per minute; 20 per hour")   # strict per-IP throttle on the expensive op
def export_cv_pdf(cv_id: int):
    """
    Generate and stream a CV as a PDF.
    Authentication + authorisation are verified BEFORE any rendering begins.
    PDF is served in-memory via send_file — never written to a public path.
    ---
    tags: [CV]
    security: [{Bearer: []}]
    parameters:
      - in: path
        name: cv_id
        type: integer
        required: true
    responses:
      200:
        description: PDF file download
        content:
          application/pdf:
            schema:
              type: string
              format: binary
      403:
        description: Forbidden (not owner, guest, or wrong role)
      404:
        description: CV not found
      429:
        description: Rate limit exceeded
    """
    try:
        caller_id, caller_role = _resolve_caller()
    except ValueError as exc:
        return jsonify({"error": "Unauthorized", "message": str(exc)}), 401

    # SECURITY: guests are explicitly blocked from PDF export
    if caller_role == "guest":
        log_security_event(
            "CV_EXPORT_DENIED",
            user_id=caller_id,
            ip=request.remote_addr or "unknown",
            severity="WARNING",
            details={"cv_id": cv_id, "reason": "guest role", "role": caller_role},
        )
        return jsonify({"error": "Forbidden", "message": "Guests cannot export PDFs."}), 403

    cv = CV.query.filter_by(id=cv_id).first()
    if not cv:
        return jsonify({"error": "Not Found", "message": "CV not found."}), 404

    # SECURITY: IDOR check — member may only export their own CV
    if not _can_write_cv(caller_id, caller_role, cv.user_id):
        log_security_event(
            "CV_EXPORT_DENIED",
            user_id=caller_id,
            ip=request.remote_addr or "unknown",
            severity="WARNING",
            details={"cv_id": cv_id, "owner_id": cv.user_id, "reason": "not owner"},
        )
        return jsonify({"error": "Forbidden", "message": "You cannot export this CV."}), 403

    # ── Build PDF in RAM ────────────────────────────────────────────────────
    try:
        pdf_buffer = build_cv_pdf(cv.to_dict())
    except Exception as exc:
        return jsonify({
            "error": "PDF Generation Failed",
            "message": str(exc),
        }), 500

    # Audit-log the successful export
    log_security_event(
        "CV_EXPORTED_PDF",
        user_id=caller_id,
        ip=request.remote_addr or "unknown",
        details={"cv_id": cv_id, "owner_id": cv.user_id, "role": caller_role},
    )

    owner_name = (cv.personal_info.get("full_name") or f"user_{cv.user_id}").replace(" ", "_")
    filename   = f"cv_{owner_name}.pdf"

    # SECURITY: Content-Disposition=attachment forces a download (no inline rendering).
    # X-Content-Type-Options is set globally in app.py (nosniff).
    return send_file(
        pdf_buffer,
        mimetype="application/pdf",
        as_attachment=True,
        download_name=filename,
    )


# ─── POST /api/cv/<id>/export  — Generate signed download link ───────────────

@cv_bp.route("/<int:cv_id>/export", methods=["POST"])
@jwt_required()
@limiter.limit("5 per minute")
def create_cv_download_link(cv_id: int):
    """
    Generate a time-limited signed download URL for a CV PDF.
    Returns a token valid for 15 minutes. Use GET /api/cv/download/<token>.
    ---
    tags: [CV]
    security: [{Bearer: []}]
    responses:
      201:
        description: Download link created
      403:
        description: Forbidden
      404:
        description: CV not found
    """
    try:
        caller_id, caller_role = _resolve_caller()
    except ValueError as exc:
        return jsonify({"error": "Unauthorized", "message": str(exc)}), 401

    if caller_role == "guest":
        return jsonify({"error": "Forbidden", "message": "Guests cannot export PDFs."}), 403

    cv = CV.query.filter_by(id=cv_id).first()
    if not cv:
        return jsonify({"error": "Not Found", "message": "CV not found."}), 404

    if not _can_write_cv(caller_id, caller_role, cv.user_id):
        log_security_event(
            "UNAUTHORIZED_CV_EXPORT_ATTEMPT",
            user_id=caller_id,
            ip=request.remote_addr or "unknown",
            severity="WARNING",
            details={"cv_id": cv_id, "owner_id": cv.user_id},
        )
        return jsonify({"error": "Forbidden", "message": "You cannot export this CV."}), 403

    token_obj = CVDownloadToken.create_token(user_id=caller_id, cv_id=cv_id)

    log_security_event(
        "CV_EXPORT_TOKEN_CREATED",
        user_id=caller_id,
        ip=request.remote_addr or "unknown",
        details={"cv_id": cv_id, "token_id": token_obj.id},
    )

    return jsonify({
        "message": "CV generated successfully",
        "download_url": f"/api/cv/download/{token_obj.token}",
        "expires_in": "15 minutes",
    }), 201


# ─── GET /api/cv/download/<token>  — Secure token-based PDF download ─────────

@cv_bp.route("/download/<string:token>", methods=["GET"])
@jwt_required()
@limiter.limit("10 per minute")
def download_cv_by_token(token: str):
    """
    Download a CV PDF using a signed token.
    Verifies token ownership, expiry, and single-use before streaming.
    ---
    tags: [CV]
    security: [{Bearer: []}]
    responses:
      200:
        description: PDF file download
      403:
        description: Token belongs to another user
      404:
        description: Invalid download link
      410:
        description: Download link expired
    """
    try:
        caller_id, caller_role = _resolve_caller()
    except ValueError as exc:
        return jsonify({"error": "Unauthorized", "message": str(exc)}), 401

    token_obj = CVDownloadToken.query.filter_by(token=token).first()
    if not token_obj:
        return jsonify({"error": "Not Found", "message": "Invalid download link"}), 404

    # SECURITY: ownership check — only the token creator can download
    if token_obj.user_id != caller_id and caller_role != "admin":
        log_security_event(
            "UNAUTHORIZED_CV_DOWNLOAD_ATTEMPT",
            user_id=caller_id,
            ip=request.remote_addr or "unknown",
            severity="WARNING",
            details={"token_id": token_obj.id, "owner_id": token_obj.user_id},
        )
        return jsonify({"error": "Forbidden", "message": "Forbidden"}), 403

    if token_obj.is_expired:
        return jsonify({"error": "Gone", "message": "Download link expired"}), 410

    if token_obj.used:
        return jsonify({"error": "Gone", "message": "Download link already used"}), 410

    cv = CV.query.filter_by(id=token_obj.cv_id).first()
    if not cv:
        return jsonify({"error": "Not Found", "message": "CV not found"}), 404

    # Mark token as consumed (single-use)
    token_obj.used = True
    db.session.commit()

    pdf_buffer = build_cv_pdf(cv.to_dict())

    log_security_event(
        "CV_DOWNLOADED",
        user_id=caller_id,
        ip=request.remote_addr or "unknown",
        details={"cv_id": cv.id, "token_id": token_obj.id},
    )

    owner_name = (cv.personal_info.get("full_name") or f"user_{cv.user_id}").replace(" ", "_")
    return send_file(
        pdf_buffer,
        mimetype="application/pdf",
        as_attachment=True,
        download_name=f"cv_{owner_name}.pdf",
    )

