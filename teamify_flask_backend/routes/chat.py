"""REST endpoints for chat rooms and message history."""
from __future__ import annotations

from datetime import datetime, timezone

from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt_identity

from middleware.auth import auth_required
from models import db
from models.chat import ChatRoom, ChatRoomMember, Message
from models.meeting_session import MeetingSession
from models.project import Project
from models.project_member import ProjectMember
from services.project_access import users_share_project
from models.user import User
from services.chat_message_service import create_chat_message, delete_chat_message
from services.chat_room_service import (
    add_room_member,
    ensure_project_chat_room,
    sync_all_project_rooms_for_user,
    sync_project_members_to_room,
)

chat_bp = Blueprint("chat", __name__, url_prefix="/api/chat")


def _dedupe_transcript(transcript: list) -> list:
    """Drop duplicate lines and browser-STT partial repeats."""
    out = []
    for item in transcript or []:
        if not isinstance(item, dict):
            continue
        content = (item.get("content") or item.get("text") or "").strip()
        if not content:
            continue
        entry = dict(item)
        entry["content"] = content
        if out and entry.get("source") == "speech":
            prev = out[-1]
            if prev.get("source") == "speech":
                prev_text = (prev.get("content") or "").strip()
                if content == prev_text:
                    continue
                if content.startswith(prev_text) and len(content) > len(prev_text):
                    out.pop()
                elif prev_text.startswith(content):
                    continue
        if any(
            (e.get("source") == entry.get("source"))
            and (e.get("content") or "").strip() == content
            and str(e.get("sender_id")) == str(entry.get("sender_id"))
            for e in out
        ):
            continue
        out.append(entry)
    return out


def _transcript_to_text(transcript: list) -> str:
    lines = []
    for item in transcript or []:
        if not isinstance(item, dict):
            continue
        name = (item.get("sender_name") or item.get("sender") or "User").strip()
        content = (item.get("content") or item.get("text") or "").strip()
        if content:
            lines.append(f"{name}: {content}")
    return "\n".join(lines)


def _summarize_meeting_transcript(transcript: list) -> dict:
    transcript = _dedupe_transcript(transcript)
    text = _transcript_to_text(transcript)
    speech_lines = []
    for item in transcript:
        if item.get("source") == "speech":
            name = (item.get("sender_name") or "User").strip()
            content = (item.get("content") or "").strip()
            if content:
                speech_lines.append(f"{name}: {content}")

    if not text.strip():
        return {
            "summary": "No speech or chat content was captured in this meeting.",
            "key_points": [],
            "action_items": [],
            "speech_transcript": speech_lines,
            "participants": [],
        }

    from services.chat_summarization_service import summarize_chat

    result = summarize_chat(text, top_n=5)
    result["speech_transcript"] = speech_lines
    # Prefer a short narrative summary over dumping raw speech.
    summary = (result.get("summary") or "").strip()
    if len(summary) > 520:
        cut = summary[:520]
        dot = cut.rfind(".")
        result["summary"] = cut[: dot + 1] if dot > 200 else cut + "…"
    return result


def _ensure_session_summary(session: MeetingSession) -> None:
    """Compute and persist AI summary when a session ended with transcript data."""
    if session.is_active:
        return
    if session.ai_summary and session.ai_summary.get("summary"):
        return
    summary = _summarize_meeting_transcript(session.transcript or [])
    if summary:
        session.ai_summary = summary
        db.session.commit()


def _room_channel(room_id: int) -> str:
    return f"chat_{room_id}"


def _broadcast_message(msg: Message) -> None:
    """Push a persisted message to connected WebSocket clients in the room."""
    try:
        from app import socketio

        socketio.emit(
            "receive_message",
            msg.to_dict(),
            to=_room_channel(msg.room_id),
        )
    except Exception:
        # REST path must succeed even if no WS clients are connected.
        pass


def _broadcast_message_deleted(room_id: int, message_id: int) -> None:
    """Notify room members that a message was removed."""
    try:
        from app import socketio

        socketio.emit(
            "message_deleted",
            {"room_id": room_id, "message_id": message_id},
            to=_room_channel(room_id),
        )
    except Exception:
        pass


