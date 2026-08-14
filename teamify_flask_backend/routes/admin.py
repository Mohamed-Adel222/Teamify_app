"""
Full System-Admin blueprint.
Covers all admin dashboard metrics, user controls, project/task monitoring, AI auditing, disputes, settings, and security.
"""
from datetime import datetime, timezone
import csv
import io

from flask import Blueprint, jsonify, request, make_response
from flask_jwt_extended import get_jwt_identity, jwt_required
from flask_bcrypt import Bcrypt

from middleware.auth import admin_required
from utils.pagination import parse_pagination
from models import db
from models.user import User
from models.project import Project
from models.task import Task
from models.dispute import Dispute
from models.file_metadata import FileMetadata
from models.login_log import LoginLog
from models.alert import Alert
from models.audit_log import AuditLog
from models.log import Log

from sqlalchemy import func
import services.admin_service as admin_service
from services.analytics_snapshot_service import compute_user_retention
from utils.admin_audit import log_admin_action

admin_bp = Blueprint("admin", __name__, url_prefix="/admin")
bcrypt = Bcrypt()

# ─── Helpers ──────────────────────────────────────────────────────────────────

def _page_args(default=20, max_pp=200):
    page, per_page, page_err = parse_pagination(
        default_per_page=default,
        max_per_page=max_pp,
    )
    if page_err:
        return None, None, page_err
    return page, per_page, None


# ══════════════════════════════════════════════════════════════════════════════
# 1.  ADMIN DASHBOARD
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/dashboard", methods=["GET"])
@admin_required
def get_dashboard_summary():
    """Retrieve full dashboard statistics for cards and charts."""
    data = admin_service.get_admin_dashboard_stats()
    return jsonify(data), 200


# ══════════════════════════════════════════════════════════════════════════════
# 2.  USER MANAGEMENT
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/users", methods=["GET"])
@admin_required
def list_users():
    """Paginated, filtered and searchable list of all users."""
    search = request.args.get("search", "").strip()
    filter_status = request.args.get("status", "").strip()  # active, locked, pending
    filter_type = request.args.get("user_type", "").strip()  # freelancer, student
    page, per_page, page_err = _page_args()
    if page_err:
        return page_err
    
    result = admin_service.list_admin_users(
        search=search,
        filter_status=filter_status,
        filter_type=filter_type,
        page=page,
        per_page=per_page
    )
    return jsonify(result), 200


@admin_bp.route("/users", methods=["POST"])
@admin_required
def create_user():
    """Create a new user account (admin only)."""
    data = request.get_json(silent=True) or {}
    full_name = data.get("full_name", "")
    email = data.get("email", "")
    password = data.get("password", "")
    role = data.get("role", "Freelancer")

    user_dict, err = admin_service.create_admin_user(
        full_name, email, password, role, bcrypt
    )
    if err or not user_dict:
        status = 409 if err and "already exists" in err.lower() else 400
        return jsonify({"error": err or "User creation failed"}), status

    admin_id = int(get_jwt_identity())
    log_admin_action(
        admin_id=admin_id,
        action="ADMIN_CREATE_USER",
        entity="User",
        entity_id=user_dict["id"],
        details=f"Admin {admin_id} created user {user_dict.get('email')}",
    )
    db.session.commit()

    return jsonify({"message": "User created successfully", "user": user_dict}), 201


@admin_bp.route("/users/<int:user_id>/status", methods=["PATCH"])
@admin_required
def change_user_status(user_id):
    """Approve, reject, lock, unlock or suspend a user account."""
    data = request.get_json(silent=True) or {}
    action = data.get("action", "").strip().lower()  # approve, reject, lock, suspend, unlock
    reason = data.get("reason", "").strip()

    if not action:
        return jsonify({"error": "action field is required"}), 400

    result, err = admin_service.update_user_status(user_id, action, reason)
    if err:
        return jsonify({"error": err}), 404 if "not found" in err.lower() else 400

    # Log action
    admin_id = int(get_jwt_identity())
    log_admin_action(
        admin_id=admin_id,
        action=f"USER_{action.upper()}",
        entity="User",
        entity_id=user_id,
        details=f"Admin {admin_id} executed action {action} on User {user_id}. Reason: {reason}",
    )
    db.session.commit()

    return jsonify({"message": f"User status updated successfully", "user": result}), 200


