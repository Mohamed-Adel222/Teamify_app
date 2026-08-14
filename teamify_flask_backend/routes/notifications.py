from __future__ import annotations

import logging

from flask import Blueprint, request, jsonify
from flask_jwt_extended import get_jwt_identity
from middleware.auth import auth_required
from models import db
from models.notification import Notification

logger = logging.getLogger(__name__)

notifications_bp = Blueprint("notifications", __name__, url_prefix="/api/notifications")


# ─── GET /api/notifications ──────────────────────────────────────────────────

@notifications_bp.route("", methods=["GET"])
@auth_required
def get_notifications():
    """
    Get notifications for the current user.
    ---
    tags:
      - Notifications
    security:
      - Bearer: []
    parameters:
      - in: query
        name: limit
        type: integer
        default: 50
      - in: query
        name: unread_only
        type: boolean
        default: false
      - in: query
        name: type
        type: string
        description: Filter by notification type
    responses:
      200:
        description: List of notifications
        schema:
          type: object
          properties:
            notifications:
              type: array
              items:
                type: object
            total:
              type: integer
            unread_count:
              type: integer
      401:
        description: Unauthorized
        schema:
          type: object
          properties:
            error:
              type: string
    """
    user_id = int(get_jwt_identity())
    limit = min(int(request.args.get("limit", 50)), 200)
    unread_only = request.args.get("unread_only", "false").lower() == "true"
    notif_type = request.args.get("type", "").strip()

    query = Notification.query.filter_by(user_id=user_id)

    if unread_only:
        query = query.filter_by(is_read=False)

    if notif_type:
        query = query.filter_by(type=notif_type)

    notifications = (
        query
        .order_by(Notification.created_at.desc())
        .limit(limit)
        .all()
    )

    unread_count = Notification.query.filter_by(user_id=user_id, is_read=False).count()

    deliveries = {}
    try:
        from models.email_delivery import EmailDelivery

        deliveries = EmailDelivery.latest_by_notification_ids([n.id for n in notifications])
    except Exception:
        logger.debug("Could not load email delivery status", exc_info=True)

    return jsonify({
        "notifications": [
            n.to_dict(email_delivery=deliveries.get(n.id)) for n in notifications
        ],
        "total": len(notifications),
        "unread_count": unread_count,
    }), 200


# ─── GET /api/notifications/unread-count ─────────────────────────────────────

@notifications_bp.route("/unread-count", methods=["GET"])
@auth_required
def unread_count():
    """
    Get the count of unread notifications.
    ---
    tags:
      - Notifications
    security:
      - Bearer: []
    responses:
      200:
        description: Unread notification count
        schema:
          type: object
          properties:
            unread_count:
              type: integer
      401:
        description: Unauthorized
        schema:
          type: object
          properties:
            error:
              type: string
    """
    user_id = int(get_jwt_identity())
    count = Notification.query.filter_by(user_id=user_id, is_read=False).count()
    return jsonify({"unread_count": count}), 200


# ─── PATCH /api/notifications/<id>/read ──────────────────────────────────────

@notifications_bp.route("/<int:notif_id>/read", methods=["PATCH"])
@auth_required
def mark_as_read(notif_id):
    """
    Mark a single notification as read.
    ---
    tags:
      - Notifications
    security:
      - Bearer: []
    parameters:
      - in: path
        name: notif_id
        type: string
        required: true
    responses:
      200:
        description: Notification marked as read
        schema:
          type: object
          properties:
            message:
              type: string
            notification:
              type: object
      404:
        description: Notification not found
        schema:
          type: object
          properties:
            error:
              type: string
    """
    user_id = int(get_jwt_identity())
    notif = Notification.query.filter_by(id=notif_id, user_id=user_id).first()
    if not notif:
        return jsonify({"error": "Notification not found"}), 404

    notif.is_read = True
    db.session.commit()
    delivery = None
    try:
        from models.email_delivery import EmailDelivery

        delivery = EmailDelivery.latest_by_notification_ids([notif.id]).get(notif.id)
    except Exception:
        pass
    return jsonify({
        "message": "Marked as read",
        "notification": notif.to_dict(email_delivery=delivery),
    }), 200


# ─── POST /api/notifications/mark-all-read ───────────────────────────────────

@notifications_bp.route("/mark-all-read", methods=["POST"])
@auth_required
def mark_all_read():
    """
    Mark all notifications as read for the current user.
    ---
    tags:
      - Notifications
    security:
      - Bearer: []
    responses:
      200:
        description: All notifications marked as read
        schema:
          type: object
          properties:
            message:
              type: string
      401:
        description: Unauthorized
        schema:
          type: object
          properties:
            error:
              type: string
    """
    user_id = int(get_jwt_identity())
    updated = (
        Notification.query
        .filter_by(user_id=user_id, is_read=False)
        .update({"is_read": True})
    )
    db.session.commit()
    return jsonify({"message": f"Marked {updated} notifications as read"}), 200


# ─── Notification preferences ────────────────────────────────────────────────