# ── List rooms the current user belongs to ────────────────────────────────────
@chat_bp.route("/rooms", methods=["GET"])
@auth_required
def list_rooms():
    """
    List chat rooms the authenticated user belongs to.
    ---
    tags: [Chat]
    security: [{Bearer: []}]
    responses:
      200:
        description: Array of rooms
        schema:
          type: object
          properties:
            rooms:
              type: array
              items:
                type: object
    """
    user_id = int(get_jwt_identity())
    sync_all_project_rooms_for_user(user_id)
    db.session.commit()

    memberships = ChatRoomMember.query.filter_by(user_id=user_id).all()
    room_ids = [m.room_id for m in memberships]

    if not room_ids:
        return jsonify({"rooms": []}), 200

    rooms = ChatRoom.query.filter(ChatRoom.id.in_(room_ids)).all()
    return jsonify({
        "rooms": [r.to_dict(include_last_message=True) for r in rooms]
    }), 200


# ── Create a new chat room ────────────────────────────────────────────────────
@chat_bp.route("/rooms", methods=["POST"])
@auth_required
def create_room():
    """
    Create a new chat room and add the creator as a member.
    ---
    tags: [Chat]
    security: [{Bearer: []}]
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          properties:
            name: {type: string}
            project_id: {type: integer}
            is_group: {type: boolean}
            member_ids:
              type: array
              items: {type: integer}
    responses:
      201:
        description: Room created
      400:
        description: Validation error
    """
    user_id = int(get_jwt_identity())
    data = request.get_json(silent=True) or {}

    name = (data.get("name") or "").strip()
    if not name:
        return jsonify({"error": "name is required"}), 400

    project_id = data.get("project_id")
    if project_id is not None:
        try:
            project_id = int(project_id)
        except (TypeError, ValueError):
            return jsonify({"error": "project_id must be an integer"}), 400

        project = db.session.get(Project, project_id)
        if not project:
            return jsonify({"error": "Project not found"}), 404

        is_member = (
            project.user_id == user_id
            or ProjectMember.query.filter_by(
                project_id=project_id, user_id=user_id
            ).first()
            is not None
        )
        if not is_member:
            return jsonify({"error": "You are not a member of this project"}), 403

        room = ensure_project_chat_room(project, user_id)
        if name and room.name != name:
            room.name = name
        db.session.commit()
        return jsonify({
            "message": "Project team chat ready",
            "room": room.to_dict(),
        }), 200

    room = ChatRoom(
        name=name,
        project_id=project_id,
        is_group=data.get("is_group", False),
    )
    db.session.add(room)
    db.session.flush()  # get room.id

    # Add creator
    add_room_member(room.id, user_id)

    if project_id is not None:
        sync_project_members_to_room(room.id, project_id)

    # Add extra members (must share a project with the creator for non-project rooms)
    extra_ids = data.get("member_ids") or data.get("members") or []
    for mid in extra_ids:
        try:
            mid = int(mid)
        except (ValueError, TypeError):
            continue
        if mid == user_id:
            continue
        if not User.query.filter_by(id=mid).first():
            continue
        if not users_share_project(user_id, mid):
            return jsonify({
                "error": "Forbidden",
                "message": f"User {mid} must share a project with you to be added to a chat room",
            }), 403
        add_room_member(room.id, mid)

    db.session.commit()
    return jsonify({"message": "Room created", "room": room.to_dict()}), 201


