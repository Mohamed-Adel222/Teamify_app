"""Evaluate notification email preferences and record delivery.

In-app notifications and Socket.IO are unchanged. This module is an extra
delivery channel that must never raise into the caller.
"""
from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

from flask import current_app, has_app_context
from sqlalchemy import event
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError

from models import db
from models.email_delivery import (
    EMAIL_STATUS_FAILED,
    EMAIL_STATUS_PENDING,
    EMAIL_STATUS_SENT,
    EMAIL_STATUS_SKIPPED,
    EmailDelivery,
)
from models.notification import Notification
from models.user import User
from services.email_service import (
    EmailResult,
    app_cta_url,
    is_valid_email,
    preferences_url,
    send_email,
)
from services.system_settings_service import is_email_notifications_enabled

logger = logging.getLogger(__name__)

# Notification.type → user preference key (existing Flutter/API names).
TYPE_TO_PREF = {
    "project_invitation": "emailTeamInvitations",
    "team_invitation": "emailTeamInvitations",
    "team_added": "emailInvitationResponses",
    "invitation_accepted": "emailInvitationResponses",
    "invitation_rejected": "emailInvitationResponses",
    "task_assigned": "emailTaskAssignments",
    "task_updated": "emailTaskUpdates",
    "deadline_approaching": "emailDeadlineReminders",
    "deadline_reminder": "emailDeadlineReminders",
    "delay_warning": "emailDeadlineReminders",
    "message": "emailNewMessages",
    "direct_message": "emailNewMessages",
    "chat_mention": "emailNewMessages",
    "role_changed": "emailRoleChanges",
    "member_removed": "emailMembershipChanges",
    "connection_request": "emailNewMessages",
    "admin_announcement": "emailAdminAnnouncements",
    "general": "emailAdminAnnouncements",
}

# Types that still send immediately when the user chose a digest frequency.
_INSTANT_EVEN_ON_DIGEST = frozenset(
    {
        "project_invitation",
        "team_invitation",
        "team_added",
        "invitation_accepted",
        "task_assigned",
        "deadline_approaching",
        "deadline_reminder",
        "delay_warning",
    }
)


def display_name(user: User | None) -> str:
    if not user:
        return "Someone"
    return (user.full_name or user.display_name or user.email or f"User {user.id}").strip()


def evaluate_email_permission(
    user: User | None,
    notif_type: str,
    *,
    is_mention: bool = False,
) -> tuple[bool, str | None]:
    """Return (allowed, skip_reason). Never raises."""
    if not is_email_notifications_enabled():
        return False, "admin_disabled"
    if user is None:
        return False, "user_not_found"
    if not is_valid_email(user.email):
        return False, "invalid_recipient"

    from routes.notifications import BOOL_PREFERENCES, CHOICE_PREFERENCES, _merged_preferences

    prefs = _merged_preferences(getattr(user, "notification_prefs", None))
    if not prefs.get("masterEmailEnabled", True):
        return False, "master_email_disabled"

    pref_key = TYPE_TO_PREF.get(notif_type)
    if pref_key and not prefs.get(pref_key, BOOL_PREFERENCES.get(pref_key, True)):
        return False, "category_disabled"

    if notif_type in ("message", "direct_message", "chat_mention"):
        behavior = prefs.get("messageEmailBehavior") or CHOICE_PREFERENCES["messageEmailBehavior"][1]
        if behavior == "never":
            return False, "message_behavior_never"
        if behavior == "offline" and _user_is_connected(user.id) and not is_mention:
            return False, "user_online"
        if behavior == "15_min_inactivity" and not is_mention:
            if not _user_inactive_for_minutes(user.id, 15):
                return False, "user_recently_active"
        # Mentions still respect master + emailNewMessages; "offline"/"inactivity"
        # do not suppress mention emails.

    frequency = prefs.get("deliveryFrequency") or CHOICE_PREFERENCES["deliveryFrequency"][1]
    if frequency in ("daily_digest", "weekly_digest") and notif_type not in _INSTANT_EVEN_ON_DIGEST:
        return False, "digest_deferred"

    return True, None