@admin_bp.route("/users/<int:user_id>/role", methods=["PATCH"])
@admin_required
def change_user_role(user_id):
    """Change role of any user account."""
    user = db.session.get(User, user_id)
    if not user:
        return jsonify({"error": "User not found"}), 404

    data = request.get_json(silent=True) or {}
    role = data.get("role", "").strip().lower()
    if role not in ["admin", "member", "guest"]:
        return jsonify({"error": "Invalid role. Must be 'admin', 'member', or 'guest'"}), 400

    user.role = role
    try:
        from routes.notifications import create_notification

        create_notification(
            user_id=user_id,
            notif_type="role_changed",
            title="Your role was updated",
            body=f"Your Teamify role is now '{role}'.",
            entity_type="User",
            entity_id=user_id,
        )
    except Exception:
        pass
    db.session.commit()

    admin_id = int(get_jwt_identity())
    log_admin_action(
        admin_id=admin_id,
        action="CHANGE_ROLE",
        entity="User",
        entity_id=user_id,
        details=f"Admin {admin_id} changed User {user_id} role to {role}",
    )
    db.session.commit()

    return jsonify({"message": "User role updated successfully", "user": user.to_dict()}), 200


@admin_bp.route("/users/<int:user_id>/reset-password", methods=["PATCH"])
@admin_required
def reset_user_password(user_id):
    """Reset password of a user account securely."""
    user = db.session.get(User, user_id)
    if not user:
        return jsonify({"error": "User not found"}), 404

    data = request.get_json(silent=True) or {}
    new_password = data.get("password", "").strip()
    if not new_password:
        return jsonify({"error": "Password is required"}), 400

    from services.system_settings_service import validate_password

    ok, pw_msg = validate_password(new_password)
    if not ok:
        return jsonify({"error": pw_msg}), 400

    user.password = bcrypt.generate_password_hash(new_password).decode("utf-8")
    db.session.commit()

    admin_id = int(get_jwt_identity())
    log_admin_action(
        admin_id=admin_id,
        action="RESET_PASSWORD",
        entity="User",
        entity_id=user_id,
        details=f"Admin {admin_id} reset password of User {user_id}",
        severity="WARNING",
    )
    db.session.commit()

    return jsonify({"message": "User password reset successfully"}), 200


@admin_bp.route("/users/<int:user_id>", methods=["DELETE"])
@admin_required
def force_delete_user(user_id):
    """Permanently delete a user account and related data."""
    admin_id = int(get_jwt_identity())
    if user_id == admin_id:
        return jsonify({"error": "You cannot delete your own account"}), 400

    ok, err = admin_service.delete_user_account(user_id)
    if not ok:
        status = 404 if err and "not found" in err.lower() else 409
        return jsonify({
            "error": err or "Could not delete user",
            "message": err or "Could not delete user",
        }), status

    log_admin_action(
        admin_id=admin_id,
        action="DELETE_USER",
        entity="User",
        entity_id=user_id,
        details=f"Admin {admin_id} deleted User {user_id}",
        severity="WARNING",
    )
    db.session.commit()

    return jsonify({"message": f"User {user_id} successfully deleted"}), 200


# ══════════════════════════════════════════════════════════════════════════════
# 3.  PROJECT MANAGEMENT
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/projects", methods=["GET"])
@admin_required
def list_projects():
    """Retrieve all projects with risk levels, overdue count, and filters."""
    search = request.args.get("search", "").strip()
    filter_status = request.args.get("status", "").strip()  # active, completed, delayed, high_risk
    page, per_page, page_err = _page_args()
    if page_err:
        return page_err

    result = admin_service.list_admin_projects(
        search=search,
        filter_status=filter_status,
        page=page,
        per_page=per_page
    )
    return jsonify(result), 200


