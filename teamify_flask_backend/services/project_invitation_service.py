"""Send and respond to project membership invitations."""
from __future__ import annotations

from datetime import datetime, timezone

from models import db
from models.project import Project
from models.project_invitation import ProjectInvitation
from models.project_member import ProjectMember
from models.user import User
from routes.notifications import create_notification
from services.chat_room_service import ensure_project_chat_room


def _display_name(user: User | None) -> str:
    if not user:
        return "Someone"
    return user.full_name or user.display_name or user.email or f"User {user.id}"


def invite_users_to_project(
    project: Project,
    inviter_id: int,
    user_ids: list[int],
) -> tuple[list[int], list[dict]]:
    """
    Create or refresh pending invitations and notify each invitee.
    Does not add project_members until the invitee accepts.
    """
    invited: list[int] = []
    skipped: list[dict] = []
    seen: set[int] = {project.user_id, inviter_id}

    inviter = db.session.get(User, inviter_id)

    for raw_id in user_ids:
        try:
            mid = int(raw_id)
        except (TypeError, ValueError):
            skipped.append({"id": raw_id, "reason": "invalid id format"})
            continue

        if mid in seen:
            skipped.append({"id": mid, "reason": "duplicate"})
            continue
        seen.add(mid)

        target = db.session.get(User, mid)
        if not target:
            skipped.append({"id": mid, "reason": "user not found"})
            continue

        if target.role == "admin" or (target.user_type or "").lower() == "admin":
            skipped.append({"id": mid, "reason": "admin accounts cannot be invited"})
            continue

        if ProjectMember.query.filter_by(project_id=project.id, user_id=mid).first():
            skipped.append({"id": mid, "reason": "already a member"})
            continue

        invitation = ProjectInvitation.query.filter_by(
            project_id=project.id, invitee_id=mid
        ).first()

        if invitation:
            if invitation.status == "pending":
                skipped.append({"id": mid, "reason": "invitation already pending"})
                continue
            if invitation.status == "accepted":
                skipped.append({"id": mid, "reason": "already accepted"})
                continue
            invitation.status = "pending"
            invitation.inviter_id = inviter_id
            invitation.responded_at = None
            invitation.created_at = datetime.now(timezone.utc)
        else:
            invitation = ProjectInvitation(
                project_id=project.id,
                inviter_id=inviter_id,
                invitee_id=mid,
                status="pending",
            )
            db.session.add(invitation)

        db.session.flush()

        create_notification(
            user_id=mid,
            notif_type="project_invitation",
            title=f"Invitation to {project.name}",
            body=f"{_display_name(inviter)} invited you to join \"{project.name}\". "
            "Open this notification to accept or decline.",
            entity_type="ProjectInvitation",
            entity_id=invitation.id,
        )
        invited.append(mid)

    return invited, skipped


def accept_invitation(invitation_id: int, user_id: int) -> tuple[ProjectInvitation | None, str | None]:
    """Add invitee as member when they accept. Returns (invitation, error_message)."""
    invitation = db.session.get(ProjectInvitation, invitation_id)
    if not invitation:
        return None, "Invitation not found"
    if invitation.invitee_id != user_id:
        return None, "Forbidden"
    if invitation.status != "pending":
        return None, f"Invitation already {invitation.status}"

    project = db.session.get(Project, invitation.project_id)
    if not project:
        return None, "Project not found"

    if not ProjectMember.query.filter_by(
        project_id=project.id, user_id=user_id
    ).first():
        db.session.add(
            ProjectMember(
                project_id=project.id,
                user_id=user_id,
                role="member",
            )
        )

    invitation.status = "accepted"
    invitation.responded_at = datetime.now(timezone.utc)

    ensure_project_chat_room(project, user_id)

    invitee = db.session.get(User, user_id)
    create_notification(
        user_id=project.user_id,
        notif_type="team_added",
        title=f"{_display_name(invitee)} joined {project.name}",
        body=f"{_display_name(invitee)} accepted your project invitation.",
        entity_type="Project",
        entity_id=project.id,
    )

    try:
        from app import socketio

        socketio.emit(
            "project_member_added",
            {
                "project_id": project.id,
                "user_id": user_id,
                "user_name": _display_name(invitee),
                "role": "member",
                "action": "added",
            },
            to=f"project_{project.id}",
        )
    except Exception:
        pass

    return invitation, None


def decline_invitation(invitation_id: int, user_id: int) -> tuple[ProjectInvitation | None, str | None]:
    """Mark invitation declined; no membership change."""
    invitation = db.session.get(ProjectInvitation, invitation_id)
    if not invitation:
        return None, "Invitation not found"
    if invitation.invitee_id != user_id:
        return None, "Forbidden"
    if invitation.status != "pending":
        return None, f"Invitation already {invitation.status}"

    invitation.status = "declined"
    invitation.responded_at = datetime.now(timezone.utc)
    return invitation, None
