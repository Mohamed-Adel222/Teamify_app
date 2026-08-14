"""Create in-app + email notifications for chat messages and mentions.

Production delivery is backend-only. Flutter demo dispatchers are not used.
"""
from __future__ import annotations

import logging
import re
from typing import Iterable

from models import db
from models.chat import ChatRoom, ChatRoomMember, Message
from models.user import User
from routes.notifications import create_notification

logger = logging.getLogger(__name__)

_MENTION_RE = re.compile(r"@([A-Za-z0-9._\-]+)")


def _display_name(user: User | None) -> str:
    if not user:
        return "Someone"
    return (user.full_name or user.display_name or user.email or f"User {user.id}").strip()


def _preview(content: str, limit: int = 160) -> str:
    text = (content or "").strip().replace("\n", " ")
    if len(text) <= limit:
        return text
    return text[: limit - 1] + "…"


def _mentioned_user_ids(content: str, members: Iterable[User]) -> set[int]:
    tokens = {m.group(1).lower() for m in _MENTION_RE.finditer(content or "")}
    if not tokens:
        return set()
    matched: set[int] = set()
    for user in members:
        names = {
            (user.display_name or "").lower(),
            (user.full_name or "").lower(),
            (user.email or "").split("@")[0].lower(),
        }
        names.discard("")
        if tokens & names:
            matched.add(user.id)
    return matched


def notify_chat_message(msg: Message, sender_id: int) -> list[tuple[int, bool]]:
    """Create mention/DM notifications for a persisted chat message. Never raises."""
    try:
        room = db.session.get(ChatRoom, msg.room_id)
        if not room:
            return []
        memberships = ChatRoomMember.query.filter_by(room_id=msg.room_id).all()
        member_ids = [m.user_id for m in memberships if m.user_id != sender_id]
        if not member_ids:
            return []

        users = User.query.filter(User.id.in_(member_ids + [sender_id])).all()
        by_id = {u.id: u for u in users}
        sender = by_id.get(sender_id)
        sender_name = _display_name(sender)
        room_name = (room.name or "").strip() or ("Chat" if room.is_group else "Direct message")
        preview = _preview(msg.content or "")
        mentioned = _mentioned_user_ids(msg.content or "", [by_id[i] for i in member_ids if i in by_id])
        is_dm = (not room.is_group) or len(memberships) <= 2

        created: list[tuple[int, bool]] = []
        for uid in member_ids:
            is_mention = uid in mentioned
            if not is_mention and not is_dm:
                member = by_id.get(uid)
                prefs = getattr(member, "notification_prefs", None) if member else None
                from routes.notifications import _merged_preferences

                merged = _merged_preferences(prefs)
                if not merged.get("emailNewMessages"):
                    continue
            notif = create_notification(
                user_id=uid,
                notif_type="chat_mention" if is_mention else "message",
                title=f"{sender_name} mentioned you" if is_mention else f"New message from {sender_name}",
                body=preview or f"New message in {room_name}",
                entity_type="ChatRoom",
                entity_id=msg.room_id,
                queue_email=False,
                is_mention=is_mention,
            )
            if getattr(notif, "id", None):
                created.append((notif.id, is_mention))
        return created
    except Exception:
        logger.warning("Chat notification failed message_id=%s", getattr(msg, "id", None), exc_info=True)
        return []


def queue_chat_notification_emails(created: list[tuple[int, bool]]) -> None:
    """Queue email after the notification rows have been committed."""
    if not created:
        return
    try:
        from services.notification_email_service import queue_notification_email

        for notif_id, is_mention in created:
            queue_notification_email(notif_id, is_mention=is_mention)
    except Exception:
        logger.warning("Failed to queue chat notification emails", exc_info=True)
