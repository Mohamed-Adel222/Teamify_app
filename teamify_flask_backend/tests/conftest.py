"""
Shared pytest fixtures for the Teamify API test suite.
======================================================

Provides:
- A configured Flask test client backed by an in-memory SQLite database.
- Helper functions to generate JWT tokens for different roles.
- Pre-built mock user objects (admin, member, guest) with deterministic IDs.
- A `mock_db_session` autouse fixture that patches `db.session.commit` and
  `db.session.rollback` so that **no** real database writes ever happen.

Usage:
    pytest tests/

Convention:
    role  ∈ {admin, member, guest}   — dictates RBAC permissions
    user_type ∈ {freelancer, student, admin} — descriptive only, no impact on access
"""

from datetime import datetime, timezone, timedelta
from unittest.mock import MagicMock, patch, PropertyMock

import pytest
from flask_jwt_extended import create_access_token, create_refresh_token

# ─── Deterministic IDs for test entities ──────────────────────────────────────
ADMIN_USER_ID = 1
MEMBER_USER_ID = 2
GUEST_USER_ID = 3
MEMBER2_USER_ID = 4  # second member
PROJECT_ID = 101
PROJECT2_ID = 102
TASK_ID = 201
TASK2_ID = 202
LOG_ID = 301
NOTIFICATION_ID = 401
ALERT_ID = 501
FILE_ID = 601
COMMENT_ID = 701
PM_ID = 801
NONEXISTENT_ID = 99999


# ─── Fake model helpers ──────────────────────────────────────────────────────

def _make_user(uid, role="member", user_type="freelancer", display_name=None):
    """Return a lightweight mock User object."""
    user = MagicMock()
    user.id = uid
    user.display_name = display_name or f"user_{uid}"
    user.full_name = f"Full {user.display_name}"
    user.email = f"{user.display_name}@example.com"
    user.password = "$2b$12$fakehashedpassword"
    user.role = role
    user.user_type = user_type
    user.professional_field = None
    user.experience_level = None
    user.availability = None
    user.skills = ["Python", "Flask"]
    user.current_level = None
    user.major = None
    user.looking_for_team = False
    user.reason_for_joining = None
    user.member_on_time_rate = 1.0
    user.member_avg_delay_days = 0.0
    user.member_experience_years = 0
    user.max_capacity = 5
    user.max_allowed_tasks = 5
    user.previous_categories = []
    user.meetings_attended = 0
    user.total_meetings = 0
    user.otp_code = None
    user.otp_expires_at = None
    user.locked_until = None
    user.failed_login_attempts = 0
    user.created_at = datetime(2025, 1, 1, tzinfo=timezone.utc)
    user.updated_at = datetime(2025, 1, 1, tzinfo=timezone.utc)
    user.to_dict.return_value = {
        "id": uid,
        "display_name": user.display_name,
        "full_name": user.full_name,
        "email": user.email,
        "role": role,
        "user_type": user_type,
        "professional_field": None,
        "experience_level": None,
        "availability": None,
        "skills": ["Python", "Flask"],
        "current_level": None,
        "major": None,
        "looking_for_team": False,
        "reason_for_joining": None,
        "member_on_time_rate": 1.0,
        "member_avg_delay_days": 0.0,
        "member_experience_years": 0,
        "max_capacity": 5,
        "max_allowed_tasks": 5,
        "previous_categories": [],
        "meetings_attended": 0,
        "total_meetings": 0,
        "attendance_rate": 0.0,
        "availability_score": 1.0,
        "workload_ratio": 0.0,
        "created_at": "2025-01-01T00:00:00+00:00",
        "updated_at": "2025-01-01T00:00:00+00:00",
    }
    return user


def _make_project(pid=PROJECT_ID, owner_id=MEMBER_USER_ID, name="Test Project",
                  status="active"):
    project = MagicMock()
    project.id = pid
    project.name = name
    project.description = "A test project"
    project.status = status
    project.start_date = None
    project.end_date = None
    project.user_id = owner_id
    project.category = None
    project.created_at = datetime(2025, 1, 1, tzinfo=timezone.utc)
    project.updated_at = datetime(2025, 1, 1, tzinfo=timezone.utc)
    project.tasks = []
    project.members = []
    project.to_dict.return_value = {
        "id": pid,
        "name": name,
        "description": "A test project",
        "status": status,
        "progress": 0,
        "start_date": None,
        "end_date": None,
        "user_id": owner_id,
        "category": None,
        "created_at": "2025-01-01T00:00:00+00:00",
        "updated_at": "2025-01-01T00:00:00+00:00",
    }
    return project