@admin_bp.route("/projects/<int:project_id>/reassign", methods=["PATCH"])
@admin_required
def reassign_project(project_id):
    """Reassign project ownership to a different user."""
    data = request.get_json(silent=True) or {}
    new_owner_id = data.get("owner_id")
    if not new_owner_id:
        return jsonify({"error": "owner_id field is required"}), 400

    result, err = admin_service.reassign_project_owner(project_id, int(new_owner_id))
    if err:
        return jsonify({"error": err}), 400

    admin_id = int(get_jwt_identity())
    log_admin_action(
        admin_id=admin_id,
        action="REASSIGN_PROJECT",
        entity="Project",
        entity_id=project_id,
        details=f"Admin {admin_id} reassigned Project {project_id} to User {new_owner_id}",
    )
    db.session.commit()

    return jsonify({"message": "Project owner reassigned successfully", "project": result}), 200


@admin_bp.route("/projects/<int:project_id>", methods=["DELETE"])
@admin_required
def force_delete_project(project_id):
    """Permanently delete a project."""
    project = db.session.get(Project, project_id)
    if not project:
        return jsonify({"error": "Project not found"}), 404

    db.session.delete(project)
    db.session.commit()

    admin_id = int(get_jwt_identity())
    log_admin_action(
        admin_id=admin_id,
        action="DELETE_PROJECT",
        entity="Project",
        entity_id=project_id,
        details=f"Admin {admin_id} deleted Project {project_id}",
        severity="WARNING",
    )
    db.session.commit()

    return jsonify({"message": f"Project {project_id} deleted successfully"}), 200


# ══════════════════════════════════════════════════════════════════════════════
# 4.  TASK MANAGEMENT
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/tasks", methods=["GET"])
@admin_required
def list_tasks():
    """Retrieve all tasks with assignments, priority, project, and filters."""
    search = request.args.get("search", "").strip()
    project_id = request.args.get("project_id", type=int)
    assigned_to = request.args.get("assigned_to", type=int)
    priority = request.args.get("priority", "").strip()
    status = request.args.get("status", "").strip()
    page, per_page, page_err = _page_args()
    if page_err:
        return page_err

    result = admin_service.list_admin_tasks(
        search=search,
        project_id=project_id,
        assigned_to=assigned_to,
        priority=priority,
        status=status,
        page=page,
        per_page=per_page
    )
    return jsonify(result), 200


@admin_bp.route("/tasks/<int:task_id>", methods=["PATCH"])
@admin_required
def edit_task(task_id):
    """Change status, assignment or other details of a task."""
    task = db.session.get(Task, task_id)
    if not task:
        return jsonify({"error": "Task not found"}), 404

    data = request.get_json(silent=True) or {}
    
    if "status" in data:
        task.status = data["status"]
    if "assigned_to" in data:
        task.assigned_to = data["assigned_to"]
    if "priority" in data:
        task.priority = data["priority"]
    if "due_date" in data:
        task.due_date = datetime.strptime(data["due_date"], "%Y-%m-%d").date()

    db.session.commit()

    admin_id = int(get_jwt_identity())
    log_admin_action(
        admin_id=admin_id,
        action="UPDATE_TASK",
        entity="Task",
        entity_id=task_id,
        details=f"Admin {admin_id} updated Task {task_id}",
    )
    db.session.commit()

    return jsonify({"message": "Task updated successfully", "task": task.to_dict()}), 200


@admin_bp.route("/tasks/<int:task_id>", methods=["DELETE"])
@admin_required
def force_delete_task(task_id):
    """Force delete a task."""
    task = db.session.get(Task, task_id)
    if not task:
        return jsonify({"error": "Task not found"}), 404

    db.session.delete(task)
    db.session.commit()

    admin_id = int(get_jwt_identity())
    log_admin_action(
        admin_id=admin_id,
        action="DELETE_TASK",
        entity="Task",
        entity_id=task_id,
        details=f"Admin {admin_id} deleted Task {task_id}",
        severity="WARNING",
    )
    db.session.commit()

    return jsonify({"message": f"Task {task_id} deleted successfully"}), 200


# ══════════════════════════════════════════════════════════════════════════════
# 5.  AI MONITOR
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/ai/metrics", methods=["GET"])
@admin_required
def get_ai_metrics():
    """Retrieve AI metrics and recent requests."""
    result = admin_service.get_ai_monitoring_metrics()
    return jsonify(result), 200


