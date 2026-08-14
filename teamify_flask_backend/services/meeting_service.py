"""Create, authorize, and lifecycle-manage Teamify meetings."""
from __future__ import annotations

import logging
from datetime import datetime, timezone
from uuid import uuid4

from sqlalchemy.exc import IntegrityError

from models import db
from models.chat import ChatRoom, ChatRoomMember
from models.meeting import Meeting, MeetingParticipant
from models.meeting_session import MeetingSession
from models.user import User
from routes.notifications import create_notification
from services.livekit_token_service import (
    create_meeting_access_token,
    delete_livekit_room,
    livekit_configured,
    livekit_url,
)
from services.project_access import user_has_project_access

logger = logging.getLogger(__name__)


def _now():
    return datetime.now(timezone.utc)


def _display_name(user: User | None) -> str:
    if user is None:
        return "Someone"
    return (user.full_name or user.display_name or user.email or "Someone").strip()


def user_can_access_meeting(user_id: int, meeting: Meeting) -> bool:
    if meeting.host_user_id == user_id:
        return True
    row = MeetingParticipant.query.filter_by(
        meeting_id=meeting.id, user_id=user_id
    ).first()
    if row is not None:
        return True
    membership = ChatRoomMember.query.filter_by(
        room_id=meeting.chat_room_id, user_id=user_id
    ).first()
    return membership is not None


def get_meeting_by_public_id(public_id: str) -> Meeting | None:
    if not public_id:
        return None
    return Meeting.query.filter_by(public_id=public_id.strip()).first()


def list_meetings_for_user(user_id: int) -> list[Meeting]:
    hosted_ids = [
        m.id for m in Meeting.query.filter_by(host_user_id=user_id).all()
    ]
    member_ids = [
        p.meeting_id
        for p in MeetingParticipant.query.filter_by(user_id=user_id).all()
    ]
    room_ids = [
        m.room_id for m in ChatRoomMember.query.filter_by(user_id=user_id).all()
    ]
    live_in_rooms: list[int] = []
    if room_ids:
        live_in_rooms = [
            m.id
            for m in Meeting.query.filter(
                Meeting.chat_room_id.in_(room_ids),
                Meeting.status == "live",
            ).all()
        ]
    ids = list({*hosted_ids, *member_ids, *live_in_rooms})
    if not ids:
        return []
    return (
        Meeting.query.filter(Meeting.id.in_(ids))
        .order_by(Meeting.created_at.desc())
        .limit(100)
        .all()
    )


def _ensure_participant(meeting: Meeting, user_id: int, role: str) -> MeetingParticipant:
    row = MeetingParticipant.query.filter_by(
        meeting_id=meeting.id, user_id=user_id
    ).first()
    if row:
        if role == "host":
            row.role = "host"
        return row
    row = MeetingParticipant(
        meeting_id=meeting.id,
        user_id=user_id,
        role=role,
        invite_status="invited",
    )
    db.session.add(row)
    return row


def create_instant_meeting(
    *,
    host_user_id: int,
    chat_room_id: int,
    title: str | None = None,
    project_id: int | None = None,
) -> tuple[Meeting | None, str | None, int]:
    """Create or reuse a live meeting for a chat room. Returns (meeting, error, status)."""
    membership = ChatRoomMember.query.filter_by(
        room_id=chat_room_id, user_id=host_user_id
    ).first()
    if membership is None:
        return None, "You are not a member of this chat room", 403

    room = db.session.get(ChatRoom, chat_room_id)
    if room is None:
        return None, "Chat room not found", 404

    resolved_project = project_id or room.project_id
    if project_id is not None:
        if room.project_id and int(room.project_id) != int(project_id):
            return None, "Chat room does not belong to this project", 400
        if not user_has_project_access(host_user_id, project_id):
            return None, "You are not a member of this project", 403

    live = _live_meeting_for_room(chat_room_id)
    if live is not None:
        _ensure_participant(
            live,
            host_user_id,
            "host" if live.host_user_id == host_user_id else "participant",
        )
        db.session.commit()
        return live, None, 200

    public_id = str(uuid4())
    meeting = Meeting(
        public_id=public_id,
        title=(title or room.name or "Team meeting").strip() or "Team meeting",
        status="live",
        starts_at=_now(),
        host_user_id=host_user_id,
        project_id=resolved_project,
        chat_room_id=chat_room_id,
        provider="livekit",
        provider_room=f"teamify_{public_id}",
    )
    db.session.add(meeting)
    try:
        db.session.flush()
    except IntegrityError:
        db.session.rollback()
        live = _live_meeting_for_room(chat_room_id)
        if live is not None:
            _ensure_participant(
                live,
                host_user_id,
                "host" if live.host_user_id == host_user_id else "participant",
            )
            db.session.commit()
            return live, None, 200
        return None, "Could not create meeting", 409

    _ensure_participant(meeting, host_user_id, "host")
    for member in ChatRoomMember.query.filter_by(room_id=chat_room_id).all():
        role = "host" if member.user_id == host_user_id else "participant"
        _ensure_participant(meeting, member.user_id, role)

    host = db.session.get(User, host_user_id)
    host_name = _display_name(host)
    for member in ChatRoomMember.query.filter_by(room_id=chat_room_id).all():
        if member.user_id == host_user_id:
            continue
        create_notification(
            user_id=member.user_id,
            notif_type="meeting_invite",
            title=f"{host_name} invited you to a meeting",
            body=(
                f'{host_name} started "{meeting.title}". '
                f"meeting:{meeting.public_id}"
            ),
            entity_type="Meeting",
            entity_id=meeting.id,
        )

    try:
        db.session.commit()
    except IntegrityError:
        db.session.rollback()
        live = _live_meeting_for_room(chat_room_id)
        if live is not None:
            _ensure_participant(
                live,
                host_user_id,
                "host" if live.host_user_id == host_user_id else "participant",
            )
            db.session.commit()
            return live, None, 200
        return None, "Could not create meeting", 409
    return meeting, None, 201


