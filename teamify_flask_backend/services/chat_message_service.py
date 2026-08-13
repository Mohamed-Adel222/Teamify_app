"""Create chat messages (text + file attachments)."""
from __future__ import annotations

from typing import Any, Optional, Tuple

from flask import jsonify

from models import db
from models.chat import ChatRoom, Message
from models.file_metadata import FileMetadata


def create_chat_message(
    room_id: int,
    sender_id: int,
    data: dict[str, Any],
) -> Tuple[Optional[Message], Optional[Tuple[Any, int]]]:
    """
    Validate payload and persist a Message.
    Returns (message, None) or (None, (response, status_code)).
    """
    content = (data.get("content") or "").strip()
    message_type = (data.get("message_type") or "text").strip().lower()
    if message_type not in ("text", "image", "file"):
        message_type = "text"

    file_id: Optional[int] = None
    raw_file = data.get("file_id")
    if raw_file is not None and str(raw_file).strip() != "":
        try:
            file_id = int(raw_file)
        except (TypeError, ValueError):
            return None, (jsonify({"error": "Invalid file_id"}), 400)

        meta = db.session.get(FileMetadata, file_id)
        if not meta or int(meta.owner_id) != int(sender_id):
            return None, (jsonify({"error": "File not found or not owned by you"}), 403)

        if not content:
            content = (meta.original_filename or "Attachment").strip()
        if message_type == "text":
            mime = (meta.mime_type or "").lower()
            message_type = "image" if mime.startswith("image/") else "file"

    if message_type == "text" and not content:
        return None, (jsonify({"error": "content is required"}), 400)
    if message_type in ("image", "file") and file_id is None:
        return None, (jsonify({"error": "file_id is required for attachments"}), 400)

    raw_key = data.get("idempotency_key")
    idempotency_key = str(raw_key).strip()[:64] if raw_key else None
    if idempotency_key == "":
        idempotency_key = None
    if idempotency_key:
        existing = Message.query.filter_by(
            room_id=room_id,
            sender_id=sender_id,
            idempotency_key=idempotency_key,
        ).first()
        if existing is not None:
            return existing, None

    room = db.session.get(ChatRoom, room_id)
    if file_id is not None and room and room.project_id:
        meta = db.session.get(FileMetadata, file_id)
        if meta and meta.project_id is None:
            meta.project_id = room.project_id

    msg = Message(
        room_id=room_id,
        sender_id=sender_id,
        content=content,
        message_type=message_type,
        file_id=file_id,
        idempotency_key=idempotency_key,
    )
    db.session.add(msg)
    db.session.commit()
    return msg, None


def delete_chat_message(
    room_id: int,
    message_id: int,
    user_id: int,
) -> Tuple[bool, Optional[Tuple[Any, int]]]:
    """
    Delete a message if the user is the sender and a room member.
    Returns (True, None) or (False, (response, status_code)).
    """
    msg = Message.query.filter_by(id=message_id, room_id=room_id).first()
    if not msg:
        return False, (jsonify({"error": "Message not found"}), 404)
    if int(msg.sender_id) != int(user_id):
        return False, (jsonify({"error": "You can only delete your own messages"}), 403)

    db.session.delete(msg)
    db.session.commit()
    return True, None
