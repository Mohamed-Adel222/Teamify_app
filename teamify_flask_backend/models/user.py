from datetime import datetime, timezone, timedelta
from models import db
from models.task import Task
import secrets


class User(db.Model):
    """User model with bcrypt password hashing and AI feature fields."""

    __tablename__ = "users"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    full_name = db.Column(db.String(150), nullable=True)
    display_name = db.Column(db.String(80), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password = db.Column(db.String(255), nullable=False)
    # role: system permission level — member | admin | guest
    role = db.Column(db.String(20), nullable=False, default="member")
    # user_type: how the user describes themselves — freelancer | student | admin
    user_type = db.Column(db.String(30), nullable=True)
    # GitHub OAuth: stores GitHub user id for social login
    github_id = db.Column(db.String(64), nullable=True, unique=True)
    # Extended profile fields (from registration forms)
    professional_field = db.Column(db.String(50), nullable=True)   # freelancer: Designer, Developer, etc.
    experience_level = db.Column(db.String(20), nullable=True)     # Beginner, Intermediate, Expert
    availability = db.Column(db.String(20), nullable=True)         # Full Time, Part Time, Freelancer
    skills = db.Column(db.JSON, nullable=True, default=list)       # Array of skills: ["Python", "Flask"]
    current_level = db.Column(db.String(30), nullable=True)        # student: First year, Second year, etc.
    major = db.Column(db.String(100), nullable=True)               # student: Computer Science, etc.
    looking_for_team = db.Column(db.Boolean, nullable=True)        # student: Yes/No
    reason_for_joining = db.Column(db.String(50), nullable=True)   # guest: Reviewing project, Viewer, etc.
    phone = db.Column(db.String(30), nullable=True)
    bio = db.Column(db.Text, nullable=True)
    preferred_language = db.Column(db.String(10), nullable=True)
    university_id = db.Column(db.String(64), nullable=True)        # student: catalog id or custom slug
    university_name = db.Column(db.String(200), nullable=True)
    is_custom_university = db.Column(db.Boolean, nullable=False, default=False)
    # Per-user email/in-app notification switches, keyed by preference name.
    notification_prefs = db.Column(db.JSON, nullable=True, default=dict)
    avatar_file_id = db.Column(
        db.Integer,
        db.ForeignKey("file_metadata.id", ondelete="SET NULL"),
        nullable=True,
    )

    # ─── AI Feature: Raw fields ──────────────────────────────────────────────
    member_on_time_rate = db.Column(db.Float, nullable=False, default=1.0)
    member_avg_delay_days = db.Column(db.Float, nullable=False, default=0.0)
    member_experience_years = db.Column(db.Integer, nullable=False, default=0)
    max_capacity = db.Column(db.Integer, nullable=False, default=5)
    max_allowed_tasks = db.Column(db.Integer, nullable=False, default=5)
    previous_categories = db.Column(db.JSON, nullable=True, default=list)  # Array of past project categories
    meetings_attended = db.Column(db.Integer, nullable=False, default=0)
    total_meetings = db.Column(db.Integer, nullable=False, default=0)

    # OTP for password reset
    otp_code = db.Column(db.String(6), nullable=True)
    otp_expires_at = db.Column(db.DateTime, nullable=True)

    # ─── 2FA (TOTP) ──────────────────────────────────────────────────────────
    # Stores the base32 secret used to derive TOTP tokens.
    # NULL means 2FA is not yet enabled for this account.
    totp_secret = db.Column(db.String(64), nullable=True)
    totp_enabled = db.Column(db.Boolean, nullable=False, default=False)

    # ─── Brute-Force Lockout (Task 4) ────────────────────────────────────────
    # Consecutive failed login attempts since the last successful login.
    failed_login_attempts = db.Column(db.Integer, nullable=False, default=0)
    # When set, logins are rejected until this UTC datetime has passed.
    locked_until = db.Column(db.DateTime, nullable=True)

    account_status = db.Column(db.String(20), nullable=False, default="approved")
    account_status_note = db.Column(db.Text, nullable=True)

    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at = db.Column(
        db.DateTime,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    # Relationships
    projects = db.relationship("Project", backref="owner", lazy=True)
    assigned_tasks = db.relationship(
        "Task", backref="assignee", lazy=True, foreign_keys="Task.assigned_to"
    )
    logs = db.relationship("Log", backref="user", lazy=True)

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

    def _assigned_tasks(self) -> list[Task]:
        if self.id is None:
            return []
        return Task.query.filter_by(assigned_to=self.id).all()

    # ─── AI Calculated Properties ────────────────────────────────────────────

    @property
    def attendance_rate(self):
        """attendance_rate = meetings_attended / total_meetings"""
        if not self.total_meetings:
            return 0.0
        return self.meetings_attended / self.total_meetings

    @property
    def member_current_tasks(self):
        """count(tasks where assigned_user_id = user AND status != 'done')"""
        return len([t for t in self._assigned_tasks() if t.status != "done"])

    @property
    def availability_score(self):
        """availability_score = 1 - (member.current_tasks / max_capacity)"""
        if not self.max_capacity:
            return 0.0
        score = 1.0 - (self.member_current_tasks / self.max_capacity)
        return max(0.0, score)

    @property
    def workload_ratio(self):
        """workload_ratio = member_current_tasks / max_allowed_tasks"""
        if not self.max_allowed_tasks:
            return 0.0
        return self.member_current_tasks / self.max_allowed_tasks

    @property
    def tasks_completed(self):
        """len(tasks where status == 'done')"""
        return len([t for t in self._assigned_tasks() if t.status == "done"])

    @property
    def overdue_tasks(self):
        """len(tasks where completed_date > deadline)"""
        return len([
            t for t in self._assigned_tasks()
            if t.completed_date and t.due_date and t.completed_date.date() > t.due_date
        ])

    @property
    def quality_score(self):
        """Average(task.review_score) / 5"""
        scores = [t.review_score for t in self._assigned_tasks() if t.review_score is not None]
        if not scores:
            return 0.0
        return (sum(scores) / len(scores)) / 5.0

    def skill_match(self, project):
        """1 if project.category in member.skills else 0"""
        if not self.skills or not project or not getattr(project, 'category', None):
            return 0
        return 1 if project.category in self.skills else 0

    def project_similarity(self, project):
        """1 if project.category in member.previous_categories else 0"""
        if not self.previous_categories or not project or not getattr(project, 'category', None):
            return 0
        return 1 if project.category in self.previous_categories else 0

    def to_dict(self):
        """Serialize user to dictionary (excluding password)."""
        return {
            "id": self.id,
            "full_name": self.full_name,
            "display_name": self.display_name,
            "email": self.email,
            "role": self.role,
            "user_type": self.user_type,
            "github_id": getattr(self, 'github_id', None),
            "professional_field": self.professional_field,
            "experience_level": self.experience_level,
            "availability": self.availability,
            "skills": self.skills if self.skills else [],
            "current_level": self.current_level,
            "major": self.major,
            "looking_for_team": self.looking_for_team,
            "reason_for_joining": self.reason_for_joining,
            "phone": self.phone,
            "bio": self.bio,
            "preferred_language": self.preferred_language,
            "university_id": self.university_id,
            "university_name": self.university_name,
            "is_custom_university": bool(self.is_custom_university),
            "avatar_file_id": self.avatar_file_id,
            "member_on_time_rate": self.member_on_time_rate,
            "member_avg_delay_days": self.member_avg_delay_days,
            "member_experience_years": self.member_experience_years,
            "max_capacity": self.max_capacity,
            "max_allowed_tasks": self.max_allowed_tasks,
            "previous_categories": self.previous_categories if self.previous_categories else [],
            "meetings_attended": self.meetings_attended,
            "total_meetings": self.total_meetings,
            "attendance_rate": self.attendance_rate,
            "availability_score": self.availability_score,
            "workload_ratio": self.workload_ratio,
            "account_status": self.account_status,
            "account_status_note": self.account_status_note,
            "locked_until": self.locked_until.isoformat() if self.locked_until else None,
            "totp_enabled": bool(self.totp_enabled),
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }

    def generate_otp(self):
        """Generate a 6-digit OTP valid for 10 minutes."""
        self.otp_code = str(secrets.randbelow(900000) + 100000)
        self.otp_expires_at = datetime.now(timezone.utc) + timedelta(minutes=10)
        return self.otp_code

    def verify_otp(self, code):
        """Return True if the OTP is correct and not expired."""
        if not self.otp_code or not self.otp_expires_at:
            return False
        now = datetime.now(timezone.utc)
        otp_exp = self.otp_expires_at
        if otp_exp.tzinfo is None:
            otp_exp = otp_exp.replace(tzinfo=timezone.utc)
        if now > otp_exp:
            return False
        return self.otp_code == code

    def clear_otp(self):
        """Clear OTP after use."""
        self.otp_code = None
        self.otp_expires_at = None

    def __repr__(self):
        return f"<User {self.display_name}>"
