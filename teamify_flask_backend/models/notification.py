from datetime import datetime, timezone
from models import db


class Notification(db.Model):
    """Notification model for user-facing alerts."""

    __tablename__ = "notifications"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    # Type: task_assigned, delay_warning, deadline_approaching, team_added,
    #        task_updated, device_login, message, general
    type = db.Column(db.String(30), nullable=False, default="general")
    title = db.Column(db.String(200), nullable=False)
    body = db.Column(db.Text, nullable=True)
    is_read = db.Column(db.Boolean, default=False, nullable=False)
    # Optional reference to related entity
    entity_type = db.Column(db.String(30), nullable=True)  # Task, Project, User
    entity_id = db.Column(db.Integer, nullable=True)
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))

    __table_args__ = (
        db.Index("ix_notif_user_read", "user_id", "is_read"),
        db.Index("ix_notif_user_created", "user_id", "created_at"),
    )

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

    def to_dict(self, email_delivery=None):
        email_status = None
        email_delivered = False
        if email_delivery is not None:
            email_status = getattr(email_delivery, "public_status", lambda: None)()
            email_delivered = bool(getattr(email_delivery, "is_sent", False))
        return {
            "id": self.id,
            "user_id": self.user_id,
            "type": self.type,
            "title": self.title,
            "body": self.body,
            "is_read": self.is_read,
            "entity_type": self.entity_type,
            "entity_id": self.entity_id,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "email_delivered": email_delivered,
            "emailDelivered": email_delivered,
            "email_status": email_status,
        }

    def __repr__(self):
        return f"<Notification {self.type}: {self.title}>"