# ══════════════════════════════════════════════════════════════════════════════
# 6.  DISPUTES
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/disputes", methods=["GET"])
@admin_required
def list_disputes():
    """Retrieve all conflicts raised on the platform."""
    page, per_page, page_err = _page_args()
    if page_err:
        return page_err
    status = request.args.get("status", "").strip()
    category = request.args.get("category", "").strip()

    q = Dispute.query
    if status:
        q = q.filter(Dispute.status == status)
    if category:
        q = q.filter(Dispute.category == category)

    p = q.order_by(Dispute.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)
    
    items = []
    for d in p.items:
        dict_val = d.to_dict()
        
        reporter = db.session.get(User, d.reporter_id)
        accused = db.session.get(User, d.accused_id)
        project = db.session.get(Project, d.project_id) if d.project_id else None
        
        dict_val["reporter_name"] = (reporter.full_name or reporter.display_name) if reporter else "Unknown"
        dict_val["accused_name"] = (accused.full_name or accused.display_name) if accused else "Unknown"
        dict_val["project_name"] = project.name if project else "General Platform"
        
        items.append(dict_val)

    return jsonify({
        "items": items,
        "total": p.total,
        "page": p.page,
        "pages": p.pages,
        "per_page": p.per_page
    }), 200


@admin_bp.route("/disputes/<int:dispute_id>/resolve", methods=["PATCH"])
@admin_required
def resolve_dispute(dispute_id):
    """Resolve or dismiss a conflict with details."""
    dispute = db.session.get(Dispute, dispute_id)
    if not dispute:
        return jsonify({"error": "Dispute not found"}), 404

    data = request.get_json(silent=True) or {}
    resolution = data.get("resolution", "").strip()
    action = data.get("action", "resolve").strip().lower()  # resolve, reject

    if not resolution:
        return jsonify({"error": "resolution details are required"}), 400

    admin_id = int(get_jwt_identity())
    dispute.status = "resolved" if action == "resolve" else "dismissed"
    dispute.resolution = resolution
    dispute.resolved_by = admin_id
    dispute.resolved_at = datetime.now(timezone.utc)

    db.session.commit()

    log_admin_action(
        admin_id=admin_id,
        action="RESOLVE_DISPUTE",
        entity="Dispute",
        entity_id=dispute_id,
        details=f"Admin {admin_id} resolved Dispute {dispute_id} as {dispute.status}. Notes: {resolution}",
    )
    db.session.commit()

    return jsonify({"message": f"Dispute marked as {dispute.status}", "dispute": dispute.to_dict()}), 200


# ══════════════════════════════════════════════════════════════════════════════
# 7.  NOTIFICATIONS CENTER
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/notifications", methods=["POST"])
@admin_required
def broadcast_notification():
    """Send announcements or maintenance alerts to a target cohort of users."""
    data = request.get_json(silent=True) or {}
    target = data.get("target", "all").strip().lower()  # all, students, freelancers, specific
    title = data.get("title", "").strip()
    body = data.get("body", "").strip()
    specific_user_id = data.get("user_id")

    if not title or not body:
        return jsonify({"error": "title and body fields are required"}), 400

    notif_count = admin_service.send_system_announcement(target, title, body, specific_user_id)

    admin_id = int(get_jwt_identity())
    from models.admin_panel import BroadcastHistory

    broadcast = BroadcastHistory()
    broadcast.admin_id = admin_id
    broadcast.target_audience = target
    broadcast.title = title
    broadcast.body = body
    broadcast.recipient_count = notif_count
    db.session.add(broadcast)
    log_admin_action(
        admin_id=admin_id,
        action="BROADCAST_NOTIFICATION",
        entity="Notification",
        details=f"Broadcast '{title}' to {target} ({notif_count} recipients)",
    )
    db.session.commit()

    return jsonify({"message": f"Broadcast successfully sent to {notif_count} users"}), 200


