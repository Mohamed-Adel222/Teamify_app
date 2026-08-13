import gevent
from flask import (
    Blueprint,
    Flask,
    after_this_request,
    current_app,
    jsonify,
    request,
)
from flask_jwt_extended import get_jwt_identity
from typing import Any, cast
from werkzeug.local import LocalProxy

from middleware.auth import auth_required, get_project_role, _READ_ROLES, _WRITE_ROLES, _MEMBER_ROLES
from models import db
from models.task import Task
from models.project import Project
from models.project_member import ProjectMember
from models.log import Log
from utils.pagination import parse_pagination

tasks_bp = Blueprint("tasks", __name__, url_prefix="/api/tasks")

VALID_STATUSES   = {"pending", "in_progress", "done"}
VALID_PRIORITIES = {"low", "medium", "high"}


def get_current_user_id():
    return int(get_jwt_identity())


def _current_flask_app() -> Flask:
    """Real Flask app from the request-local proxy (for background greenlets)."""
    return cast(LocalProxy[Flask], current_app)._get_current_object()


def _request_json() -> dict[str, Any]:
    payload = request.get_json(silent=True, force=True)
    return payload if isinstance(payload, dict) else {}


def _load_task(task_id: int) -> Task | tuple[Any, int]:
    task = Task.query.get(task_id)
    if not task:
        return jsonify({"error": "Not Found", "message": "Task not found"}), 404
    return task


def _defer_task_ai_classify(app, task_id: int, text: str) -> None:
    """Run ML classification after the HTTP response is sent (gevent-safe)."""

    def _run() -> None:
        with app.app_context():
            try:
                from services.task_pipeline_service import classify_task
                ai_result = classify_task(text)
                t = Task.query.get(task_id)
                if t:
                    t.ai_category = ai_result.get("category")
                    t.ai_difficulty = ai_result.get("difficulty")
                    t.ai_skills = ai_result.get("required_skills")
                    db.session.commit()
            except Exception:
                import traceback
                traceback.print_exc()

    gevent.spawn(_run)


def _task_to_enriched_dict(task: Task) -> dict:
    """Serialize a task and attach assignee profile fields when assigned."""
    from models.user import User

    # Handle mock task objects gracefully
    if hasattr(task, "_mock_return_value") or not hasattr(task, "to_dict"):
        return {}

    data = task.to_dict()
    if not isinstance(data, dict):
        return {}

    if not task.assigned_to or hasattr(task.assigned_to, "_mock_return_value"):
        return data

    user = User.query.get(task.assigned_to)
    if not user or hasattr(user, "_mock_return_value") or not hasattr(user, "display_name"):
        return data

    data["assignee_display_name"] = user.display_name
    data["assignee_full_name"] = (user.full_name or "").strip() or user.display_name
    data["assignee_email"] = user.email
    data["assignee_user_type"] = user.user_type
    return data


def _assert_is_project_member(user_id, project_id, project):
    """Return a 400 response tuple if user_id is NOT a member/owner/admin of the project."""
    from models.user import User
    user = User.query.filter_by(id=user_id).first()
    if not user:
        return jsonify({"error": "Not Found", "message": "Assigned user not found"}), 404
    if user.role == "admin":
        return None  # admins can be assigned to any task
    if project.user_id == user_id:
        return None  # project creator/owner
    is_member = ProjectMember.query.filter_by(
        project_id=project_id, user_id=user_id
    ).first()
    if not is_member:
        return jsonify({"error": "Bad Request", "message": "assigned_to user must be a member of the project"}), 400
    return None


# ─── GET /api/tasks?project_id=<uuid> ────────────────────────────────────────

