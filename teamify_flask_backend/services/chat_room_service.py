"""Ensure project-linked team chat rooms exist for all project members."""
from __future__ import annotations

from models import db
from models.chat import ChatRoom, ChatRoomMember
from models.project import Project
from models.project_member import ProjectMember
from models.user import User


def direct_pair_key(user_a: int, user_b: int) -> str:
    lo, hi = (user_a, user_b) if user_a < user_b else (user_b, user_a)
    return f"{lo}:{hi}"


def add_room_member(room_id: int, user_id: int) -> None:
    exists = ChatRoomMember.query.filter_by(
        room_id=room_id, user_id=user_id
    ).first()
    if not exists:
        db.session.add(ChatRoomMember(room_id=room_id, user_id=user_id))


def sync_project_members_to_room(room_id: int, project_id: int) -> None:
    """Ensure all project members can access the linked chat room."""
    for pm in ProjectMember.query.filter_by(project_id=project_id).all():
        add_room_member(room_id, pm.user_id)


def ensure_project_chat_room(project: Project, acting_user_id: int) -> ChatRoom:
    """Return the team chat room for a project, creating it if needed."""
    room = ChatRoom.query.filter_by(project_id=project.id).first()
    if room is None:
        room = ChatRoom(
            name=project.name,
            project_id=project.id,
            is_group=True,
        )
        db.session.add(room)
        db.session.flush()

    add_room_member(room.id, acting_user_id)
    if project.user_id:
        add_room_member(room.id, project.user_id)
    sync_project_members_to_room(room.id, project.id)
    return room


def sync_all_project_rooms_for_user(user_id: int) -> None:
    """Create or refresh chat rooms for every project the user can access."""
    seen_ids: set[int] = set()
    projects: list[Project] = []

    for project in Project.query.filter_by(user_id=user_id).all():
        if project.id not in seen_ids:
            seen_ids.add(project.id)
            projects.append(project)

    for pm in ProjectMember.query.filter_by(user_id=user_id).all():
        if pm.project_id in seen_ids:
            continue
        project = db.session.get(Project, pm.project_id)
        if project is not None:
            seen_ids.add(project.id)
            projects.append(project)

    for project in projects:
        ensure_project_chat_room(project, user_id)


def find_direct_chat_room(user_a: int, user_b: int) -> ChatRoom | None:
    """Return the 1:1 room for two users, if it exists."""
    if user_a == user_b:
        return None
    key = direct_pair_key(user_a, user_b)
    room = ChatRoom.query.filter_by(direct_pair_key=key).first()
    if room is not None:
        return room

    # Legacy rooms created before direct_pair_key existed.
    a_ids = {
        m.room_id for m in ChatRoomMember.query.filter_by(user_id=user_a).all()
    }
    b_ids = {
        m.room_id for m in ChatRoomMember.query.filter_by(user_id=user_b).all()
    }
    shared = a_ids & b_ids
    if not shared:
        return None
    rooms = ChatRoom.query.filter(
        ChatRoom.id.in_(shared),
        ChatRoom.is_group.is_(False),
        ChatRoom.project_id.is_(None),
    ).all()
    for room in rooms:
        member_count = ChatRoomMember.query.filter_by(room_id=room.id).count()
        if member_count != 2:
            continue
        if not room.direct_pair_key:
            room.direct_pair_key = key
        return room
    return None


def ensure_direct_chat_room(user_a: int, user_b: int) -> tuple[ChatRoom | None, str | None]:
    """
    Find or create a 1:1 DM room between two registered users.

    Product rule (intentional): any two approved Teamify users may DM.
    Project membership is NOT required for direct messages. Team/project
    chats still require project membership via ensure_project_chat_room.
    """
    if user_a == user_b:
        return None, "Cannot start a direct message with yourself"
    other = db.session.get(User, user_b)
    if other is None:
        return None, "User not found"
    status = (other.account_status or "approved").lower()
    if status in {"locked", "banned", "deleted"}:
        return None, "This user is not available"

    existing = find_direct_chat_room(user_a, user_b)
    if existing is not None:
        add_room_member(existing.id, user_a)
        add_room_member(existing.id, user_b)
        return existing, None

    me = db.session.get(User, user_a)
    other_name = (other.full_name or other.display_name or other.email or "User").strip()
    my_name = ((me.full_name or me.display_name or me.email) if me else "You").strip()
    room = ChatRoom(
        name=f"{my_name} & {other_name}",
        project_id=None,
        is_group=False,
        direct_pair_key=direct_pair_key(user_a, user_b),
    )
    db.session.add(room)
    db.session.flush()
    add_room_member(room.id, user_a)
    add_room_member(room.id, user_b)
    return room, None
