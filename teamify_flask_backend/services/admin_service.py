import logging
import re
from datetime import datetime, timezone, timedelta
from sqlalchemy import func, or_, and_, text
from models import db
from models.user import User
from models.project import Project
from models.project_member import ProjectMember
from models.task import Task
from models.login_log import LoginLog
from models.alert import Alert
from models.notification import Notification
from models.log import Log
from models.dispute import Dispute
from models.file_metadata import FileMetadata
from models.chat import ChatRoom, ChatRoomMember, Message
from models.meeting_session import MeetingSession
from services import system_settings_service as sys_settings

logger = logging.getLogger(__name__)

def get_admin_dashboard_stats():
    total_users = User.query.count()
    total_projects = Project.query.count()
    pending_disputes = Dispute.query.filter_by(status="pending").count()
    
    open_tasks = Task.query.filter(Task.status != "done").count()
    
    from models.audit_log import AuditLog
    today_start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    ai_requests_today = AuditLog.query.filter(
        AuditLog.action == "AI_REQUEST",
        AuditLog.created_at >= today_start,
    ).count()
    
    freelancers = User.query.filter_by(user_type="freelancer").count()
    students = User.query.filter_by(user_type="student").count()
    admins = User.query.filter_by(role="admin").count()
    others = total_users - freelancers - students
    
    growth_list = []
    now = datetime.now(timezone.utc)
    for i in range(5, -1, -1):
        month_dt = now - timedelta(days=i*30)
        m_start = month_dt.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        if m_start.month == 12:
            m_end = m_start.replace(year=m_start.year+1, month=1)
        else:
            m_end = m_start.replace(month=m_start.month+1)
            
        cnt = User.query.filter(User.created_at >= m_start, User.created_at < m_end).count()
        growth_list.append({
            "month": m_start.strftime("%b"),
            "count": cnt
        })

    total_storage_bytes = (
        db.session.query(func.coalesce(func.sum(FileMetadata.size_bytes), 0)).scalar()
        or 0
    )
    storage_usage_mb = round(float(total_storage_bytes) / (1024 * 1024), 2)

    thirty_days_ago = datetime.now(timezone.utc) - timedelta(days=30)
    active_users = (
        db.session.query(func.count(func.distinct(LoginLog.user_id)))
        .filter(
            LoginLog.status == "success",
            LoginLog.timestamp >= thirty_days_ago,
            LoginLog.user_id.isnot(None),
        )
        .scalar()
        or 0
    )
        
    return {
        "cards": {
            "system_health": 100,
            "storage_usage_mb": storage_usage_mb,
            "total_users": total_users,
            "active_users": active_users,
            "total_projects": total_projects,
            "pending_disputes": pending_disputes,
            "open_tasks": open_tasks,
            "ai_requests_today": ai_requests_today
        },
        "charts": {
            "ratios": {
                "freelancers": freelancers,
                "students": students,
                "admins": admins,
                "others": max(0, others)
            },
            "user_growth": growth_list
        }
    }

def list_admin_users(*args, **kwargs):
    search = kwargs.get("search", "")
    filter_status = kwargs.get("filter_status", "")
    filter_type = kwargs.get("filter_type", "")
    page = kwargs.get("page", 1)
    per_page = kwargs.get("per_page", 20)
    
    q = User.query
    if search:
        q = q.filter(or_(
            User.display_name.ilike(f"%{search}%"),
            User.full_name.ilike(f"%{search}%"),
            User.email.ilike(f"%{search}%")
        ))
        
    if filter_status:
        if filter_status == "active":
            q = q.filter(User.account_status == "approved")
        elif filter_status == "locked":
            q = q.filter(User.locked_until != None)
        elif filter_status == "pending":
            q = q.filter(User.account_status == "pending")
        elif filter_status == "rejected":
            q = q.filter(User.account_status == "rejected")
            
    if filter_type:
        q = q.filter(User.user_type == filter_type)
        
    p = q.order_by(User.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)
    
    return {
        "items": [u.to_dict() for u in p.items],
        "total": p.total,
        "page": p.page,
        "pages": p.pages,
        "per_page": p.per_page
    }


_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
def _unique_display_name(base: str) -> str:
    """Pick a unique display_name from an email local-part or name slug."""
    slug = re.sub(r"[^a-zA-Z0-9_]", "", base.lower())[:40] or "user"
    candidate = slug
    n = 1
    while User.query.filter_by(display_name=candidate).first():
        candidate = f"{slug}{n}"[:80]
        n += 1
    return candidate


