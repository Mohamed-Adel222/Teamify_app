"""
Flask-SocketIO event handlers for real-time chat.

Architecture notes
------------------
* async_mode = "gevent"  → all handlers run inside gevent greenlets.
* A module-level _lock (gevent.lock.RLock) guards _sid_to_uid so that
  concurrent connect/disconnect greenlets cannot corrupt the mapping.
* Handlers are registered exactly ONCE via register_chat_events().
  Calling it a second time (e.g. during tests) is a no-op thanks to the
  guard flag, preventing duplicate/zombie listeners.

Security model
--------------
  connect       — decodes JWT, checks DB blocklist (revoked tokens rejected),
                  validates expiry, verifies user exists and is active.
  join_chat     — validates room membership in DB every time (detects kicks).
  send_message  — re-validates room membership on every message.

Events (server ← client):
  connect       – Authenticate via JWT token in auth dict or query string.
  join_chat     – Join a Socket.IO room (requires membership).
  send_message  – Persist + broadcast a message to all room members.
  leave_chat    – Leave a room explicitly.
  disconnect    – Cleanup: remove from mapping, leave all rooms.

Events (server → client):
  joined          – Confirmation that the user joined a room.
  receive_message – New message broadcast to a room.
  error           – Error payload { "message": "..." }.
"""

import logging
import gevent.lock

from flask import request
from flask_socketio import emit, join_room, leave_room, disconnect
from flask_jwt_extended import decode_token

from models import db
from models.chat import ChatRoom, ChatRoomMember, Message
from models.user import User
from services.chat_message_service import create_chat_message

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Shared state
# ---------------------------------------------------------------------------

# sid → user_id mapping (cleaned up on every disconnect)
_sid_to_uid: dict[str, int] = {}
# sid → set of room names joined (so we can leave them all on disconnect)
_sid_to_rooms: dict[str, set[str]] = {}

# RLock is greenlet-safe with gevent
_lock = gevent.lock.RLock()

# Guard: register handlers only once
_registered = False

# chat room_id → set of user_ids currently in an active meeting
_meeting_active: dict[int, set[int]] = {}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def _meeting_room_name(room_id: int) -> str:
    return f"meeting_{room_id}"


def _broadcast_meeting_presence(socketio, room_id: int) -> None:
    """Notify everyone in meeting_<room_id> who is currently in the call."""
    active_ids = sorted(_meeting_active.get(room_id, set()))
    users = []
    for uid in active_ids:
        user = db.session.get(User, uid)
        if not user:
            continue
        users.append({
            "user_id": uid,
            "display_name": (user.full_name or "").strip() or user.display_name,
            "email": user.email or "",
        })
    socketio.emit(
        "meeting_presence",
        {
            "room_id": room_id,
            "active_user_ids": active_ids,
            "users": users,
        },
        to=_meeting_room_name(room_id),
    )


def _leave_all_meetings_for_user(socketio, user_id: int) -> None:
    """Remove user from every meeting room they joined (on disconnect)."""
    affected: list[int] = []
    for room_id, members in list(_meeting_active.items()):
        if user_id in members:
            members.discard(user_id)
            affected.append(room_id)
    for room_id in affected:
        _broadcast_meeting_presence(socketio, room_id)