# ── Find or create a 1:1 direct-message room ─────────────────────────────────
@chat_bp.route("/rooms/direct", methods=["POST"])
@auth_required
def open_direct_room():
    """
    Find (or create) the private 1:1 room between the caller and another user.
    Direct messages do not require a shared project — any member can DM
    another member (e.g. from the freelancer search screen).
    ---
    tags: [Chat]
    security: [{Bearer: []}]
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          properties:
            user_id: {type: integer}
    responses:
      200:
        description: Existing or newly created DM room
      404:
        description: Target user not found
    """
    user_id = int(get_jwt_identity())
    data = request.get_json(silent=True) or {}

    try:
        other_id = int(data.get("user_id"))
    except (TypeError, ValueError):
        return jsonify({"error": "user_id is required"}), 400

    if other_id == user_id:
        return jsonify({"error": "Cannot open a chat with yourself"}), 400

    other = db.session.get(User, other_id)
    if not other:
        return jsonify({"error": "User not found"}), 404

    # Existing non-group, non-project room whose members are exactly the pair.
    my_room_ids = [
        m.room_id
        for m in ChatRoomMember.query.filter_by(user_id=user_id).all()
    ]
    if my_room_ids:
        candidates = ChatRoom.query.filter(
            ChatRoom.id.in_(my_room_ids),
            ChatRoom.is_group.is_(False),
            ChatRoom.project_id.is_(None),
        ).all()
        for room in candidates:
            member_ids = {
                m.user_id
                for m in ChatRoomMember.query.filter_by(room_id=room.id).all()
            }
            if member_ids == {user_id, other_id}:
                return jsonify({
                    "message": "Existing direct chat",
                    "room": room.to_dict(include_last_message=True),
                }), 200

    me = db.session.get(User, user_id)
    my_name = (me.full_name or me.display_name) if me else "User"
    other_name = other.full_name or other.display_name or "User"

    room = ChatRoom(
        name=f"{my_name} & {other_name}",
        project_id=None,
        is_group=False,
    )
    db.session.add(room)
    db.session.flush()
    add_room_member(room.id, user_id)
    add_room_member(room.id, other_id)
    db.session.commit()

    return jsonify({
        "message": "Direct chat created",
        "room": room.to_dict(include_last_message=True),
    }), 201


# ── Get a single room with member profiles ────────────────────────────────────
@chat_bp.route("/rooms/<int:room_id>", methods=["GET"])
@auth_required
def get_room(room_id):
    """
    Fetch one chat room and its members (for meeting / participant UIs).
    ---
    tags: [Chat]
    security: [{Bearer: []}]
    parameters:
      - {in: path, name: room_id, type: integer, required: true}
    responses:
      200:
        description: Room and members
      403:
        description: Not a member
      404:
        description: Room not found
    """
    user_id = int(get_jwt_identity())

    room = db.session.get(ChatRoom, room_id)
    if not room:
        return jsonify({"error": "Room not found"}), 404

    membership = ChatRoomMember.query.filter_by(
        room_id=room_id, user_id=user_id
    ).first()
    if not membership:
        return jsonify({"error": "You are not a member of this room"}), 403

    members = []
    for m in ChatRoomMember.query.filter_by(room_id=room_id).all():
        user = db.session.get(User, m.user_id)
        if not user:
            continue
        members.append({
            "id": user.id,
            "user_id": user.id,
            "display_name": user.full_name or user.display_name or user.email,
            "full_name": user.full_name or "",
            "email": user.email,
            "user_type": user.user_type or "",
            "joined_at": m.joined_at.isoformat() if m.joined_at else None,
        })

    return jsonify({
        "room": room.to_dict(include_last_message=True),
        "members": members,
    }), 200


# ── Get message history for a room ────────────────────────────────────────────
@chat_bp.route("/rooms/<int:room_id>/messages", methods=["GET"])
@auth_required
def get_messages(room_id):
    """
    Fetch historical messages for a chat room, ordered by created_at ascending.
    Supports pagination via ?page=1&per_page=50
    ---
    tags: [Chat]
    security: [{Bearer: []}]
    parameters:
      - {in: path, name: room_id, type: integer, required: true}
      - {in: query, name: page, type: integer, required: false}
      - {in: query, name: per_page, type: integer, required: false}
    responses:
      200:
        description: Paginated messages
      403:
        description: Not a member of this room
      404:
        description: Room not found
    """
    user_id = int(get_jwt_identity())

    room = db.session.get(ChatRoom, room_id)
    if not room:
        return jsonify({"error": "Room not found"}), 404

    # Verify membership
    membership = ChatRoomMember.query.filter_by(
        room_id=room_id, user_id=user_id
    ).first()
    if not membership:
        return jsonify({"error": "You are not a member of this room"}), 403

    page = request.args.get("page", 1, type=int)
    per_page = min(request.args.get("per_page", 50, type=int), 100)

    pagination = (
        Message.query.filter_by(room_id=room_id)
        .order_by(Message.created_at.asc())
        .paginate(page=page, per_page=per_page, error_out=False)
    )

    return jsonify({
        "messages": [m.to_dict() for m in pagination.items],
        "page": pagination.page,
        "per_page": pagination.per_page,
        "total": pagination.total,
        "pages": pagination.pages,
    }), 200