# ══════════════════════════════════════════════════════════════════════════════
# 8.  FILE MANAGEMENT
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/files", methods=["GET"])
@admin_required
def list_files():
    """Retrieve all uploaded files, sorted and searchable."""
    search = request.args.get("search", "").strip()
    owner_id = request.args.get("owner_id", type=int)
    page, per_page, page_err = _page_args()
    if page_err:
        return page_err

    q = FileMetadata.query
    if owner_id:
        q = q.filter(FileMetadata.owner_id == owner_id)
    if search:
        q = q.filter(FileMetadata.original_filename.ilike(f"%{search}%"))

    p = q.order_by(FileMetadata.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)

    items = []
    for f in p.items:
        dict_val = f.to_dict()
        user = db.session.get(User, f.owner_id)
        dict_val["owner_name"] = (user.full_name or user.display_name) if user else "System"
        items.append(dict_val)

    return jsonify({
        "items": items,
        "total": p.total,
        "page": p.page,
        "pages": p.pages,
        "per_page": p.per_page
    }), 200


@admin_bp.route("/files/<int:file_id>", methods=["DELETE"])
@admin_required
def force_delete_file(file_id):
    """Force remove file pointer from db."""
    file = db.session.get(FileMetadata, file_id)
    if not file:
        return jsonify({"error": "File not found"}), 404

    db.session.delete(file)
    db.session.commit()

    admin_id = int(get_jwt_identity())
    log_admin_action(
        admin_id=admin_id,
        action="DELETE_FILE",
        entity="FileMetadata",
        entity_id=file_id,
        details=f"Admin {admin_id} deleted File {file_id}",
        severity="WARNING",
    )
    db.session.commit()

    return jsonify({"message": f"File pointer {file_id} successfully deleted"}), 200


# ══════════════════════════════════════════════════════════════════════════════
# 9.  ACTIVITY LOGS
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/logs", methods=["GET"])
@admin_required
def list_logs():
    """Retrieve full audit/activity logs."""
    page, per_page, page_err = _page_args()
    if page_err:
        return page_err
    q = Log.query

    # Apply filters
    action = request.args.get("action", "").strip()
    entity = request.args.get("entity", "").strip()
    user_id = request.args.get("user_id", type=int)
    search = request.args.get("search", "").strip()

    if action:
        q = q.filter(Log.action == action.upper())
    if entity:
        q = q.filter(Log.entity == entity)
    if user_id:
        q = q.filter(Log.user_id == user_id)
    if search:
        from sqlalchemy import or_
        pattern = f"%{search}%"
        q = q.filter(or_(Log.action.ilike(pattern), Log.entity.ilike(pattern), Log.details.ilike(pattern)))

    p = q.order_by(Log.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)
    
    items = []
    for log in p.items:
        dict_val = log.to_dict()
        user = db.session.get(User, log.user_id)
        dict_val["user_name"] = (user.full_name or user.display_name) if user else "System/Unknown"
        items.append(dict_val)

    return jsonify({
        "items": items,
        "total": p.total,
        "page": p.page,
        "pages": p.pages,
        "per_page": p.per_page
    }), 200


# ══════════════════════════════════════════════════════════════════════════════
# 10. SECURITY CENTER
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/security", methods=["GET"])
@admin_required
def get_security_summary():
    """Retrieve security monitoring, active sessions, and logins."""
    data = admin_service.get_security_center_data()
    return jsonify(data), 200


@admin_bp.route("/security/revoke-session/<int:user_id>", methods=["POST"])
@admin_required
def revoke_user_sessions(user_id):
    """Force logout a user from all devices by blocklisting their tokens."""
    user = db.session.get(User, user_id)
    if not user:
        return jsonify({"error": "User not found"}), 404

    from services.security_session_service import revoke_all_user_sessions

    revoked = revoke_all_user_sessions(user_id)
    user.failed_login_attempts = 0
    db.session.commit()

    admin_id = int(get_jwt_identity())
    log_admin_action(
        admin_id=admin_id,
        action="REVOKE_SESSION",
        entity="User",
        entity_id=user_id,
        details=f"Admin {admin_id} revoked all active sessions of User {user_id}",
        severity="WARNING",
    )
    db.session.commit()

    return jsonify({
        "message": f"Revoked {revoked} active session(s) for user {user_id}",
        "revoked_count": revoked,
    }), 200


