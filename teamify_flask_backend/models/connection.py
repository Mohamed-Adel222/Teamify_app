"""User-to-user connection requests (the "Connect" button on profiles)."""
from datetime import datetime, timezone

from models import db
from utils.timeutils import utc_iso


class Connection(db.Model):
    __tablename__ = "connections"

    STATUS_PENDING = "pending"
    STATUS_ACCEPTED = "accepted"
    STATUS_DECLINED = "declined"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    requester_id = db.Column(
        db.Integer,
        db.ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    addressee_id = db.Column(
        db.Integer,
        db.ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    status = db.Column(db.String(20), nullable=False, default=STATUS_PENDING)
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at = db.Column(
        db.DateTime,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    __table_args__ = (
        db.UniqueConstraint("requester_id", "addressee_id", name="uq_connection_pair"),
        db.Index("ix_conn_addressee", "addressee_id", "status"),
        db.Index("ix_conn_requester", "requester_id", "status"),
    )

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

    def to_dict(self):
        return {
            "id": self.id,
            "requester_id": self.requester_id,
            "addressee_id": self.addressee_id,
            "status": self.status,
            "created_at": utc_iso(self.created_at),
            "updated_at": utc_iso(self.updated_at),
        }

    def __repr__(self):
        return f"<Connection {self.requester_id}->{self.addressee_id} {self.status}>"