def _make_task(tid=TASK_ID, project_id=PROJECT_ID, assigned_to=None,
               title="Test Task", status="pending", priority="medium"):
    task = MagicMock()
    task.id = tid
    task.title = title
    task.description = "A test task"
    task.status = status
    task.priority = priority
    task.due_date = None
    task.project_id = project_id
    task.assigned_to = assigned_to
    task.task_difficulty = 3
    task.estimated_duration_days = None
    task.progress_percent = 0.0
    task.priority_level = 2
    task.complexity_level = 3
    task.num_subtasks = 0
    task.start_date = None
    task.completed_date = None
    task.review_score = None
    task.deadline_days = None
    task.days_since_start = 0
    task.days_remaining = None
    task.expected_progress_percent = 0.0
    task.progress_gap = 0.0
    task.created_at = datetime(2025, 1, 1, tzinfo=timezone.utc)
    task.updated_at = datetime(2025, 1, 1, tzinfo=timezone.utc)
    task.to_dict.return_value = {
        "id": tid,
        "title": title,
        "description": "A test task",
        "status": status,
        "priority": priority,
        "due_date": None,
        "project_id": project_id,
        "assigned_to": assigned_to,
        "task_difficulty": 3,
        "estimated_duration_days": None,
        "progress_percent": 0.0,
        "priority_level": 2,
        "complexity_level": 3,
        "num_subtasks": 0,
        "start_date": None,
        "completed_date": None,
        "review_score": None,
        "deadline_days": None,
        "days_since_start": 0,
        "days_remaining": None,
        "expected_progress_percent": 0.0,
        "progress_gap": 0.0,
        "created_at": "2025-01-01T00:00:00+00:00",
        "updated_at": "2025-01-01T00:00:00+00:00",
    }
    return task


def _make_log(lid=LOG_ID, user_id=MEMBER_USER_ID, action="CREATE",
              entity="Task", entity_id=TASK_ID):
    log = MagicMock()
    log.id = lid
    log.action = action
    log.entity = entity
    log.entity_id = entity_id
    log.details = "test log entry"
    log.user_id = user_id
    log.created_at = datetime(2025, 1, 1, tzinfo=timezone.utc)
    log.to_dict.return_value = {
        "id": lid,
        "action": action,
        "entity": entity,
        "entity_id": entity_id,
        "details": "test log entry",
        "user_id": user_id,
        "created_at": "2025-01-01T00:00:00+00:00",
    }
    return log


def _make_notification(nid=NOTIFICATION_ID, user_id=MEMBER_USER_ID,
                       notif_type="general", title="Test Notif", is_read=False):
    notif = MagicMock()
    notif.id = nid
    notif.user_id = user_id
    notif.type = notif_type
    notif.title = title
    notif.body = "test body"
    notif.is_read = is_read
    notif.entity_type = None
    notif.entity_id = None
    notif.created_at = datetime(2025, 1, 1, tzinfo=timezone.utc)
    notif.to_dict.return_value = {
        "id": nid,
        "user_id": user_id,
        "type": notif_type,
        "title": title,
        "body": "test body",
        "is_read": is_read,
        "entity_type": None,
        "entity_id": None,
        "created_at": "2025-01-01T00:00:00+00:00",
    }
    return notif


def _make_project_member(pm_id=PM_ID, project_id=PROJECT_ID,
                         user_id=MEMBER_USER_ID, role="member"):
    pm = MagicMock()
    pm.id = pm_id
    pm.project_id = project_id
    pm.user_id = user_id
    pm.role = role
    pm.to_dict.return_value = {
        "id": pm_id,
        "project_id": project_id,
        "user_id": user_id,
        "role": role,
    }
    return pm


def _make_alert(aid=ALERT_ID, alert_type="brute_force", resolved=False):
    alert = MagicMock()
    alert.id = aid
    alert.type = alert_type
    alert.description = "Test alert"
    alert.timestamp = datetime(2025, 1, 1, tzinfo=timezone.utc)
    alert.resolved = resolved
    alert.resolved_at = None
    alert.resolved_by = None
    alert.to_dict.return_value = {
        "id": aid,
        "type": alert_type,
        "description": "Test alert",
        "timestamp": "2025-01-01T00:00:00+00:00",
        "resolved": resolved,
        "resolved_at": None,
        "resolved_by": None,
    }
    return alert


def _make_login_log(user_id=MEMBER_USER_ID, status="success"):
    ll = MagicMock()
    ll.id = 9001
    ll.user_id = user_id
    ll.status = status
    ll.timestamp = datetime(2025, 1, 1)
    ll.ip_address = "127.0.0.1"
    ll.device_info = "TestAgent"
    ll.to_dict.return_value = {
        "id": 9001,
        "user_id": user_id,
        "status": status,
        "timestamp": "2025-01-01T00:00:00",
        "ip_address": "127.0.0.1",
        "device_info": "TestAgent",
    }
    return ll