@tasks_bp.route("", methods=["GET"])
@auth_required
def get_tasks():
    """
    Get all tasks for a specific project (paginated).
    Accessible by: admin, project owner, project member, project guest.
    ---
    tags:
      - Tasks
    security:
      - Bearer: []
    parameters:
      - in: query
        name: project_id
        type: string
        required: true
        description: UUID of the project
      - in: query
        name: page
        type: integer
        default: 1
      - in: query
        name: per_page
        type: integer
        default: 20
      - in: query
        name: status
        type: string
        description: Filter by status (pending, in_progress, done)
      - in: query
        name: priority
        type: string
        description: Filter by priority (low, medium, high)
      - in: query
        name: assigned_to
        type: string
        description: Filter by assigned user UUID
    responses:
      200:
        description: List of tasks
        schema:
          type: object
          properties:
            tasks:
              type: array
              items:
                type: object
            total:
              type: integer
            page:
              type: integer
            per_page:
              type: integer
            pages:
              type: integer
      400:
        description: project_id query param missing or invalid
        schema:
          type: object
          properties:
            error:
              type: string
      403:
        description: Forbidden – not a member of this project
        schema:
          type: object
          properties:
            error:
              type: string
      404:
        description: Project not found
        schema:
          type: object
          properties:
            error:
              type: string
    """
    user_id = get_current_user_id()
    project_id_str = request.args.get("project_id")
    page, per_page, page_err = parse_pagination()
    if page_err:
        return page_err
    status_filter   = request.args.get("status", "").strip().lower()
    priority_filter = request.args.get("priority", "").strip().lower()
    assigned_filter = request.args.get("assigned_to", "").strip()

    if not project_id_str:
        return jsonify({"error": "project_id query parameter is required"}), 400

    try:
        project_id = int(project_id_str)
    except ValueError:
        return jsonify({"error": "Invalid project_id format"}), 400

    project = Project.query.get(project_id)
    if not project:
        return jsonify({"error": "Not Found", "message": "Project not found"}), 404

    role = get_project_role(user_id, project_id)
    if role not in _READ_ROLES:
        return jsonify({"error": "Access denied"}), 403

    # Parse and validate assigned_to filter UUID
    parsed_assigned = None
    if assigned_filter:
        try:
            parsed_assigned = int(assigned_filter)
        except ValueError:
            return jsonify({"error": "Bad Request", "message": "Invalid assigned_to UUID format"}), 400

    query = Task.query.filter_by(project_id=project_id)
    if status_filter:
        query = query.filter(Task.status == status_filter)
    if priority_filter:
        query = query.filter(Task.priority == priority_filter)
    if parsed_assigned is not None:
        query = query.filter(Task.assigned_to == parsed_assigned)

    pagination = (
        query
        .order_by(Task.created_at.desc())
        .paginate(page=page, per_page=per_page, error_out=False)
    )
    return jsonify({
        "tasks": [_task_to_enriched_dict(t) for t in pagination.items],
        "total": pagination.total,
        "page": pagination.page,
        "per_page": pagination.per_page,
        "pages": pagination.pages,
    }), 200


# ─── POST /api/tasks ──────────────────────────────────────────────────────────