def _user_is_connected(user_id: int) -> bool:
    try:
        from sockets.chat_sockets import is_user_connected

        return bool(is_user_connected(user_id))
    except Exception:
        return False


def _user_inactive_for_minutes(user_id: int, minutes: int) -> bool:
    try:
        from sockets.chat_sockets import user_inactive_for

        return bool(user_inactive_for(user_id, minutes))
    except Exception:
        return True


def _record_delivery(
    *,
    notification_id: int | None,
    user_id: int | None,
    recipient_email: str,
    email_type: str,
    status: str,
    provider_message_id: str | None = None,
    error_message: str | None = None,
    skip_reason: str | None = None,
    idempotency_key: str | None = None,
    sent_at: datetime | None = None,
) -> EmailDelivery | None:
    row = _existing_delivery(idempotency_key) if idempotency_key else None
    if row is None:
        row = EmailDelivery(
            notification_id=notification_id,
            user_id=user_id,
            recipient_email=recipient_email,
            email_type=email_type,
            status=status,
            provider_message_id=provider_message_id,
            error_message=error_message,
            skip_reason=skip_reason,
            idempotency_key=idempotency_key,
            sent_at=sent_at,
        )
        db.session.add(row)
    else:
        row.notification_id = notification_id or row.notification_id
        row.user_id = user_id or row.user_id
        row.recipient_email = recipient_email
        row.email_type = email_type
        row.status = status
        row.provider_message_id = provider_message_id
        row.error_message = error_message
        row.skip_reason = skip_reason
        row.sent_at = sent_at
    try:
        db.session.commit()
        return row
    except IntegrityError:
        db.session.rollback()
        if idempotency_key:
            existing = EmailDelivery.query.filter_by(idempotency_key=idempotency_key).first()
            return existing
        logger.warning("Failed to persist email delivery row")
        return None
    except Exception:
        db.session.rollback()
        logger.warning("Failed to persist email delivery row", exc_info=True)
        return None


def already_sent(idempotency_key: str | None) -> bool:
    if not idempotency_key:
        return False
    row = EmailDelivery.query.filter_by(idempotency_key=idempotency_key).first()
    return bool(row and row.status == EMAIL_STATUS_SENT)


def _existing_delivery(idempotency_key: str | None) -> EmailDelivery | None:
    if not idempotency_key:
        return None
    return EmailDelivery.query.filter_by(idempotency_key=idempotency_key).first()


def deliver_notification_email(
    notification_id: int,
    *,
    idempotency_key: str | None = None,
    is_mention: bool = False,
) -> EmailResult:
    """Load a saved notification and send email when preferences allow."""
    try:
        notif = db.session.get(Notification, notification_id)
        if not notif:
            return EmailResult(False, "skipped", error="notification_not_found")

        user = db.session.get(User, notif.user_id)
        recipient = (user.email if user else "") or ""
        email_type = notif.type or "notification"

        if idempotency_key:
            existing = _existing_delivery(idempotency_key)
            if existing and existing.status == EMAIL_STATUS_SENT:
                return EmailResult(False, "skipped", error="duplicate")

        allowed, reason = evaluate_email_permission(
            user, email_type, is_mention=is_mention or email_type == "chat_mention"
        )
        if not allowed:
            _record_delivery(
                notification_id=notif.id,
                user_id=notif.user_id,
                recipient_email=recipient or "unknown",
                email_type=email_type,
                status=EMAIL_STATUS_SKIPPED,
                skip_reason=reason,
                idempotency_key=idempotency_key,
            )
            return EmailResult(False, "skipped", error=reason)

        subject, html, text = build_notification_email_content(notif, user)
        result = send_email(to=recipient, subject=subject, html=html, text=text)
        status = EMAIL_STATUS_SENT if result.success else (
            EMAIL_STATUS_SKIPPED if result.status == "skipped" else EMAIL_STATUS_FAILED
        )
        _record_delivery(
            notification_id=notif.id,
            user_id=notif.user_id,
            recipient_email=recipient,
            email_type=email_type,
            status=status,
            provider_message_id=result.provider_message_id,
            error_message=None if result.success else (result.error or "send_failed"),
            skip_reason=result.error if status == EMAIL_STATUS_SKIPPED else None,
            idempotency_key=idempotency_key,
            sent_at=datetime.now(timezone.utc) if result.success else None,
        )
        return result
    except Exception:
        logger.exception("Notification email delivery failed id=%s", notification_id)
        try:
            db.session.rollback()
        except Exception:
            pass
        return EmailResult(False, "failed", error="internal_error")