def create_admin_user(full_name, email, password, role_label, password_hasher):
    """
    Create a user from the admin panel.
    role_label: 'Admin' | 'Freelancer' | 'Student' (UI labels).
    Returns (user_dict, error_message).
    """
    full_name = (full_name or "").strip()
    email = (email or "").strip().lower()
    password = password or ""
    role_label = (role_label or "Freelancer").strip()

    errors = []
    if not full_name:
        errors.append("full_name is required")
    if not email or not _EMAIL_RE.match(email):
        errors.append("valid email is required")
    ok, pw_msg = sys_settings.validate_password(password)
    if not ok:
        errors.append(pw_msg)
    if errors:
        return None, "; ".join(errors)

    if User.query.filter_by(email=email).first():
        return None, "Email already exists"

    label = role_label.lower()
    if label == "admin":
        system_role = "admin"
        user_type = "freelancer"
    elif label == "student":
        system_role = "member"
        user_type = "student"
    else:
        system_role = "member"
        user_type = "freelancer"

    display_name = _unique_display_name(email.split("@")[0])

    hashed = password_hasher.generate_password_hash(password).decode("utf-8")
    user = User(
        display_name=display_name,
        full_name=full_name,
        email=email,
        password=hashed,
        role=system_role,
        user_type=user_type,
        account_status="approved",
    )
    db.session.add(user)
    db.session.commit()
    return user.to_dict(), None


def delete_user_account(user_id: int) -> tuple[bool, str | None]:
    """
    Permanently delete a user and clean up rows that block FK constraints.
    Returns (success, error_message).
    """
    user = db.session.get(User, user_id)
    if not user:
        return False, "User not found"

    try:
        Dispute.query.filter(
            or_(Dispute.reporter_id == user_id, Dispute.accused_id == user_id)
        ).delete(synchronize_session=False)
        Dispute.query.filter_by(resolved_by=user_id).update(
            {Dispute.resolved_by: None}, synchronize_session=False
        )

        Notification.query.filter_by(user_id=user_id).delete(synchronize_session=False)
        Log.query.filter_by(user_id=user_id).delete(synchronize_session=False)

        owned_ids = [
            p.id for p in Project.query.filter_by(user_id=user_id).all()
        ]
        for pid in owned_ids:
            Task.query.filter_by(project_id=pid).delete(synchronize_session=False)

            room_ids = [
                r.id for r in ChatRoom.query.filter_by(project_id=pid).all()
            ]
            for rid in room_ids:
                MeetingSession.query.filter_by(room_id=rid).delete(
                    synchronize_session=False
                )
                Message.query.filter_by(room_id=rid).delete(synchronize_session=False)
                ChatRoomMember.query.filter_by(room_id=rid).delete(
                    synchronize_session=False
                )
            ChatRoom.query.filter_by(project_id=pid).delete(synchronize_session=False)

            db.session.execute(
                text("UPDATE disputes SET project_id = NULL WHERE project_id = :pid"),
                {"pid": pid},
            )
            FileMetadata.query.filter_by(project_id=pid).update(
                {FileMetadata.project_id: None}, synchronize_session=False
            )
            ProjectMember.query.filter_by(project_id=pid).delete(
                synchronize_session=False
            )
            project = db.session.get(Project, pid)
            if project:
                db.session.delete(project)

        Task.query.filter_by(assigned_to=user_id).update(
            {Task.assigned_to: None}, synchronize_session=False
        )
        Alert.query.filter_by(resolved_by=user_id).update(
            {Alert.resolved_by: None}, synchronize_session=False
        )

        db.session.delete(user)
        db.session.commit()
        return True, None
    except Exception as exc:
        db.session.rollback()
        logger.exception("delete_user_account failed for user_id=%s", user_id)
        return False, str(exc)


def update_user_status(user_id, action, reason=""):
    user = db.session.get(User, user_id)
    if not user:
        return {}, "User not found"
        
    action = action.lower()
    if action == "approve":
        user.account_status = "approved"
        user.account_status_note = None
    elif action == "reject":
        user.account_status = "rejected"
        user.account_status_note = reason
    elif action == "lock":
        user.account_status = "locked"
        user.locked_until = datetime.now(timezone.utc) + timedelta(days=365)
        user.failed_login_attempts = 99
        user.account_status_note = reason
    elif action == "suspend":
        user.account_status = "suspended"
        user.account_status_note = reason
    elif action == "unlock":
        user.account_status = "approved"
        user.locked_until = None
        user.failed_login_attempts = 0
        user.account_status_note = None
    else:
        return {}, f"Invalid action: {action}"
        
    db.session.commit()
    return user.to_dict(), None

