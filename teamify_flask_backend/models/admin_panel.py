"""Admin panel support tables."""
from datetime import datetime, timezone

from models import db


def _utc_iso(dt):
    """Serialize with an explicit UTC offset; the columns store naive UTC and
    clients would otherwise read the timestamp as local time."""
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.isoformat()


class AdminAnalyticsSnapshot(db.Model):
    __tablename__ = "admin_analytics_snapshots"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    snapshot_date = db.Column(db.Date, nullable=False, unique=True, index=True)
    total_users = db.Column(db.Integer, nullable=False, default=0)
    active_users = db.Column(db.Integer, nullable=False, default=0)
    new_users = db.Column(db.Integer, nullable=False, default=0)
    total_projects = db.Column(db.Integer, nullable=False, default=0)
    active_projects = db.Column(db.Integer, nullable=False, default=0)
    tasks_completed = db.Column(db.Integer, nullable=False, default=0)
    disputes_opened = db.Column(db.Integer, nullable=False, default=0)
    disputes_resolved = db.Column(db.Integer, nullable=False, default=0)
    ai_requests = db.Column(db.Integer, nullable=False, default=0)
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "snapshot_date": self.snapshot_date.isoformat() if self.snapshot_date else None,
            "total_users": self.total_users,
            "active_users": self.active_users,
            "new_users": self.new_users,
            "total_projects": self.total_projects,
            "active_projects": self.active_projects,
            "tasks_completed": self.tasks_completed,
            "disputes_opened": self.disputes_opened,
            "disputes_resolved": self.disputes_resolved,
            "ai_requests": self.ai_requests,
            "created_at": _utc_iso(self.created_at),
        }


class BroadcastHistory(db.Model):
    __tablename__ = "broadcast_history"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    admin_id = db.Column(db.Integer, db.ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    target_audience = db.Column(db.String(50), nullable=False, default="all")
    title = db.Column(db.String(255), nullable=False)
    body = db.Column(db.Text, nullable=False)
    recipient_count = db.Column(db.Integer, nullable=False, default=0)
    sent_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc), index=True)

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "admin_id": self.admin_id,
            "target_audience": self.target_audience,
            "title": self.title,
            "body": self.body,
            "recipient_count": self.recipient_count,
            "sent_at": _utc_iso(self.sent_at),
        }


class RolePermission(db.Model):
    __tablename__ = "role_permissions"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    role = db.Column(db.String(30), nullable=False, unique=True, index=True)
    permissions = db.Column(db.JSON, nullable=False, default=dict)
    updated_by = db.Column(db.Integer, db.ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    updated_at = db.Column(
        db.DateTime,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "role": self.role,
            "permissions": self.permissions or {},
            "updated_by": self.updated_by,
            "updated_at": _utc_iso(self.updated_at),
        }


class AdminSession(db.Model):
    __tablename__ = "admin_sessions"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    jti = db.Column(db.String(64), nullable=True, index=True)
    ip_address = db.Column(db.String(50), nullable=True)
    device_info = db.Column(db.String(255), nullable=True)
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))
    revoked_at = db.Column(db.DateTime, nullable=True)

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "user_id": self.user_id,
            "jti": self.jti,
            "ip_address": self.ip_address,
            "device_info": self.device_info,
            "created_at": _utc_iso(self.created_at),
            "revoked_at": _utc_iso(self.revoked_at),
        }