def record_standalone_email(
    *,
    user_id: int | None,
    recipient_email: str,
    email_type: str,
    result: EmailResult,
    idempotency_key: str | None = None,
) -> None:
    status = EMAIL_STATUS_SENT if result.success else (
        EMAIL_STATUS_SKIPPED if result.status == "skipped" else EMAIL_STATUS_FAILED
    )
    _record_delivery(
        notification_id=None,
        user_id=user_id,
        recipient_email=recipient_email,
        email_type=email_type,
        status=status,
        provider_message_id=result.provider_message_id,
        error_message=None if result.success else (result.error or "send_failed"),
        skip_reason=result.error if status == EMAIL_STATUS_SKIPPED else None,
        idempotency_key=idempotency_key,
        sent_at=datetime.now(timezone.utc) if result.success else None,
    )


def build_notification_email_content(notif: Notification, user: User) -> tuple[str, str, str]:
    """Build subject/html/text from the notification and related entities."""
    from services import email_templates as templates

    name = display_name(user)
    prefs_url = preferences_url()
    cta = app_cta_url("/")
    notif_type = notif.type or "general"
    title = notif.title or "Teamify notification"
    body = notif.body or ""

    project_name, task_title, due_label, extra = _related_entity_details(notif)

    if notif_type in ("project_invitation", "team_invitation"):
        inviter = extra.get("actor") or "A teammate"
        subject, html, text = templates.team_invitation_email(
            recipient_name=name,
            inviter_name=inviter,
            project_name=project_name or extra.get("project_name") or "a project",
            cta_url=cta,
            preferences_url=prefs_url,
        )
        return subject, html, text

    if notif_type in ("team_added", "invitation_accepted"):
        subject, html, text = templates.invitation_accepted_email(
            owner_name=name,
            invitee_name=extra.get("actor") or "A teammate",
            project_name=project_name or "your project",
            cta_url=cta,
            preferences_url=prefs_url,
        )
        return subject, html, text

    if notif_type == "task_assigned":
        due = extra.get("due_date") or due_label
        subject, html, text = templates.task_assigned_email(
            recipient_name=name,
            task_title=task_title or title,
            project_name=project_name,
            due_date=due,
            cta_url=cta,
            preferences_url=prefs_url,
        )
        return subject, html, text

    if notif_type == "task_updated":
        subject, html, text = templates.task_updated_email(
            recipient_name=name,
            task_title=task_title or title,
            change_summary=body or "The task was updated.",
            project_name=project_name,
            cta_url=cta,
            preferences_url=prefs_url,
        )
        return subject, html, text

    if notif_type in ("deadline_approaching", "deadline_reminder"):
        subject, html, text = templates.deadline_reminder_email(
            recipient_name=name,
            task_title=task_title or title,
            due_label=due_label or body or "Deadline approaching",
            project_name=project_name,
            cta_url=cta,
            preferences_url=prefs_url,
        )
        return subject, html, text

    if notif_type == "delay_warning":
        subject, html, text = templates.overdue_task_email(
            recipient_name=name,
            task_title=task_title or title,
            overdue_label=due_label or body or "Overdue",
            project_name=project_name,
            cta_url=cta,
            preferences_url=prefs_url,
        )
        return subject, html, text

    if notif_type in ("message", "direct_message", "chat_mention"):
        subject, html, text = templates.chat_message_email(
            recipient_name=name,
            sender_name=extra.get("actor") or "A teammate",
            room_name=extra.get("room_name") or "Teamify chat",
            preview=_message_preview(body),
            is_mention=notif_type == "chat_mention",
            cta_url=cta,
            preferences_url=prefs_url,
        )
        return subject, html, text

    if notif_type in ("admin_announcement", "general"):
        subject, html, text = templates.announcement_email(
            recipient_name=name,
            title=title,
            body=body,
            cta_url=cta,
            preferences_url=prefs_url,
        )
        return subject, html, text

    if notif_type == "role_changed":
        subject, html, text = templates.role_changed_email(
            recipient_name=name,
            new_role=extra.get("role") or body or "updated",
            context_label=title,
            cta_url=cta,
            preferences_url=prefs_url,
        )
        return subject, html, text

    if notif_type == "member_removed":
        subject, html, text = templates.membership_changed_email(
            recipient_name=name,
            project_name=project_name or extra.get("project_name") or "a project",
            cta_url=cta,
            preferences_url=prefs_url,
        )
        return subject, html, text

    subject, html, text = templates.render_email(
        preheader=title,
        title=title,
        intro=body or "You have a new Teamify notification.",
        cta_label="Open Teamify" if cta else None,
        cta_url=cta,
        preferences_url=prefs_url,
    )
    return title, html, text