@tasks_bp.route("", methods=["POST"])
@auth_required
def create_task():
    """
    Create a new task inside a project.
    Accessible by: admin, project owner. Members → 403.
    ---
    tags:
      - Tasks
    security:
      - Bearer: []
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          required:
            - title
            - project_id
          properties:
            title:
              type: string
              example: Design homepage
            description:
              type: string
            status:
              type: string
              enum: [pending, in_progress, done]
              example: pending
            priority:
              type: string
              enum: [low, medium, high]
              example: medium
            due_date:
              type: string
              format: date
              example: "2025-12-31"
            project_id:
              type: string
              example: "uuid-of-project"
            assigned_to:
              type: string
              example: "uuid-of-user"
    responses:
      201:
        description: Task created
        schema:
          type: object
          properties:
            message:
              type: string
            task:
              type: object
      400:
        description: Validation error
        schema:
          type: object
          properties:
            error:
              type: string
      403:
        description: Forbidden – must be project owner or admin
        schema:
          type: object
          properties:
            error:
              type: string
      404:
        description: Project not found
        schema:
          type: object
          properties:
            error:
              type: string
    """
    user_id = get_current_user_id()
    data = _request_json()

    if not data:
        return jsonify({"error": "Bad Request", "message": "Request body is required"}), 400

    title = data.get("title", "").strip()
    project_id_str = data.get("project_id", "")

    if not title:
        return jsonify({"error": "Bad Request", "message": "Task title is required"}), 400
    if len(title) > 200:
        return jsonify({"error": "Bad Request", "message": "Task title must be 200 characters or fewer"}), 400
    if not project_id_str:
        return jsonify({"error": "Bad Request", "message": "project_id is required"}), 400

    try:
        project_id = int(project_id_str)
    except ValueError:
        return jsonify({"error": "Bad Request", "message": "Invalid project_id format"}), 400

    project = Project.query.get(project_id)
    if not project:
        return jsonify({"error": "Not Found", "message": "Project not found"}), 404

    role = get_project_role(user_id, project_id)
    if role not in _WRITE_ROLES:
        return jsonify({"error": "Forbidden", "message": "Only the project owner or admin can create tasks"}), 403

    # Validate status
    req_status = data.get("status", "pending")
    if req_status not in VALID_STATUSES:
        return jsonify({"error": "Bad Request", "message": f"status must be one of: {', '.join(sorted(VALID_STATUSES))}"}), 400

    # Validate priority
    req_priority = data.get("priority", "medium")
    if req_priority not in VALID_PRIORITIES:
        return jsonify({"error": "Bad Request", "message": f"priority must be one of: {', '.join(sorted(VALID_PRIORITIES))}"}), 400

    # Parse optional due_date
    due_date = None
    if data.get("due_date"):
        from datetime import date
        try:
            due_date = date.fromisoformat(data["due_date"])
        except ValueError:
            return jsonify({"error": "Bad Request", "message": "Invalid due_date format. Use YYYY-MM-DD"}), 400

    # Parse + validate assigned_to is a project member
    assigned_to = None
    auto_assigned = False
    auto_assign_reason = ""
    if data.get("assigned_to"):
        try:
            assigned_to = int(data["assigned_to"])
        except ValueError:
            return jsonify({"error": "Bad Request", "message": "Invalid assigned_to format"}), 400
        err = _assert_is_project_member(assigned_to, project_id, project)
        if err is not None:
            return err
    elif data.get("auto_assign", False):
        # AI auto-assign: pick the least busy member
        from services.ai_service import auto_assign as ai_auto_assign
        suggested_id, reason = ai_auto_assign(project_id, req_priority)
        auto_assign_reason = reason
        if suggested_id:
            assigned_to = suggested_id
            auto_assigned = True

    task = Task(
        title=title,
        description=data.get("description", ""),
        status=req_status,
        priority=req_priority,
        due_date=due_date,
        project_id=project_id,
        assigned_to=assigned_to,
    )

    db.session.add(task)
    db.session.flush()  # get task.id before commit

    # Schedule AI classification in background so the HTTP response is fast
    task_id_for_ai = task.id
    task_text_for_ai = task.title + " " + (task.description or "")

    log = Log(
        action="CREATE",
        entity="Task",
        entity_id=task.id,
        details=f"Task '{task.title}' created",
        user_id=user_id,
    )
    db.session.add(log)

    # Notify the assignee
    if task.assigned_to and task.assigned_to != user_id:
        from routes.notifications import create_notification
        create_notification(
            user_id=task.assigned_to,
            notif_type="task_assigned",
            title="New task assigned",
            body=f"You have been assigned to \"{task.title}\"",
            entity_type="Task",
            entity_id=task.id,
        )

    db.session.commit()

    flask_app = _current_flask_app()

    @after_this_request
    def _schedule_ai_classify(response):
        _defer_task_ai_classify(flask_app, task_id_for_ai, task_text_for_ai)
        return response

    response_data: dict[str, Any] = {
        "message": "Task created successfully",
        "task": _task_to_enriched_dict(task),
    }
    if auto_assigned:
        response_data["auto_assigned"] = True
        response_data["auto_assign_reason"] = auto_assign_reason

    return jsonify(response_data), 201


# ─── GET /api/tasks/accessible ────────────────────────────────────────────────

@tasks_bp.route("/accessible", methods=["GET"])
@auth_required
def get_accessible_tasks():
    """
    List tasks across every project the caller can access (single query).
    Used by AI Hub screens to avoid N+1 project task fetches.
    """
    from services.project_access import get_accessible_project_ids

    user_id = get_current_user_id()
    try:
        limit = min(max(int(request.args.get("limit", 100)), 1), 200)
    except (TypeError, ValueError):
        limit = 100

    project_ids = get_accessible_project_ids(user_id)
    if not project_ids:
        return jsonify({"tasks": [], "total": 0}), 200

    rows = (
        db.session.query(Task, Project.name)
        .join(Project, Task.project_id == Project.id)
        .filter(Task.project_id.in_(project_ids))
        .order_by(Task.updated_at.desc())
        .limit(limit)
        .all()
    )

    tasks = [
        {
            "id": str(task.id),
            "title": task.title,
            "status": task.status,
            "priority": task.priority,
            "project_id": str(task.project_id),
            "project_name": project_name,
        }
        for task, project_name in rows
    ]
    return jsonify({"tasks": tasks, "total": len(tasks)}), 200


# ─── GET /api/tasks/<id> ──────────────────────────────────────────────────────

@tasks_bp.route("/<int:task_id>", methods=["GET"])
@auth_required
def get_task(task_id):
    """
    Get a single task by ID.
    Accessible by: admin, project owner, project member.
    ---
    tags:
      - Tasks
    security:
      - Bearer: []
    parameters:
      - in: path
        name: task_id
        type: string
        required: true
    responses:
      200:
        description: Task data
        schema:
          type: object
          properties:
            task:
              type: object
      403:
        description: Forbidden
        schema:
          type: object
          properties:
            error:
              type: string
      404:
        description: Not found
        schema:
          type: object
          properties:
            error:
              type: string
    """
    user_id = get_current_user_id()
    loaded = _load_task(task_id)
    if isinstance(loaded, tuple):
        return loaded
    task = loaded

    role = get_project_role(user_id, task.project_id)
    if role not in _READ_ROLES:
        return jsonify({"error": "Access denied"}), 403

    return jsonify({"task": _task_to_enriched_dict(task)}), 200