# ── Send a message (REST fallback when WebSocket unavailable) ─────────────────
@chat_bp.route("/rooms/<int:room_id>/messages", methods=["POST"])
@auth_required
def send_message(room_id):
    """
    Persist a chat message via REST (fallback for clients without WebSocket).
    ---
    tags: [Chat]
    security: [{Bearer: []}]
    parameters:
      - {in: path, name: room_id, type: integer, required: true}
      - in: body
        name: body
        required: true
        schema:
          type: object
          required: [content]
          properties:
            content: {type: string}
            idempotency_key: {type: string}
    responses:
      201:
        description: Message created
      403:
        description: Not a member
      404:
        description: Room not found
    """
    user_id = int(get_jwt_identity())

    room = db.session.get(ChatRoom, room_id)
    if not room:
        return jsonify({"error": "Room not found"}), 404

    membership = ChatRoomMember.query.filter_by(
        room_id=room_id, user_id=user_id
    ).first()
    if not membership:
        return jsonify({"error": "You are not a member of this room"}), 403

    data = request.get_json(silent=True) or {}
    msg, err = create_chat_message(room_id, user_id, data)
    if err:
        return err
    if msg is None:
        return jsonify({"error": "Failed to create message"}), 500

    _broadcast_message(msg)

    return jsonify({"message": "Message sent", "data": msg.to_dict()}), 201


@chat_bp.route("/rooms/<int:room_id>/messages/<int:message_id>", methods=["DELETE"])
@auth_required
def delete_message(room_id, message_id):
    """Delete a chat message (sender only)."""
    user_id = int(get_jwt_identity())
    _, _, err = _require_room_member(user_id, room_id)
    if err:
        return err

    ok, del_err = delete_chat_message(room_id, message_id, user_id)
    if del_err:
        return del_err
    if not ok:
        return jsonify({"error": "Message not found"}), 404

    _broadcast_message_deleted(room_id, message_id)
    return jsonify({"message": "Message deleted", "message_id": message_id}), 200


def _require_room_member(user_id: int, room_id: int):
    """Return (room, membership) or (None, error_response)."""
    room = db.session.get(ChatRoom, room_id)
    if not room:
        return None, None, (jsonify({"error": "Room not found"}), 404)
    membership = ChatRoomMember.query.filter_by(
        room_id=room_id, user_id=user_id
    ).first()
    if not membership:
        return room, None, (jsonify({"error": "You are not a member of this room"}), 403)
    return room, membership, None


# ── Meeting sessions (persisted transcript) ───────────────────────────────────
@chat_bp.route("/rooms/<int:room_id>/meetings/start", methods=["POST"])
@auth_required
def start_meeting_session(room_id):
    """Start a persisted meeting session for this chat room."""
    user_id = int(get_jwt_identity())
    room, _, err = _require_room_member(user_id, room_id)
    if err:
        return err
    if room is None:
        return jsonify({"error": "Room not found"}), 404

    from datetime import datetime, timezone as tz
    now = datetime.now(tz.utc)

    active = MeetingSession.query.filter_by(room_id=room_id, is_active=True).first()
    if active:
        stale = (now - active.started_at.replace(tzinfo=tz.utc)).total_seconds() > 300 \
                if active.started_at else True
        if stale:
            active.is_active = False
            active.ended_at = now
            if active.started_at:
                active.duration_seconds = int(
                    (now - active.started_at.replace(tzinfo=tz.utc)).total_seconds()
                )
            db.session.flush()
        else:
            return jsonify({"session": active.to_dict()}), 200

    session = MeetingSession(
        room_id=room_id,
        project_id=room.project_id,
        started_by=user_id,
        is_active=True,
        started_at=now,
        transcript=[],
        participant_ids=[user_id],
    )
    db.session.add(session)
    db.session.commit()
    return jsonify({"session": session.to_dict()}), 201