def list_admin_projects(*args, **kwargs):
    search = kwargs.get("search", "")
    filter_status = kwargs.get("filter_status", "")
    page = kwargs.get("page", 1)
    per_page = kwargs.get("per_page", 20)
    
    q = Project.query
    if search:
        q = q.filter(Project.name.ilike(f"%{search}%"))
        
    if filter_status:
        q = q.filter(Project.status == filter_status)
        
    p = q.order_by(Project.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)
    
    return {
        "items": [pr.to_dict() for pr in p.items],
        "total": p.total,
        "page": p.page,
        "pages": p.pages,
        "per_page": p.per_page
    }

def reassign_project_owner(project_id, new_owner_id):
    project = db.session.get(Project, project_id)
    if not project:
        return {}, "Project not found"
        
    new_owner = db.session.get(User, new_owner_id)
    if not new_owner:
        return {}, "New owner user not found"
        
    project.user_id = new_owner_id
    db.session.commit()
    return project.to_dict(), None

def list_admin_tasks(*args, **kwargs):
    search = kwargs.get("search", "")
    project_id = kwargs.get("project_id")
    assigned_to = kwargs.get("assigned_to")
    priority = kwargs.get("priority", "")
    status = kwargs.get("status", "")
    page = kwargs.get("page", 1)
    per_page = kwargs.get("per_page", 20)
    
    q = Task.query
    if search:
        q = q.filter(or_(
            Task.title.ilike(f"%{search}%"),
            Task.description.ilike(f"%{search}%")
        ))
    if project_id:
        q = q.filter(Task.project_id == project_id)
    if assigned_to:
        q = q.filter(Task.assigned_to == assigned_to)
    if priority:
        q = q.filter(Task.priority == priority)
    if status:
        q = q.filter(Task.status == status)
        
    p = q.order_by(Task.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)
    
    return {
        "items": [t.to_dict() for t in p.items],
        "total": p.total,
        "page": p.page,
        "pages": p.pages,
        "per_page": p.per_page
    }

def get_ai_monitoring_metrics():
    import json
    from collections import Counter
    from models.audit_log import AuditLog

    today_start = datetime.now(timezone.utc).replace(
        hour=0, minute=0, second=0, microsecond=0
    )

    def _details(log: AuditLog) -> dict:
        try:
            return json.loads(log.details or "{}")
        except (TypeError, json.JSONDecodeError):
            return {}

    today_logs = (
        AuditLog.query.filter(
            AuditLog.action == "AI_REQUEST",
            AuditLog.created_at >= today_start,
        )
        .order_by(AuditLog.created_at.desc())
        .all()
    )
    recent_logs = today_logs[:20]

    failed_calls = sum(
        1 for log in today_logs
        if _details(log).get("status") != "success"
        or (_details(log).get("status_code") or 200) >= 400
    )
    latencies_ms = [
        int(_details(log).get("latency_ms") or 0)
        for log in today_logs
        if _details(log).get("latency_ms") is not None
    ]
    avg_latency_s = round(
        (sum(latencies_ms) / len(latencies_ms) / 1000.0) if latencies_ms else 0.0,
        2,
    )
    token_usage = sum(int(_details(log).get("token_usage") or 0) for log in today_logs)

    endpoint_counts = Counter(
        _details(log).get("endpoint") or "unknown" for log in today_logs
    )
    most_used_endpoint = endpoint_counts.most_common(1)[0][0] if endpoint_counts else None

    def _feature_label(endpoint: str | None) -> str:
        if not endpoint or endpoint == "unknown":
            return "None"
        labels = {
            "predict-delay": "Delay Predictor",
            "classify-task": "Task Classifier",
            "summarize-chat": "Chat Summarizer",
            "transcribe": "Speech Transcription",
            "mentor-report": "Mentor Report",
            "mentor/analyse": "Mentor Analysis",
            "recommend-teammates": "Teammate Matching",
            "detect-anomaly": "Anomaly Detection",
            "suggest-priority": "Priority Suggester",
            "suggest-deadline": "Deadline Suggester",
            "cv/build": "CV Builder",
            "feedback-assist": "Feedback Assistant",
        }
        for key, label in labels.items():
            if key in endpoint:
                return label
        slug = endpoint.rstrip("/").rsplit("/", 1)[-1]
        return slug.replace("-", " ").title() if slug else "None"

    def _user_name(uid):
        if not uid:
            return "System"
        u = db.session.get(User, uid)
        return (u.full_name or u.display_name or u.email) if u else "Deleted user"

    return {
        "metrics": {
            "total_ai_requests": len(today_logs),
            "failed_ai_calls": failed_calls,
            "average_response_time": avg_latency_s,
            "token_usage": token_usage,
            "most_used_feature": _feature_label(most_used_endpoint),
        },
        "recent_requests": [
            {
                "id": log.id,
                "endpoint": _details(log).get("endpoint") or "unknown",
                "feature": _feature_label(_details(log).get("endpoint")),
                "user_name": _user_name(log.user_id),
                "status": _details(log).get("status") or "success",
                "duration": round((_details(log).get("latency_ms") or 0) / 1000.0, 2),
                "token_usage": _details(log).get("token_usage") or 0,
                "timestamp": log.created_at.isoformat() if log.created_at else None,
            }
            for log in recent_logs
        ],
    }

