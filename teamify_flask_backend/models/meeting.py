"""Meeting domain: scheduled/instant meetings and participant membership."""
from datetime import datetime, timezone
from uuid import uuid4

from models import db


def _utc_iso(dt):
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.isoformat()


class Meeting(db.Model):
    """A Teamify meeting. Media lives in LiveKit; this row is the source of truth."""

    __tablename__ = "meetings"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    public_id = db.Column(
        db.String(36),
        unique=True,
        nullable=False,
        default=lambda: str(uuid4()),
        index=True,
    )
    title = db.Column(db.String(200), nullable=False)
    status = db.Column(db.String(20), nullable=False, default="live")
    starts_at = db.Column(db.DateTime, nullable=True)
    host_user_id = db.Column(
        db.Integer,
        db.ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    project_id = db.Column(
        db.Integer,
        db.ForeignKey("projects.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    chat_room_id = db.Column(
        db.Integer,
        db.ForeignKey("chat_rooms.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    provider = db.Column(db.String(40), nullable=False, default="livekit")
    provider_room = db.Column(db.String(120), nullable=False)
    ended_at = db.Column(db.DateTime, nullable=True)
    created_at = db.Column(
        db.DateTime, default=lambda: datetime.now(timezone.utc), nullable=False
    )
    updated_at = db.Column(
        db.DateTime,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    __table_args__ = (
        db.Index(
            "uq_meetings_one_live_per_room",
            "chat_room_id",
            unique=True,
            postgresql_where=db.text("status = 'live'"),
            sqlite_where=db.text("status = 'live'"),
        ),
    )

    participants = db.relationship(
        "MeetingParticipant",
        backref="meeting",
        lazy=True,
        cascade="all, delete-orphan",
    )

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

    def to_dict(self, include_participants: bool = True):
        data = {
            "id": self.id,
            "public_id": self.public_id,
            "title": self.title,
            "status": self.status,
            "starts_at": _utc_iso(self.starts_at),
            "host_user_id": self.host_user_id,
            "project_id": self.project_id,
            "chat_room_id": self.chat_room_id,
            "provider": self.provider,
            "provider_room": self.provider_room,
            "ended_at": _utc_iso(self.ended_at),
            "created_at": _utc_iso(self.created_at),
            "updated_at": _utc_iso(self.updated_at),
            "participant_count": len(self.participants) if self.participants is not None else 0,
        }
        if include_participants:
            data["participants"] = [p.to_dict() for p in (self.participants or [])]
        from models.user import User
        from models.project import Project

        host = db.session.get(User, self.host_user_id)
        data["host_name"] = ""
        if host is not None:
            data["host_name"] = (
                host.full_name or host.display_name or host.email or ""
            ).strip()
        data["project_name"] = None
        if self.project_id:
            project = db.session.get(Project, self.project_id)
            if project is not None:
                data["project_name"] = project.name
        return data

    def __repr__(self):
        return f"<Meeting {self.public_id} status={self.status}>"


class MeetingParticipant(db.Model):
    """Invited or joined participant on a Teamify meeting."""

    __tablename__ = "meeting_participants"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    meeting_id = db.Column(
        db.Integer,
        db.ForeignKey("meetings.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    user_id = db.Column(
        db.Integer,
        db.ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    role = db.Column(db.String(20), nullable=False, default="participant")
    invite_status = db.Column(db.String(20), nullable=False, default="invited")
    joined_at = db.Column(db.DateTime, nullable=True)
    left_at = db.Column(db.DateTime, nullable=True)
    created_at = db.Column(
        db.DateTime, default=lambda: datetime.now(timezone.utc), nullable=False
    )

    __table_args__ = (
        db.UniqueConstraint("meeting_id", "user_id", name="uq_meeting_participant"),
        db.Index("ix_mp_user_status", "user_id", "invite_status"),
    )

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

    def to_dict(self):
        from models.user import User

        user = db.session.get(User, self.user_id)
        display = ""
        if user:
            display = (user.full_name or user.display_name or user.email or "").strip()
        return {
            "id": self.id,
            "meeting_id": self.meeting_id,
            "user_id": self.user_id,
            "display_name": display,
            "role": self.role,
            "invite_status": self.invite_status,
            "joined_at": _utc_iso(self.joined_at),
            "left_at": _utc_iso(self.left_at),
            "created_at": _utc_iso(self.created_at),
        }

    def __repr__(self):
        return f"<MeetingParticipant meeting={self.meeting_id} user={self.user_id}>"