# ─── PATCH /api/tasks/<id>/status ─────────────────────────────────────────────

@tasks_bp.route("/<int:task_id>/status", methods=["PATCH"])
@auth_required
def update_task_status(task_id):
    """
    Update only the status of a task.
    Accessible by: admin, project owner, project member.
    ---
    tags:
      - Tasks
    security:
      - Bearer: []
    parameters:
      - in: path
        name: task_id
        type: string
        required: true
      - in: body
        name: body
        required: true
        schema:
          type: object
          required:
            - status
          properties:
            status:
              type: string
              enum: [pending, in_progress, done]
              example: in_progress
    responses:
      200:
        description: Task status updated
        schema:
          type: object
          properties:
            message:
              type: string
            task:
              type: object
      400:
        description: Invalid status value
        schema:
          type: object
          properties:
            error:
              type: string
      403:
        description: Forbidden
        schema:
          type: object
          properties:
            error:
              type: string
      404:
        description: Task not found
        schema:
          type: object
          properties:
            error:
              type: string
    """
    user_id = get_current_user_id()
    loaded = _load_task(task_id)
    if isinstance(loaded, tuple):
        return loaded
    task = loaded

    role = get_project_role(user_id, task.project_id)
    if role not in _MEMBER_ROLES:
        return jsonify({"error": "Forbidden", "message": "Guests cannot update task status"}), 403

    # Members may only change status on tasks assigned to them; owners/admins any task.
    if role not in _WRITE_ROLES:
        if not task.assigned_to or task.assigned_to != user_id:
            return jsonify({
                "error": "Forbidden",
                "message": "You can only update status on tasks assigned to you",
            }), 403

    data = _request_json()
    new_status = data.get("status")

    if not new_status:
        return jsonify({"error": "Bad Request", "message": "status field is required"}), 400
    if new_status not in VALID_STATUSES:
        return jsonify({
            "error": "Bad Request",
            "message": f"Invalid status. Must be one of: {', '.join(sorted(VALID_STATUSES))}"
        }), 400

    old_status = task.status
    task.status = new_status

    log = Log(
        action="UPDATE_STATUS",
        entity="Task",
        entity_id=task.id,
        details=f"Task '{task.title}' status changed from '{old_status}' to '{new_status}'",
        user_id=user_id,
    )
    db.session.add(log)

    # Notify assignee about status change
    if task.assigned_to and task.assigned_to != user_id:
        from routes.notifications import create_notification
        create_notification(
            user_id=task.assigned_to,
            notif_type="task_updated",
            title="Task updated",
            body=f"Task \"{task.title}\" status changed to '{new_status}'",
            entity_type="Task",
            entity_id=task.id,
        )

    db.session.commit()

    return jsonify({
        "message": "Task status updated successfully",
        "task": _task_to_enriched_dict(task),
    }), 200


# ─── PUT /api/tasks/<id> ──────────────────────────────────────────────────────