def send_system_announcement(target, title, body, specific_user_id=None):
    from datetime import date
    import hashlib

    from routes.notifications import create_notification

    users = []
    if target == "specific" and specific_user_id:
        u = db.session.get(User, specific_user_id)
        if u:
            users.append(u)
    elif target == "students":
        users = User.query.filter_by(user_type="student").all()
    elif target == "freelancers":
        users = User.query.filter_by(user_type="freelancer").all()
    else:
        users = User.query.all()

    digest = hashlib.sha256(f"{title}\n{body}".encode("utf-8")).hexdigest()[:16]
    day = date.today().isoformat()
    count = 0
    for u in users:
        create_notification(
            user_id=u.id,
            notif_type="admin_announcement",
            title=title,
            body=body,
            entity_type="Announcement",
            email_idempotency_key=f"announce:{u.id}:{digest}:{day}",
        )
        count += 1

    db.session.commit()
    return count

def get_security_center_data():
    from datetime import timedelta
    from services.security_session_service import count_active_sessions, is_automation_agent

    now = datetime.now(timezone.utc)
    day_ago = now - timedelta(hours=24)
    hour_ago = now - timedelta(hours=1)

    failed_logins_24h = (
        LoginLog.query.filter(LoginLog.status == "fail", LoginLog.timestamp >= day_ago)
        .count()
    )
    locked_users = User.query.filter(
        or_(
            User.account_status == "locked",
            and_(User.locked_until.isnot(None), User.locked_until > now),
        )
    ).count()
    suspicious_alerts_count = Alert.query.filter_by(resolved=False).count()
    active_sessions = count_active_sessions()

    alerts = Alert.query.filter_by(resolved=False).order_by(Alert.timestamp.desc()).limit(10).all()
    raw_logins = LoginLog.query.order_by(LoginLog.timestamp.desc()).limit(50).all()

    def _user_name(uid):
        if not uid:
            return "Unknown user"
        u = db.session.get(User, uid)
        return (u.full_name or u.display_name or u.email) if u else "Deleted user"

    def _alert_payload(alert: Alert) -> dict:
        user_id = None
        ip_match = re.search(r"\d{1,3}(?:\.\d{1,3}){3}", alert.description or "")
        if ip_match:
            recent_fail = (
                LoginLog.query.filter(
                    LoginLog.status == "fail",
                    LoginLog.ip_address == ip_match.group(0),
                    LoginLog.user_id.isnot(None),
                )
                .order_by(LoginLog.timestamp.desc())
                .first()
            )
            if recent_fail:
                user_id = recent_fail.user_id
        return {
            "id": alert.id,
            "type": alert.type,
            "description": alert.description,
            "details": alert.description,
            "user_id": user_id,
            "timestamp": alert.timestamp.isoformat() if alert.timestamp else None,
        }

    human_logins = []
    for log in raw_logins:
        if is_automation_agent(log.device_info):
            continue
        human_logins.append(log)
        if len(human_logins) >= 15:
            break

    return {
        "metrics": {
            "failed_logins": failed_logins_24h,
            "failed_logins_window": "24h",
            "locked_users": locked_users,
            "active_sessions": active_sessions,
            "recent_logins_1h": (
                LoginLog.query.filter(
                    LoginLog.status == "success",
                    LoginLog.timestamp >= hour_ago,
                )
                .filter(~LoginLog.device_info.ilike("%python-requests%"))
                .count()
            ),
            "suspicious_activity_alerts": suspicious_alerts_count,
        },
        "alerts": [_alert_payload(a) for a in alerts],
        "logins": [
            {
                "id": l.id,
                "status": l.status,
                "user_name": _user_name(l.user_id),
                "ip_address": l.ip_address,
                "device_info": l.device_info or "Unknown device",
                "user_id": l.user_id,
                "timestamp": l.timestamp.isoformat() if l.timestamp else None,
                "is_automation": is_automation_agent(l.device_info),
            }
            for l in human_logins
        ],
    }

def get_system_settings():
    return sys_settings.get_system_settings()


def update_system_settings(data):
    return sys_settings.update_system_settings(data)