def _message_preview(body: str, limit: int = 160) -> str:
    text = (body or "").strip().replace("\n", " ")
    if len(text) <= limit:
        return text
    return text[: limit - 1] + "…"


def _related_entity_details(notif: Notification) -> tuple[str | None, str | None, str | None, dict[str, Any]]:
    extra: dict[str, Any] = {}
    project_name = None
    task_title = None
    due_label = None
    try:
        if notif.entity_type == "ProjectInvitation" and notif.entity_id:
            from models.project_invitation import ProjectInvitation
            from models.project import Project

            inv = db.session.get(ProjectInvitation, notif.entity_id)
            if inv:
                project = db.session.get(Project, inv.project_id)
                project_name = project.name if project else None
                extra["project_name"] = project_name
                inviter = db.session.get(User, inv.inviter_id)
                extra["actor"] = display_name(inviter)
        elif notif.entity_type == "Project" and notif.entity_id:
            from models.project import Project

            project = db.session.get(Project, notif.entity_id)
            project_name = project.name if project else None
            extra["project_name"] = project_name
            # Invitation-accepted notifications mention the invitee in the title/body.
            extra["actor"] = (notif.title or "").split(" joined ")[0].strip() or None
        elif notif.entity_type == "Task" and notif.entity_id:
            from models.task import Task
            from models.project import Project

            task = db.session.get(Task, notif.entity_id)
            if task:
                task_title = task.title
                if task.due_date:
                    due_label = task.due_date.isoformat()
                    extra["due_date"] = due_label
                project = db.session.get(Project, task.project_id)
                project_name = project.name if project else None
        elif notif.entity_type in ("Message", "ChatRoom") and notif.entity_id:
            from models.chat import ChatRoom, Message

            if notif.entity_type == "Message":
                msg = db.session.get(Message, notif.entity_id)
                if msg:
                    sender = db.session.get(User, msg.sender_id)
                    extra["actor"] = display_name(sender)
                    room = db.session.get(ChatRoom, msg.room_id)
                    extra["room_name"] = (room.name if room and room.name else "Chat")
            else:
                room = db.session.get(ChatRoom, notif.entity_id)
                extra["room_name"] = (room.name if room and room.name else "Chat")
    except Exception:
        logger.debug("Could not expand notification entity for email", exc_info=True)
    return project_name, task_title, due_label, extra


_SESSION_EMAIL_QUEUE = "teamify_notification_emails"