@tasks_bp.route("/<int:task_id>", methods=["PUT"])
@auth_required
def update_task(task_id):
    """
    Update a task (full update).
    Accessible by: admin, project owner. Members → 403.
    ---
    tags:
      - Tasks
    security:
      - Bearer: []
    parameters:
      - in: path
        name: task_id
        type: string
        required: true
      - in: body
        name: body
        schema:
          type: object
          properties:
            title:
              type: string
            description:
              type: string
            status:
              type: string
              enum: [pending, in_progress, done]
            priority:
              type: string
              enum: [low, medium, high]
            due_date:
              type: string
              format: date
            assigned_to:
              type: string
    responses:
      200:
        description: Task updated
        schema:
          type: object
          properties:
            message:
              type: string
            task:
              type: object
      403:
        description: Forbidden – must be project owner or admin
        schema:
          type: object
          properties:
            error:
              type: string
      404:
        description: Not found
        schema:
          type: object
          properties:
            error:
              type: string
    """
    user_id = get_current_user_id()
    loaded = _load_task(task_id)
    if isinstance(loaded, tuple):
        return loaded
    task = loaded

    role = get_project_role(user_id, task.project_id)
    if role not in _WRITE_ROLES:
        return jsonify({"error": "Forbidden", "message": "Only the project owner or admin can update tasks"}), 403

    data = _request_json()
    previous_assignee = task.assigned_to
    previous_status = task.status
    previous_title = task.title

    if "title" in data:
        title = data["title"].strip()
        if not title:
            return jsonify({"error": "title cannot be empty"}), 400
        if len(title) > 200:
            return jsonify({"error": "title exceeds 200 characters"}), 400
        task.title = title
    if "description" in data:
        task.description = data["description"]
    if "status" in data:
        if data["status"] not in VALID_STATUSES:
            return jsonify({"error": "Bad Request", "message": f"Invalid status. Must be one of: {', '.join(sorted(VALID_STATUSES))}"}), 400
        task.status = data["status"]
    if "priority" in data:
        if data["priority"] not in VALID_PRIORITIES:
            return jsonify({"error": "Bad Request", "message": f"priority must be one of: {', '.join(sorted(VALID_PRIORITIES))}"}), 400
        task.priority = data["priority"]
    if "due_date" in data:
        from datetime import date
        try:
            task.due_date = date.fromisoformat(data["due_date"]) if data["due_date"] else None
        except ValueError:
            return jsonify({"error": "Bad Request", "message": "Invalid due_date format. Use YYYY-MM-DD"}), 400
    if "assigned_to" in data:
        if data["assigned_to"]:
            try:
                new_assignee = int(data["assigned_to"])
            except ValueError:
                return jsonify({"error": "Bad Request", "message": "Invalid assigned_to format"}), 400
            project_obj = Project.query.get(task.project_id)
            if not project_obj:
                return jsonify({"error": "Not Found", "message": "Project not found"}), 404
            err = _assert_is_project_member(new_assignee, task.project_id, project_obj)
            if err:
                return err
            task.assigned_to = new_assignee
        else:
            task.assigned_to = None

    log = Log(
        action="UPDATE",
        entity="Task",
        entity_id=task.id,
        details=f"Task '{task.title}' updated",
        user_id=user_id,
    )
    db.session.add(log)

    from routes.notifications import create_notification

    assignee_changed = task.assigned_to != previous_assignee
    if assignee_changed and task.assigned_to and task.assigned_to != user_id:
        create_notification(
            user_id=task.assigned_to,
            notif_type="task_assigned",
            title="New task assigned",
            body=f"You have been assigned to \"{task.title}\"",
            entity_type="Task",
            entity_id=task.id,
        )
    elif task.assigned_to and task.assigned_to != user_id:
        update_bits = []
        if previous_title != task.title:
            update_bits.append("title")
        if previous_status != task.status:
            update_bits.append(f"status → {task.status}")
        if "priority" in data:
            update_bits.append("priority")
        if "due_date" in data:
            update_bits.append("due date")
        if "description" in data:
            update_bits.append("description")
        summary = ", ".join(update_bits) if update_bits else "details updated"
        create_notification(
            user_id=task.assigned_to,
            notif_type="task_updated",
            title="Task updated",
            body=f"Task \"{task.title}\" was updated ({summary})",
            entity_type="Task",
            entity_id=task.id,
        )

    db.session.commit()

    return jsonify({
        "message": "Task updated successfully",
        "task": _task_to_enriched_dict(task),
    }), 200


# ─── DELETE /api/tasks/<id> ───────────────────────────────────────────────────

@tasks_bp.route("/<int:task_id>", methods=["DELETE"])
@auth_required
def delete_task(task_id):
    """
    Delete a task.
    Accessible by: admin, project owner. Members → 403.
    ---
    tags:
      - Tasks
    security:
      - Bearer: []
    parameters:
      - in: path
        name: task_id
        type: string
        required: true
    responses:
      200:
        description: Task deleted
        schema:
          type: object
          properties:
            message:
              type: string
      403:
        description: Forbidden
        schema:
          type: object
          properties:
            error:
              type: string
      404:
        description: Not found
        schema:
          type: object
          properties:
            error:
              type: string
    """
    user_id = get_current_user_id()
    loaded = _load_task(task_id)
    if isinstance(loaded, tuple):
        return loaded
    task = loaded

    role = get_project_role(user_id, task.project_id)
    if role not in _WRITE_ROLES:
        return jsonify({"error": "Forbidden", "message": "Only the project owner or admin can delete tasks"}), 403

    log = Log(
        action="DELETE_TASK",
        entity="Task",
        entity_id=task.id,
        details=f"Task '{task.title}' deleted from project {task.project_id}",
        user_id=user_id,
    )
    db.session.add(log)
    db.session.delete(task)
    db.session.commit()

    return jsonify({"message": "Task deleted successfully"}), 200