def _live_meeting_for_room(chat_room_id: int) -> Meeting | None:
    return (
        Meeting.query.filter_by(chat_room_id=chat_room_id, status="live")
        .order_by(Meeting.created_at.desc())
        .first()
    )


def issue_join_token(meeting: Meeting, user_id: int) -> tuple[dict | None, str | None, int]:
    if not user_can_access_meeting(user_id, meeting):
        return None, "Meeting not found", 404
    if meeting.status == "ended" or meeting.status == "cancelled":
        return None, "This meeting has ended", 409

    user = db.session.get(User, user_id)
    name = _display_name(user)
    is_host = meeting.host_user_id == user_id
    token, err = create_meeting_access_token(
        identity=str(user_id),
        name=name,
        room=meeting.provider_room,
        is_host=is_host,
    )
    if err:
        return None, err, 503

    row = _ensure_participant(meeting, user_id, "host" if is_host else "participant")
    row.invite_status = "joined"
    row.joined_at = row.joined_at or _now()
    row.left_at = None
    if meeting.status == "scheduled":
        meeting.status = "live"
        meeting.starts_at = meeting.starts_at or _now()
    db.session.commit()

    return {
        "url": livekit_url(),
        "token": token,
        "identity": str(user_id),
        "room": meeting.provider_room,
        "ttl_seconds": 7200,
        "configured": livekit_configured(),
        "meeting": meeting.to_dict(),
    }, None, 200


def leave_meeting(meeting: Meeting, user_id: int) -> tuple[dict | None, str | None, int]:
    if not user_can_access_meeting(user_id, meeting):
        return None, "Meeting not found", 404
    row = MeetingParticipant.query.filter_by(
        meeting_id=meeting.id, user_id=user_id
    ).first()
    if row:
        row.invite_status = "left"
        row.left_at = _now()
        db.session.commit()
    return {"ok": True, "meeting": meeting.to_dict()}, None, 200


def end_meeting(meeting: Meeting, user_id: int) -> tuple[dict | None, str | None, int]:
    if not user_can_access_meeting(user_id, meeting):
        return None, "Meeting not found", 404
    if meeting.host_user_id != user_id:
        return None, "Only the host can end this meeting", 403
    if meeting.status == "ended":
        return {"ok": True, "meeting": meeting.to_dict()}, None, 200

    meeting.status = "ended"
    meeting.ended_at = _now()
    for row in MeetingParticipant.query.filter_by(meeting_id=meeting.id).all():
        if row.invite_status == "joined":
            row.invite_status = "left"
            row.left_at = row.left_at or _now()

    provider_room = meeting.provider_room
    db.session.commit()
    try:
        delete_livekit_room(provider_room)
    except Exception as exc:
        logger.warning("LiveKit room close after host end failed: %s", exc)
    return {"ok": True, "meeting": meeting.to_dict()}, None, 200


def attach_session(meeting: Meeting, session: MeetingSession) -> None:
    session.meeting_id = meeting.id
    if meeting.project_id and not session.project_id:
        session.project_id = meeting.project_id
