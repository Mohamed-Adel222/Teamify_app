"""Persisted meeting sessions: transcript captured from chat during a live meeting."""
from datetime import datetime, timezone

from models import db


def _utc_iso(dt):
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.isoformat()


class MeetingSession(db.Model):
    """A live meeting tied to a chat room; transcript is chat messages during the session."""

    __tablename__ = "meeting_sessions"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    room_id = db.Column(
        db.Integer,
        db.ForeignKey("chat_rooms.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    meeting_id = db.Column(
        db.Integer,
        db.ForeignKey("meetings.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    project_id = db.Column(
        db.Integer,
        db.ForeignKey("projects.id", ondelete="SET NULL"),
        nullable=True,
    )
    started_by = db.Column(
        db.Integer,
        db.ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    started_at = db.Column(
        db.DateTime,
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    ended_at = db.Column(db.DateTime, nullable=True)
    is_active = db.Column(db.Boolean, default=True, nullable=False)
    transcript = db.Column(db.JSON, default=list, nullable=False)
    participant_ids = db.Column(db.JSON, default=list, nullable=False)
    duration_seconds = db.Column(db.Integer, nullable=True)
    ai_summary = db.Column(db.JSON, nullable=True)

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

    def to_dict(self):
        data = {
            "id": self.id,
            "room_id": self.room_id,
            "meeting_id": self.meeting_id,
            "project_id": self.project_id,
            "started_by": self.started_by,
            "started_at": _utc_iso(self.started_at),
            "ended_at": _utc_iso(self.ended_at),
            "is_active": self.is_active,
            "transcript": self.transcript or [],
            "participant_ids": self.participant_ids or [],
            "duration_seconds": self.duration_seconds,
            "ai_summary": self.ai_summary or {},
        }
        summary = self.ai_summary if isinstance(self.ai_summary, dict) else {}
        data["summary"] = summary.get("summary")
        data["speech_transcript"] = summary.get("speech_transcript") or []
        data["key_points"] = summary.get("key_points") or []
        data["action_items"] = summary.get("action_items") or []
        return data

    def __repr__(self):
        return f"<MeetingSession {self.id} room={self.room_id} active={self.is_active}>"