# ══════════════════════════════════════════════════════════════════════════════
# 11. ANALYTICS
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/analytics", methods=["GET"])
@admin_required
def get_analytics():
    """Provide detailed system analytics for advanced charts."""
    # 1. Most productive teams (by project completion rate)
    projects = Project.query.all()
    project_success = []
    for p in projects:
        progress = p._compute_progress()
        project_success.append({
            "project_name": p.name,
            "owner": p.owner_name,
            "progress": progress,
            "member_count": p.member_count
        })
    project_success = sorted(project_success, key=lambda x: x["progress"], reverse=True)[:5]

    # 2. Most active users (by task completion count)
    active_users_query = db.session.query(
        User.id, User.full_name, User.display_name, func.count(Task.id).label('tasks')
    ).join(Task, Task.assigned_to == User.id)\
     .filter(Task.status == 'done')\
     .group_by(User.id).order_by(func.count(Task.id).desc()).limit(5).all()

    active_users = [
        {"id": u.id, "name": u.full_name or u.display_name, "tasks_completed": u.tasks}
        for u in active_users_query
    ]

    # 3. Overall numbers
    total_tasks = Task.query.count()
    done_tasks = Task.query.filter_by(status='done').count()
    task_completion_rate = round(done_tasks / total_tasks * 100, 1) if total_tasks else 0

    return jsonify({
        "most_productive_teams": project_success,
        "most_active_users": active_users,
        "task_completion_rate": task_completion_rate,
        "project_success_rate": 100.0 if projects else 0.0,
        "user_retention": compute_user_retention()
    }), 200


# ══════════════════════════════════════════════════════════════════════════════
# 12. SETTINGS
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/settings", methods=["GET"])
@admin_required
def get_settings():
    """Retrieve all stored admin system settings."""
    settings = admin_service.get_system_settings()
    return jsonify(settings), 200


@admin_bp.route("/settings", methods=["PUT"])
@admin_required
def update_settings():
    """Save administrative configuration overrides."""
    data = request.get_json(silent=True) or {}
    updated = admin_service.update_system_settings(data)
    
    admin_id = int(get_jwt_identity())
    log_admin_action(
        admin_id=admin_id,
        action="UPDATE_SETTINGS",
        entity="SystemSetting",
        entity_id=0,
        details=f"Admin {admin_id} updated system-wide settings",
    )
    db.session.commit()

    return jsonify({"message": "Settings updated successfully", "settings": updated}), 200


# ══════════════════════════════════════════════════════════════════════════════
# 13. LEGACY TESTS ENDPOINTS
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/users/pending", methods=["GET"])
@admin_required
def list_pending_users():
    page, per_page, page_err = _page_args(20)
    if page_err:
        return page_err
    q = User.query.filter_by(account_status="pending")
    user_type = request.args.get("user_type")
    if user_type:
        q = q.filter(User.user_type == user_type)
    p = q.order_by(User.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)
    return jsonify({
        "items":    [u.to_dict() for u in p.items],
        "total":    p.total,
        "page":     p.page,
        "pages":    p.pages,
    }), 200


@admin_bp.route("/users/<int:user_id>/approve", methods=["PATCH"])
@admin_required
def approve_user(user_id):
    user = db.session.get(User, user_id)
    if not user:
        return jsonify({"error": "User not found"}), 404
    user.account_status      = "approved"
    user.account_status_note = None
    db.session.add(Log(
        action="ADMIN_APPROVE_USER", entity="User", entity_id=user_id,
        details=f"Approved by admin {get_jwt_identity()}", user_id=int(get_jwt_identity()),
    ))
    db.session.commit()
    return jsonify({"message": "User approved", "user": user.to_dict()}), 200


