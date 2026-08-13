"""Persistent tracking of transactional email delivery attempts."""
from datetime import datetime, timezone

from models import db

EMAIL_STATUS_PENDING = "pending"
EMAIL_STATUS_SENT = "sent"
EMAIL_STATUS_FAILED = "failed"
EMAIL_STATUS_SKIPPED = "skipped"

EMAIL_STATUSES = (
    EMAIL_STATUS_PENDING,
    EMAIL_STATUS_SENT,
    EMAIL_STATUS_FAILED,
    EMAIL_STATUS_SKIPPED,
)


class EmailDelivery(db.Model):
    """One delivery attempt (or skip) for a notification or standalone email."""

    __tablename__ = "email_deliveries"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    notification_id = db.Column(
        db.Integer,
        db.ForeignKey("notifications.id", ondelete="SET NULL"),
        nullable=True,
    )
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True)
    recipient_email = db.Column(db.String(255), nullable=False)
    email_type = db.Column(db.String(50), nullable=False, default="notification")
    status = db.Column(db.String(20), nullable=False, default=EMAIL_STATUS_PENDING)
    provider_message_id = db.Column(db.String(255), nullable=True)
    error_message = db.Column(db.Text, nullable=True)
    skip_reason = db.Column(db.String(80), nullable=True)
    idempotency_key = db.Column(db.String(180), nullable=True)
    sent_at = db.Column(db.DateTime, nullable=True)
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))

    __table_args__ = (
        db.Index("ix_email_delivery_notification", "notification_id"),
        db.Index("ix_email_delivery_user_created", "user_id", "created_at"),
        db.Index("ix_email_delivery_status", "status"),
        db.UniqueConstraint("idempotency_key", name="uq_email_delivery_idempotency"),
    )

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

    @property
    def is_sent(self) -> bool:
        return self.status == EMAIL_STATUS_SENT

    def public_status(self) -> str:
        """Status safe to expose to the client (no provider internals)."""
        if self.status in EMAIL_STATUSES:
            return self.status
        return EMAIL_STATUS_FAILED

    def to_public_dict(self) -> dict:
        return {
            "status": self.public_status(),
            "sent_at": self.sent_at.isoformat() if self.sent_at else None,
            "email_delivered": self.is_sent,
        }

    @classmethod
    def latest_by_notification_ids(cls, notification_ids: list[int]) -> dict[int, "EmailDelivery"]:
        """Return the newest delivery row per notification id."""
        if not notification_ids:
            return {}
        rows = (
            cls.query.filter(cls.notification_id.in_(notification_ids))
            .order_by(cls.id.desc())
            .all()
        )
        latest: dict[int, EmailDelivery] = {}
        for row in rows:
            if row.notification_id is not None and row.notification_id not in latest:
                latest[row.notification_id] = row
        return latest

    def __repr__(self):
        return f"<EmailDelivery {self.email_type} {self.status} to={self.recipient_email}>"