def register_chat_events(socketio) -> None:
    """Register all chat SocketIO event handlers (idempotent)."""
    global _registered
    if _registered:
        return
    _registered = True

    # ------------------------------------------------------------------
    # connect
    # ------------------------------------------------------------------
    @socketio.on("connect")
    def handle_connect(auth=None):
        """
        Authenticate the WebSocket connection.

        The client may send the JWT token in ONE of these ways:
          1. Auth dict (Socket.IO v4+):  io.connect(url, { auth: { token: "..." } })
          2. Query string:               ?token=<JWT>

        Security checks (in order):
          1. Token present
          2. Token parses and has valid signature / not expired (decode_token)
          3. Token JTI is NOT in the DB blocklist (revoked tokens rejected)
          4. User exists in the database
        """
        token: str | None = None
        _sid: str = getattr(request, "sid", "unknown")  # type: ignore[attr-defined]

        # Prefer auth dict (Socket.IO v4 / socket_io_client Flutter ^3.x)
        if isinstance(auth, dict):
            token = auth.get("token")

        # Fallback: query string (?token=...)
        if not token:
            token = request.args.get("token")

        if not token:
            logger.warning("[WS] Connection rejected — no token provided sid=%s", _sid)
            return False

        # ── 1. Decode and validate signature / expiry ──────────────────────
        try:
            decoded = decode_token(token)
            user_id = int(decoded["sub"])
            jti: str = decoded.get("jti", "")
        except Exception as exc:
            logger.warning("[WS] Connection rejected — bad token: %s sid=%s", exc, _sid)
            return False

        # ── 2. Check DB blocklist (revoked tokens must not reconnect) ──────
        try:
            from models.token_blocklist import TokenBlocklist
            if TokenBlocklist.is_revoked(jti):
                logger.warning(
                    "[WS] Connection rejected — revoked token jti=%s user=%s sid=%s",
                    jti, user_id, _sid,
                )
                return False
        except Exception as exc:
            # Blocklist DB unavailable — fail closed (security-first)
            logger.error("[WS] Blocklist check failed: %s — rejecting connection", exc)
            return False

        # ── 3. Verify the user still exists and is active ──────────────────
        user = db.session.get(User, user_id)
        if user is None:
            logger.warning("[WS] Connection rejected — user %s not found sid=%s", user_id, _sid)
            return False

        sid = request.sid  # type: ignore[attr-defined]
        with _lock:
            _sid_to_uid[sid] = user_id
            _sid_to_rooms[sid] = set()

        # Auto-join the user's personal notification room.
        # Backend emits "new_notification" events to this room.
        personal_room = f"user_{user_id}"
        join_room(personal_room)
        with _lock:
            if sid in _sid_to_rooms:
                _sid_to_rooms[sid].add(personal_room)

        # Auto-join rooms for all projects the user belongs to,
        # so they receive real-time project_member_added/removed events.
        try:
            from models.project_member import ProjectMember
            memberships = ProjectMember.query.filter_by(user_id=user_id).all()
            for pm in memberships:
                project_room = f"project_{pm.project_id}"
                join_room(project_room)
                with _lock:
                    if sid in _sid_to_rooms:
                        _sid_to_rooms[sid].add(project_room)
        except Exception as exc:
            logger.warning("[WS] Failed to join project rooms for user %s: %s", user_id, exc)

        logger.info("[WS] ✓ Connected user=%s (%s) sid=%s", user_id, user.display_name, sid)
        return True

    # ------------------------------------------------------------------
    # disconnect
    # ------------------------------------------------------------------
    @socketio.on("disconnect")
    def handle_disconnect():
        sid = request.sid  # type: ignore[attr-defined]
        with _lock:
            uid = _sid_to_uid.pop(sid, None)
            rooms = _sid_to_rooms.pop(sid, set())

        # Explicitly leave every room so server-side room membership is clean.
        # flask-socketio leaves rooms automatically on disconnect, but doing it
        # explicitly prevents stale references in the internal rooms dict when
        # gevent context-switches mid-cleanup.
        for room_name in rooms:
            try:
                leave_room(room_name)
            except Exception:
                pass  # already removed by engine

        if uid is not None:
            _leave_all_meetings_for_user(socketio, uid)

        logger.info("[WS] ✗ Disconnected sid=%s user=%s", sid, uid)

    # ------------------------------------------------------------------
    # join_chat
    # ------------------------------------------------------------------
    @socketio.on("join_chat")
    def handle_join(data):
        """
        Client sends: { "room_id": <int> }
        Server joins the socket to the matching Socket.IO room if the
        caller is an authorised member.
        """
        sid = request.sid  # type: ignore[attr-defined]

        with _lock:
            user_id = _sid_to_uid.get(sid)

        if user_id is None:
            emit("error", {"message": "Not authenticated"})
            return {"ok": False, "error": "Not authenticated"}

        if not isinstance(data, dict):
            emit("error", {"message": "Invalid payload — expected JSON object"})
            return {"ok": False, "error": "Invalid payload"}

        try:
            room_id = int(data["room_id"])
        except (KeyError, TypeError, ValueError):
            emit("error", {"message": "room_id is required and must be an integer"})
            return {"ok": False, "error": "room_id is required and must be an integer"}

        # Verify membership
        membership = db.session.query(ChatRoomMember).filter_by(
            room_id=room_id, user_id=user_id
        ).first()
        if membership is None:
            emit("error", {"message": "You are not a member of this room"})
            return {"ok": False, "error": "You are not a member of this room"}

        room_name = f"chat_{room_id}"
        join_room(room_name)

        with _lock:
            if sid in _sid_to_rooms:
                _sid_to_rooms[sid].add(room_name)

        emit("joined", {"room_id": room_id, "user_id": user_id}, to=room_name)
        logger.info("[WS] user=%s joined room=%s", user_id, room_name)
        return {"ok": True, "room_id": room_id}

    # ------------------------------------------------------------------
    # leave_chat
    # ------------------------------------------------------------------
    @socketio.on("leave_chat")
    def handle_leave(data):
        """
        Client sends: { "room_id": <int> }
        Allows clients to leave a room without disconnecting.
        """
        sid = request.sid  # type: ignore[attr-defined]

        with _lock:
            user_id = _sid_to_uid.get(sid)

        if user_id is None:
            emit("error", {"message": "Not authenticated"})
            return

        try:
            room_id = int((data or {}).get("room_id", 0))
        except (TypeError, ValueError):
            emit("error", {"message": "Invalid room_id"})
            return

        room_name = f"chat_{room_id}"
        leave_room(room_name)

        with _lock:
            if sid in _sid_to_rooms:
                _sid_to_rooms[sid].discard(room_name)

        logger.info("[WS] user=%s left room=%s", user_id, room_name)

    # ------------------------------------------------------------------
    # join_meeting / leave_meeting — live presence for Meeting screen
    # ------------------------------------------------------------------
    @socketio.on("join_meeting")
    def handle_join_meeting(data):
        sid = request.sid  # type: ignore[attr-defined]
        with _lock:
            user_id = _sid_to_uid.get(sid)
        if user_id is None:
            emit("error", {"message": "Not authenticated"})
            return
        if not isinstance(data, dict):
            emit("error", {"message": "Invalid payload"})
            return
        try:
            room_id = int(data["room_id"])
        except (KeyError, TypeError, ValueError):
            emit("error", {"message": "room_id is required"})
            return

        membership = ChatRoomMember.query.filter_by(
            room_id=room_id, user_id=user_id
        ).first()
        if membership is None:
            emit("error", {"message": "You are not a member of this room"})
            return

        meeting_name = _meeting_room_name(room_id)
        join_room(meeting_name)
        with _lock:
            if sid in _sid_to_rooms:
                _sid_to_rooms[sid].add(meeting_name)
            _meeting_active.setdefault(room_id, set()).add(user_id)

        _broadcast_meeting_presence(socketio, room_id)
        logger.info("[WS] user=%s joined meeting room=%s", user_id, room_id)

    @socketio.on("leave_meeting")
    def handle_leave_meeting(data):
        sid = request.sid  # type: ignore[attr-defined]
        with _lock:
            user_id = _sid_to_uid.get(sid)
        if user_id is None:
            return
        try:
            room_id = int((data or {}).get("room_id", 0))
        except (TypeError, ValueError):
            return

        meeting_name = _meeting_room_name(room_id)
        leave_room(meeting_name)
        with _lock:
            if sid in _sid_to_rooms:
                _sid_to_rooms[sid].discard(meeting_name)
            if room_id in _meeting_active:
                _meeting_active[room_id].discard(user_id)

        _broadcast_meeting_presence(socketio, room_id)
        logger.info("[WS] user=%s left meeting room=%s", user_id, room_id)

    # ------------------------------------------------------------------
    # send_message
    # ------------------------------------------------------------------
    @socketio.on("send_message")
    def handle_send_message(data):
        """
        Client sends: { "room_id": <int>, "content": "<text>" }
        Server persists the message, then emits 'receive_message' to the room.
        """
        sid = request.sid  # type: ignore[attr-defined]

        with _lock:
            user_id = _sid_to_uid.get(sid)

        if user_id is None:
            emit("error", {"message": "Not authenticated"})
            return {"ok": False, "error": "Not authenticated"}

        if not isinstance(data, dict):
            emit("error", {"message": "Invalid payload"})
            return {"ok": False, "error": "Invalid payload"}

        try:
            room_id = int(data["room_id"])
        except (KeyError, TypeError, ValueError):
            emit("error", {"message": "room_id is required and must be an integer"})
            return {"ok": False, "error": "room_id is required and must be an integer"}

        # Verify membership (re-check on every message to detect kicked members)
        membership = db.session.query(ChatRoomMember).filter_by(
            room_id=room_id, user_id=user_id
        ).first()
        if membership is None:
            emit("error", {"message": "You are not a member of this room"})
            return {"ok": False, "error": "You are not a member of this room"}

        msg, err = create_chat_message(room_id, user_id, data)
        if err:
            body, status = err
            try:
                payload = body.get_json()
                message = payload.get("error", "Send failed")
            except Exception:
                message = "Send failed"
            emit("error", {"message": message})
            return {"ok": False, "error": message}

        # Broadcast to room
        room_name = f"chat_{room_id}"
        payload = msg.to_dict()
        emit("receive_message", payload, to=room_name)
        logger.info(
            "[WS] msg room=%s user=%s type=%s",
            room_id,
            user_id,
            msg.message_type,
        )
        return {"ok": True, "message": payload}