@admin_bp.route("/users/<int:user_id>/reject", methods=["PATCH"])
@admin_required
def reject_user(user_id):
    user = db.session.get(User, user_id)
    if not user:
        return jsonify({"error": "User not found"}), 404
    data = request.get_json(silent=True, force=True) or {}
    user.account_status      = "rejected"
    user.account_status_note = data.get("reason", "Rejected by admin.")
    db.session.add(Log(
        action="ADMIN_REJECT_USER", entity="User", entity_id=user_id,
        details=f"Rejected by admin {get_jwt_identity()}: {user.account_status_note}",
        user_id=int(get_jwt_identity()),
    ))
    db.session.commit()
    return jsonify({"message": "User rejected", "user": user.to_dict()}), 200


@admin_bp.route("/analytics/overview", methods=["GET"])
@admin_required
def analytics_overview():
    from datetime import date, timedelta

    total_users     = User.query.count()
    thirty_days_ago = datetime.now(timezone.utc) - timedelta(days=30)
    active_users    = (
        db.session.query(func.count(func.distinct(LoginLog.user_id)))
        .filter(
            LoginLog.status == "success",
            LoginLog.timestamp >= thirty_days_ago,
            LoginLog.user_id.isnot(None),
        )
        .scalar()
        or 0
    )
    total_projects  = Project.query.count()
    active_projects = Project.query.filter_by(status="active").count()
    total_tasks     = Task.query.count()
    done_tasks      = Task.query.filter_by(status="done").count()
    overdue_tasks   = Task.query.filter(
        Task.status != "done", Task.due_date < date.today()
    ).count()
    completion_rate = round(done_tasks / total_tasks * 100, 1) if total_tasks else 0

    user_type_breakdown = {}
    for row in db.session.query(User.user_type, func.count(User.id)).group_by(User.user_type).all():
        user_type_breakdown[row[0] or "unknown"] = row[1]

    project_status_breakdown = {}
    for row in db.session.query(Project.status, func.count(Project.id)).group_by(Project.status).all():
        project_status_breakdown[row[0]] = row[1]

    task_status_breakdown = {}
    for row in db.session.query(Task.status, func.count(Task.id)).group_by(Task.status).all():
        task_status_breakdown[row[0]] = row[1]

    user_role_breakdown = {}
    for row in db.session.query(User.role, func.count(User.id)).group_by(User.role).all():
        user_role_breakdown[row[0] or "member"] = row[1]

    freelancers = user_type_breakdown.get("freelancer", 0)
    students    = user_type_breakdown.get("student", 0)

    return jsonify({
        "users": {
            "total":       total_users,
            "active":      active_users,
            "freelancers": freelancers,
            "students":    students,
            "by_type":     user_type_breakdown,
            "by_role":     user_role_breakdown,
        },
        "projects": {
            "total":     total_projects,
            "active":    active_projects,
            "by_status": project_status_breakdown,
        },
        "tasks": {
            "total":           total_tasks,
            "done":            done_tasks,
            "overdue":         overdue_tasks,
            "completion_rate": completion_rate,
            "by_status":       task_status_breakdown,
        },
    }), 200


# ── Security Alerts ───────────────────────────────────────────────────────────

@admin_bp.route("/alerts", methods=["GET"])
@admin_required
def list_alerts():
    """Paginated security alert list."""
    page, per_page, page_err = _page_args(50)
    if page_err:
        return page_err
    resolved = request.args.get("resolved")
    alert_type = request.args.get("type", "").strip()

    q = Alert.query
    if resolved is not None:
        q = q.filter(Alert.resolved == (resolved.lower() == "true"))
    if alert_type:
        q = q.filter(Alert.type == alert_type)

    p = q.order_by(Alert.timestamp.desc()).paginate(page=page, per_page=per_page, error_out=False)
    items = []
    for a in p.items:
        d = a.to_dict()
        if a.resolved_by:
            u = db.session.get(User, a.resolved_by)
            d["resolved_by_name"] = (u.full_name or u.display_name or u.email) if u else None
        items.append(d)
    return jsonify({
        "items":    items,
        "total":    p.total,
        "page":     p.page,
        "pages":    p.pages,
        "per_page": p.per_page,
    }), 200