# Per-user email notification switches. Keys mirror the Flutter
# NotificationPreferences model so the payload round-trips unchanged.
BOOL_PREFERENCES = {
    "masterEmailEnabled": True,
    "emailTeamInvitations": True,
    "emailInvitationResponses": True,
    "emailTaskAssignments": True,
    "emailTaskUpdates": False,
    "emailDeadlineReminders": True,
    "emailNewMessages": False,
    "emailRoleChanges": True,
    "emailMembershipChanges": True,
    "emailAdminAnnouncements": True,
}

CHOICE_PREFERENCES = {
    "taskReminderTiming": (
        {"3_hours", "12_hours", "24_hours", "48_hours"},
        "24_hours",
    ),
    "messageEmailBehavior": (
        {"never", "offline", "15_min_inactivity", "every_message"},
        "offline",
    ),
    "deliveryFrequency": (
        {"instant", "daily_digest", "weekly_digest"},
        "instant",
    ),
}


def _merged_preferences(stored: dict | None) -> dict:
    """Overlay the stored preferences on top of the defaults."""
    stored = stored or {}
    merged = {key: stored.get(key, default) for key, default in BOOL_PREFERENCES.items()}
    for key, (_allowed, default) in CHOICE_PREFERENCES.items():
        merged[key] = stored.get(key, default)
    return merged


@notifications_bp.route("/preferences", methods=["GET"])
@auth_required
def get_notification_preferences():
    """Return the current user's email notification preferences."""
    from models.user import User

    user = db.session.get(User, int(get_jwt_identity()))
    if not user:
        return jsonify({"error": "Not Found", "message": "User not found"}), 404
    return jsonify({"preferences": _merged_preferences(user.notification_prefs)}), 200


@notifications_bp.route("/preferences", methods=["PUT"])
@auth_required
def update_notification_preferences():
    """Replace the current user's email notification preferences."""
    from models.user import User

    user = db.session.get(User, int(get_jwt_identity()))
    if not user:
        return jsonify({"error": "Not Found", "message": "User not found"}), 404

    data = request.get_json(silent=True) or {}
    if isinstance(data.get("preferences"), dict):
        data = data["preferences"]

    errors = []
    prefs = _merged_preferences(user.notification_prefs)

    for key in BOOL_PREFERENCES:
        if key in data:
            value = data[key]
            if isinstance(value, bool):
                prefs[key] = value
            elif isinstance(value, str):
                prefs[key] = value.strip().lower() in ("true", "1", "yes")
            else:
                errors.append(f"{key} must be a boolean")

    for key, (allowed, _default) in CHOICE_PREFERENCES.items():
        if key in data:
            value = str(data[key] or "").strip()
            if value not in allowed:
                errors.append(f"{key} must be one of: {', '.join(sorted(allowed))}")
            else:
                prefs[key] = value

    if errors:
        return jsonify({"error": "Validation failed", "messages": errors}), 400

    user.notification_prefs = prefs
    db.session.commit()
    return jsonify({"preferences": prefs}), 200


# ─── Helper: create notification (used by other routes) ──────────────────────

def create_notification(
    user_id: int,
    notif_type: str,
    title: str,
    body: str | None = None,
    entity_type: str | None = None,
    entity_id: int | None = None,
    *,
    queue_email: bool = True,
    email_idempotency_key: str | None = None,
    is_mention: bool = False,
) -> Notification:
    """
    Persist a Notification row AND emit a real-time Socket.IO event to the
    user's personal room (``user_<user_id>``).

    When ``queue_email`` is true, email delivery is scheduled after the HTTP
    response (or spawned in background). Email failure never raises.

    The caller is responsible for calling ``db.session.commit()`` after this
    function returns (or the caller can rely on an enclosing commit).
    """
    notif = Notification(
        user_id=user_id,
        type=notif_type,
        title=title,
        body=body,
        entity_type=entity_type,
        entity_id=entity_id,
    )
    db.session.add(notif)

    # Flush so notif.id is populated before we serialise
    try:
        db.session.flush()
    except Exception:
        pass  # caller's commit will surface the error

    # Emit real-time event to the user's personal Socket.IO room
    _emit_notification(user_id, notif)

    if queue_email and getattr(notif, "id", None):
        try:
            from services.notification_email_service import queue_notification_email

            queue_notification_email(
                notif.id,
                idempotency_key=email_idempotency_key,
                is_mention=is_mention or notif_type == "chat_mention",
            )
        except Exception:
            logger.warning("Failed to queue notification email", exc_info=True)

    return notif


def _emit_notification(user_id: int, notif: Notification) -> None:
    """Push ``new_notification`` to the user's personal room. Never raises."""
    try:
        from services.system_settings_service import is_push_notifications_enabled

        if not is_push_notifications_enabled():
            return
        from app import socketio
        unread_count = Notification.query.filter_by(
            user_id=user_id, is_read=False
        ).count()
        payload = {
            **notif.to_dict(),
            "unread_count": unread_count,
        }
        socketio.emit("new_notification", payload, to=f"user_{user_id}")
        logger.debug(
            "Emitted new_notification to user_%s id=%s", user_id, notif.id
        )
    except Exception as exc:
        # Non-fatal — the notification is already saved in DB
        logger.warning("Failed to emit new_notification for user %s: %s", user_id, exc)