# ─── Flask app + test client ────────────────────────────────────────────────

@pytest.fixture(scope="session")
def app():
    """Create the Flask application configured for testing."""
    test_config = {
        "TESTING": True,
        "SQLALCHEMY_DATABASE_URI": "sqlite:///:memory:",
        "JWT_SECRET_KEY": "test-secret-key-for-unit-tests",
        "WTF_CSRF_ENABLED": False,
        "RATELIMIT_ENABLED": False,
        "RESEND_API_KEY": "",
    }
    with patch("services.scheduler.init_scheduler", return_value=None):
        from app import create_app, limiter
        application = create_app(test_config=test_config)

    # Directly disable rate limiter so tests don't get 429s
    limiter.enabled = False
    return application


@pytest.fixture(scope="session")
def _db(app):
    """Create database tables once for the session."""
    from models import db
    with app.app_context():
        db.create_all()
    return db


@pytest.fixture
def client(app, _db):
    """Yield a Flask test client with an active application context."""
    with app.test_client() as testing_client:
        with app.app_context():
            yield testing_client


# ─── Mock database session (autouse) ────────────────────────────────────────

@pytest.fixture(autouse=True)
def mock_db_session(request):
    """Prevent any real database writes during unit tests, unless marked as integration.

    Also patches TokenBlocklist.is_revoked → False so that JWT tokens created by
    the test fixtures are never treated as revoked (the blocklist is tested separately
    in test_jwt_blocklist.py which is marked @pytest.mark.integration).
    """
    if "integration" in request.keywords:
        yield None
        return

    with patch("models.db.session") as mock_session, \
         patch("models.token_blocklist.TokenBlocklist.is_revoked", return_value=False):
        mock_session.add = MagicMock()
        mock_session.flush = MagicMock()
        mock_session.commit = MagicMock()
        mock_session.rollback = MagicMock()
        mock_session.delete = MagicMock()
        mock_session.execute = MagicMock()
        # db.session.get(Model, pk) returns None by default.
        # Individual tests that need an object can set:
        #   mock_db_session.get.return_value = some_object
        mock_session.get = MagicMock(return_value=None)
        yield mock_session


# ─── Token generators ───────────────────────────────────────────────────────

@pytest.fixture
def admin_user():
    """Return a mock admin user."""
    return _make_user(ADMIN_USER_ID, role="admin", user_type="freelancer",
                      display_name="admin_user")


@pytest.fixture
def member_user():
    """Return a mock member user."""
    return _make_user(MEMBER_USER_ID, role="member", user_type="freelancer",
                      display_name="member_user")


@pytest.fixture
def guest_user():
    """Return a mock guest user."""
    return _make_user(GUEST_USER_ID, role="guest", user_type="freelancer",
                      display_name="guest_user")


@pytest.fixture
def admin_headers(app):
    """Return Authorization headers for an admin user."""
    with app.app_context():
        token = create_access_token(identity=str(ADMIN_USER_ID))
    return {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}


@pytest.fixture
def member_headers(app):
    """Return Authorization headers for a member user."""
    with app.app_context():
        token = create_access_token(identity=str(MEMBER_USER_ID))
    return {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}


@pytest.fixture
def guest_headers(app):
    """Return Authorization headers for a guest user."""
    with app.app_context():
        token = create_access_token(identity=str(GUEST_USER_ID))
    return {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}


@pytest.fixture
def member2_headers(app):
    """Return Authorization headers for a second member user (non-project-member)."""
    with app.app_context():
        token = create_access_token(identity=str(MEMBER2_USER_ID))
    return {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}


@pytest.fixture
def admin_refresh_token(app):
    """Return a refresh token for admin."""
    with app.app_context():
        return create_refresh_token(identity=str(ADMIN_USER_ID))


@pytest.fixture
def member_refresh_token(app):
    """Return a refresh token for member."""
    with app.app_context():
        return create_refresh_token(identity=str(MEMBER_USER_ID))


def make_headers(token: str) -> dict:
    """Convenience: wrap a token string into Authorization headers."""
    return {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}


# ─── Re-export factory functions for use in tests ────────────────────────────

@pytest.fixture
def make_user_factory():
    """Return the _make_user factory function for custom test users."""
    return _make_user


@pytest.fixture
def make_project_factory():
    return _make_project


@pytest.fixture
def make_task_factory():
    return _make_task


@pytest.fixture
def make_log_factory():
    return _make_log


@pytest.fixture
def make_notification_factory():
    return _make_notification


@pytest.fixture
def make_project_member_factory():
    return _make_project_member


@pytest.fixture
def make_alert_factory():
    return _make_alert


@pytest.fixture
def make_login_log_factory():
    return _make_login_log