@chat_bp.route("/rooms/<int:room_id>/meetings/<int:session_id>", methods=["GET"])
@auth_required
def get_meeting_session(room_id, session_id):
    """Fetch a saved meeting session (transcript, duration, participants)."""
    user_id = int(get_jwt_identity())
    _, _, err = _require_room_member(user_id, room_id)
    if err:
        return err

    session = MeetingSession.query.filter_by(id=session_id, room_id=room_id).first()
    if not session:
        return jsonify({"error": "Meeting session not found"}), 404

    _ensure_session_summary(session)
    return jsonify({"session": session.to_dict()}), 200


@chat_bp.route("/rooms/<int:room_id>/meetings/<int:session_id>/save", methods=["POST"])
@auth_required
def save_meeting_checkpoint(room_id, session_id):
    """Persist transcript while the meeting stays live (checkpoint save)."""
    user_id = int(get_jwt_identity())
    _, _, err = _require_room_member(user_id, room_id)
    if err:
        return err

    session = MeetingSession.query.filter_by(id=session_id, room_id=room_id).first()
    if not session:
        return jsonify({"error": "Meeting session not found"}), 404

    data = request.get_json(silent=True) or {}
    transcript = data.get("transcript")
    if transcript is None:
        transcript = session.transcript or []
    if not isinstance(transcript, list):
        return jsonify({"error": "transcript must be a list"}), 400

    participant_ids = data.get("participant_ids")
    if participant_ids is None:
        participant_ids = session.participant_ids or []
    if not isinstance(participant_ids, list):
        return jsonify({"error": "participant_ids must be a list"}), 400

    session.transcript = transcript
    session.participant_ids = [int(x) for x in participant_ids if str(x).isdigit()]
    session.is_active = True
    if session.started_at:
        started = session.started_at
        if started.tzinfo is None:
            started = started.replace(tzinfo=timezone.utc)
        session.duration_seconds = max(
            0,
            int((datetime.now(timezone.utc) - started).total_seconds()),
        )

    summary = _summarize_meeting_transcript(transcript)
    if summary:
        session.ai_summary = summary

    db.session.commit()
    return jsonify({"session": session.to_dict()}), 200


@chat_bp.route("/rooms/<int:room_id>/meetings/<int:session_id>/stop", methods=["POST"])
@auth_required
def stop_meeting_session(room_id, session_id):
    """End a meeting session and persist the captured chat transcript."""
    user_id = int(get_jwt_identity())
    _, _, err = _require_room_member(user_id, room_id)
    if err:
        return err

    session = MeetingSession.query.filter_by(id=session_id, room_id=room_id).first()
    if not session:
        return jsonify({"error": "Meeting session not found"}), 404
    if not session.is_active:
        return jsonify({"session": session.to_dict()}), 200

    data = request.get_json(silent=True) or {}
    transcript = data.get("transcript")
    if transcript is None:
        transcript = []
    if not isinstance(transcript, list):
        return jsonify({"error": "transcript must be a list"}), 400

    participant_ids = data.get("participant_ids") or []
    if not isinstance(participant_ids, list):
        return jsonify({"error": "participant_ids must be a list"}), 400

    now = datetime.now(timezone.utc)
    session.ended_at = now
    session.is_active = False
    session.transcript = transcript
    session.participant_ids = [int(x) for x in participant_ids if str(x).isdigit()]
    if session.started_at:
        started = session.started_at
        if started.tzinfo is None:
            started = started.replace(tzinfo=timezone.utc)
        session.duration_seconds = max(0, int((now - started).total_seconds()))

    summary = _summarize_meeting_transcript(transcript)
    if summary:
        session.ai_summary = summary

    db.session.commit()
    return jsonify({"session": session.to_dict()}), 200