def _mail_disabled_for_tests() -> bool:
    try:
        return bool(
            has_app_context()
            and current_app.config.get("TESTING")
            and not current_app.config.get("MAIL_SEND_IN_TESTS")
        )
    except Exception:
        return False


def queue_notification_email(
    notification_id: int,
    *,
    idempotency_key: str | None = None,
    is_mention: bool = False,
) -> None:
    """Send email after the surrounding transaction commits. Never raises.

    Invitation and other notification emails used to register Flask
    ``after_this_request`` *before* ``db.session.commit()``. Under gunicorn's
    gevent worker those callbacks were easy to miss, so invites created an
    in-app notification and never emailed. Queue on the SQLAlchemy session and
    flush on ``after_commit`` (or immediately when already committed).
    """
    if not notification_id:
        return
    if _mail_disabled_for_tests():
        return

    item = (int(notification_id), idempotency_key, bool(is_mention))
    try:
        session = db.session
        pending = session.info.setdefault(_SESSION_EMAIL_QUEUE, [])
        pending.append(item)
        in_transaction = session.get_transaction() is not None
    except Exception:
        logger.warning(
            "Failed to queue notification email id=%s", notification_id, exc_info=True
        )
        _spawn_delivery(*item)
        return

    if not in_transaction:
        _flush_session_emails(session)


def deliver_notification_email_now(
    notification_id: int,
    *,
    idempotency_key: str | None = None,
    is_mention: bool = False,
) -> EmailResult:
    """Synchronous delivery used by the scheduler after commit."""
    try:
        return deliver_notification_email(
            notification_id,
            idempotency_key=idempotency_key,
            is_mention=is_mention,
        )
    except Exception:
        logger.exception("Synchronous notification email failed id=%s", notification_id)
        return EmailResult(False, "failed", error="internal_error")


def send_invitation_emails(notification_ids: list[int]) -> dict[str, Any]:
    """Send project-invitation emails after the invite transaction committed."""
    from services.email_service import mail_status

    status = mail_status()
    sent = 0
    failed = 0
    last_error = None
    for notification_id in notification_ids:
        if not notification_id:
            continue
        result = deliver_notification_email_now(int(notification_id))
        if result.success:
            sent += 1
        else:
            failed += 1
            last_error = result.error
    configured = bool(status.get("configured"))
    if not configured:
        last_error = (
            "Email is not configured on the server. "
            "Set RESEND_API_KEY and a verified MAIL_FROM_ADDRESS."
        )
    return {
        "email_configured": configured,
        "email_sent": sent > 0 and failed == 0,
        "emails_sent": sent,
        "email_error": last_error if failed or not configured else None,
    }


def _flush_session_emails(session) -> None:
    pending = list(session.info.pop(_SESSION_EMAIL_QUEUE, []) or [])
    if not pending:
        return
    app = None
    try:
        if has_app_context():
            app = current_app._get_current_object()
    except Exception:
        app = None
    for notification_id, key, mention in pending:
        _spawn_delivery(notification_id, key, mention, app=app)


def _spawn_delivery(
    notification_id: int,
    idempotency_key: str | None,
    is_mention: bool,
    app=None,
) -> None:
    if app is None:
        try:
            if has_app_context():
                app = current_app._get_current_object()
        except Exception:
            app = None
    if app is None:
        logger.warning(
            "Cannot send notification email id=%s without an application context",
            notification_id,
        )
        return

    def _run() -> None:
        with app.app_context():
            deliver_notification_email(
                notification_id,
                idempotency_key=idempotency_key,
                is_mention=is_mention,
            )

    _spawn(_run)


@event.listens_for(Session, "after_commit")
def _send_queued_emails_after_commit(session) -> None:
    try:
        _flush_session_emails(session)
    except Exception:
        logger.warning("Failed to flush queued notification emails", exc_info=True)


def _spawn(fn) -> None:
    try:
        import gevent

        gevent.spawn(fn)
    except Exception:
        import threading

        threading.Thread(target=fn, daemon=True).start()