@admin_bp.route("/alerts/<int:alert_id>/resolve", methods=["PATCH"])
@admin_required
def resolve_alert(alert_id):
    """Mark an alert as resolved."""
    alert = db.session.get(Alert, alert_id)
    if not alert:
        return jsonify({"error": "Alert not found"}), 404
    alert.resolved    = True
    alert.resolved_at = datetime.now(timezone.utc)
    alert.resolved_by = int(get_jwt_identity())
    admin_id = int(get_jwt_identity())
    log_admin_action(
        admin_id=admin_id,
        action="RESOLVE_ALERT",
        entity="Alert",
        entity_id=alert_id,
        details=f"Admin {admin_id} resolved alert {alert_id}",
    )
    db.session.commit()
    return jsonify({"message": "Alert resolved", "alert": alert.to_dict()}), 200


# ── Reports Summary ───────────────────────────────────────────────────────────

@admin_bp.route("/reports/summary", methods=["GET"])
@admin_required
def reports_summary():
    """High-level platform summary for Admin Home cards."""
    total_users  = User.query.count()
    freelancers  = User.query.filter_by(user_type="freelancer").count()
    students     = User.query.filter_by(user_type="student").count()
    total_projects = Project.query.count()
    open_alerts  = Alert.query.filter_by(resolved=False).count()

    role_breakdown = {}
    for row in db.session.query(User.role, func.count(User.id)).group_by(User.role).all():
        role_breakdown[row[0] or "member"] = row[1]

    return jsonify({
        "users": {
            "total":       total_users,
            "freelancers": freelancers,
            "students":    students,
            "by_role":     role_breakdown,
        },
        "projects": {
            "total": total_projects,
        },
        "alerts": {
            "open": open_alerts,
        },
    }), 200


# ── Login Logs ────────────────────────────────────────────────────────────────

@admin_bp.route("/login-logs", methods=["GET"])
@admin_required
def list_login_logs():
    """Paginated LoginLog (login audit) list."""
    page, per_page, page_err = _page_args(50)
    if page_err:
        return page_err
    status  = request.args.get("status", "").strip()
    user_id = request.args.get("user_id", type=int)
    ip      = request.args.get("ip", "").strip()

    q = LoginLog.query
    if status:
        q = q.filter(LoginLog.status == status)
    if user_id:
        q = q.filter(LoginLog.user_id == user_id)
    if ip:
        q = q.filter(LoginLog.ip_address.ilike(f"%{ip}%"))

    p = q.order_by(LoginLog.timestamp.desc()).paginate(page=page, per_page=per_page, error_out=False)
    items = []
    for log in p.items:
        d = log.to_dict()
        if log.user_id:
            u = db.session.get(User, log.user_id)
            d["user_name"] = (
                (u.full_name or u.display_name or u.email) if u else "Unknown"
            )
        else:
            d["user_name"] = "Unknown"
        items.append(d)
    return jsonify({
        "items":    items,
        "total":    p.total,
        "page":     p.page,
        "pages":    p.pages,
        "per_page": p.per_page,
    }), 200


# ── Activity Log (alias) ──────────────────────────────────────────────────────

@admin_bp.route("/activity", methods=["GET"])
@admin_required
def list_activity():
    """System action log (Log model) — same data as /logs, kept for compatibility."""
    page, per_page, page_err = _page_args(50)
    if page_err:
        return page_err
    action  = request.args.get("action", "").strip()
    entity  = request.args.get("entity", "").strip()
    user_id = request.args.get("user_id", type=int)

    q = Log.query
    if action:
        q = q.filter(Log.action == action.upper())
    if entity:
        q = q.filter(Log.entity == entity)
    if user_id:
        q = q.filter(Log.user_id == user_id)

    p = q.order_by(Log.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)
    items = []
    for log in p.items:
        d = log.to_dict()
        if log.user_id:
            u = db.session.get(User, log.user_id)
            d["user_name"] = (u.full_name or u.display_name) if u else "System"
        items.append(d)
    return jsonify({
        "items":    items,
        "total":    p.total,
        "page":     p.page,
        "pages":    p.pages,
        "per_page": p.per_page,
    }), 200


# Register extended admin panel routes (audit logs, analytics, roles, export)
import routes.admin_panel_routes  # noqa: F401,E402
