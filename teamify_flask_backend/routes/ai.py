"""
AI Routes — Flask Blueprint
Endpoints:
  GET  /api/ai/predict-delay/<task_id>
  POST /api/ai/classify-task
  POST /api/ai/assign-members
  POST /api/ai/summarize-chat
  POST /api/ai/transcribe
  GET  /api/ai/mentor-report/<user_id>
  GET  /api/ai/predict-rating/<user_id>
  POST /api/ai/recommend-teammates
  GET  /api/ai/mentor/insights/<user_id>   — Flutter AI Hub (single ML run)
  GET  /api/ai/mentor/analyse/<user_id>
  GET  /api/ai/mentor/performance/<user_id>
  GET  /api/ai/mentor/courses/<user_id>
  GET  /api/ai/mentor/chat/history
  POST /api/ai/mentor/chat
"""
import os
import logging
import time
from typing import Any, cast

import requests
from flask import Blueprint, request, jsonify, current_app, g
from flask_jwt_extended import get_jwt_identity
from middleware.auth import auth_required

from services.task_pipeline_service import classify_task, assign_best_members
from services.chat_summarization_service import summarize_chat
from services.ai_mentor_service import (
    generate_mentor_report,
    get_db_performance_snapshot,
    generate_feedback_draft,
)
from services.profile_rating_service import predict_user_rating, recommend_teammates
from services.anomaly_service_ml import detect_anomaly
from services.cv_builder_service import build_cv_for_user, persist_cv_from_ai_build
from services.ai_service import (
    auto_assign,
    suggest_priority,
    suggest_deadline,
    predict_delay,
    calculate_workload,
)

# Models and auth — imported at module level so @patch("routes.ai.X") works in tests
from models.project import Project
from models.project_member import ProjectMember
from models.task import Task
from models.user import User
from models import db
from middleware.auth import get_project_role, _WRITE_ROLES

# Marshmallow validation (reused from existing validators)
from marshmallow import Schema, fields, validates, ValidationError
from validators.cv_validator import cv_build_schema

logger = logging.getLogger(__name__)
ai_bp = Blueprint("ai", __name__, url_prefix="/api/ai")


@ai_bp.before_request
def _ai_before_request():
    if request.method == "OPTIONS":
        return None
    g.ai_request_start = time.time()
    from services.system_settings_service import is_ai_enabled

    path = request.path.rstrip("/")
    if path.endswith("/models/status") or path.endswith("/delay-model/status"):
        return None

    if not is_ai_enabled():
        return jsonify({
            "error": "AI disabled",
            "message": "Platform AI features are currently disabled by the administrator.",
        }), 503


@ai_bp.after_request
def _log_ai_request(response):
    """Persist every AI API call for the admin monitor dashboard."""
    if request.method == "OPTIONS":
        return response
    try:
        user_id = None
        try:
            from flask_jwt_extended import verify_jwt_in_request, get_jwt_identity

            verify_jwt_in_request(optional=True)
            uid = get_jwt_identity()
            if uid:
                user_id = int(uid)
        except Exception:
            pass

        started = getattr(g, "ai_request_start", None)
        duration_ms = int((time.time() - started) * 1000) if started else 0
        status = "success" if response.status_code < 400 else "fail"
        body_text = response.get_data(as_text=True) or ""
        token_usage = max(1, len(body_text) // 4) if body_text else 0

        from services.audit_log_service import log_ai_event

        log_ai_event(
            "AI_REQUEST",
            user_id=user_id,
            ip=request.remote_addr or "unknown",
            severity="INFO" if status == "success" else "WARNING",
            details={
                "endpoint": request.path,
                "method": request.method,
                "status": status,
                "status_code": response.status_code,
                "latency_ms": duration_ms,
                "token_usage": token_usage,
            },
        )
    except Exception:
        logger.debug("AI request audit skipped", exc_info=True)
    return response

_RECOMMEND_CACHE: dict[int, tuple[float, dict]] = {}
_RECOMMEND_TTL_SECONDS = 300


def _cache_get(cache: dict, key: int, ttl: float):
    entry = cache.get(key)
    if entry and (time.time() - entry[0]) < ttl:
        return entry[1]
    return None


def _cache_set(cache: dict, key: int, value: dict) -> None:
    cache[key] = (time.time(), value)


# ─── Predict Task Delay ───────────────────────────────────────────────────────

@ai_bp.route("/predict-delay/<int:task_id>", methods=["GET"])
@auth_required
def api_predict_delay(task_id):
    """
    Predict if a specific task will be delayed.
    ---
    tags:
      - AI
    security:
      - Bearer: []
    parameters:
      - in: path
        name: task_id
        type: integer
        required: true
    responses:
      200:
        description: Delay prediction result
      404:
        description: Task not found
    """
    from models.task import Task
    from models.user import User
    from models import db

    user_id = int(get_jwt_identity())
    task = db.session.get(Task, task_id)
    if not task:
        return jsonify({"error": "Task not found"}), 404

    from middleware.auth import get_project_role, _READ_ROLES

    role = get_project_role(user_id, task.project_id)
    if role not in _READ_ROLES:
        return jsonify({
            "error": "Forbidden",
            "message": "You do not have access to this task",
        }), 403

    from services.ai_service import predict_delay as predict_delay_service

    result = predict_delay_service(task_id=task_id)
    if result.get("error"):
        return jsonify({"error": result["error"]}), 404

    return jsonify(result), 200


# ─── Classify Task ────────────────────────────────────────────────────────────

@ai_bp.route("/classify-task", methods=["POST"])
@auth_required
def api_classify_task():
    """
    Classify a task by text → category, difficulty, required skills.
    ---
    tags:
      - AI
    security:
      - Bearer: []
    parameters:
      - in: body
        name: body
        schema:
          type: object
          required: [text]
          properties:
            text:
              type: string
    responses:
      200:
        description: Classification result
      400:
        description: Missing text
    """
    data = request.get_json(silent=True) or {}
    text = data.get("text", "").strip()
    if not text:
        return jsonify({"error": "text field is required"}), 400

    try:
        result = classify_task(text)
    except Exception as exc:
        logger.exception("classify-task failed")
        from services.task_pipeline_service import _keyword_classify

        result = _keyword_classify(text)
        result["error"] = str(exc)

    category = result.get("category") or "general"
    difficulty = result.get("difficulty") or result.get("complexity") or "medium"
    suggested = {
        "backend": "Backend specialist",
        "frontend": "Frontend specialist",
        "mobile": "Mobile developer",
        "data_science": "Data / ML engineer",
        "devops": "DevOps engineer",
        "security": "Security engineer",
        "testing": "QA engineer",
        "ui_ux": "UI/UX designer",
        "project_management": "Project lead",
        "cloud": "Cloud engineer",
        "database": "Database engineer",
        "ai_ml": "AI/ML engineer",
    }.get(str(category).lower(), "Best matching teammate")

    payload = {
        **result,
        "complexity": result.get("complexity") or difficulty,
        "difficulty": difficulty,
        "confidence": result.get(
            "confidence",
            0.92 if result.get("source") == "ml_model" else 0.72,
        ),
        "suggested_assignee": suggested,
    }
    return jsonify(payload), 200


# ─── Feedback assist ─────────────────────────────────────────────────────────

@ai_bp.route("/feedback-assist", methods=["POST"])
@auth_required
def api_feedback_assist():
    """Generate a draft peer-feedback comment from rating and context."""
    data = request.get_json(silent=True) or {}
    try:
        rating = int(data.get("rating", 0))
    except (TypeError, ValueError):
        return jsonify({"error": "rating must be an integer between 1 and 5"}), 400
    if not 1 <= rating <= 5:
        return jsonify({"error": "rating must be between 1 and 5"}), 400

    result = generate_feedback_draft(
        rating=rating,
        teammate_name=(data.get("teammate_name") or data.get("member_name") or "").strip(),
        project_name=(data.get("project_name") or "").strip(),
    )
    return jsonify(result), 200


# ─── Assign Members ───────────────────────────────────────────────────────────

@ai_bp.route("/assign-members", methods=["POST"])
@auth_required
def api_assign_members():
    """
    Rank members for a task using domain matching and workload score.
    ---
    tags:
      - AI
    security:
      - Bearer: []
    parameters:
      - in: body
        name: body
        schema:
          type: object
          properties:
            task_info:
              type: object
            members:
              type: array
    responses:
      200:
        description: Ranked member assignments
    """
    data = request.get_json(silent=True) or {}
    task_info = data.get("task_info", {})
    project_id = data.get("project_id")

    if not project_id:
        return jsonify({"error": "project_id is required"}), 400

    try:
        project_id_int = int(project_id)
    except (TypeError, ValueError):
        return jsonify({"error": "project_id must be an integer"}), 400

    current_user_id = int(get_jwt_identity())
    role = get_project_role(current_user_id, project_id_int)
    if role not in _WRITE_ROLES:
        return jsonify({
            "error": "Forbidden",
            "message": "Only project owners can rank members for assignment",
        }), 403

    project = db.session.get(Project, project_id_int)
    if not project:
        return jsonify({"error": "Project not found"}), 404

    member_ids = {project.user_id}
    for pm in ProjectMember.query.filter_by(project_id=project_id_int).all():
        member_ids.add(pm.user_id)

    from services.ai_service import get_user_workload

    members_list = []
    for uid in member_ids:
        member = db.session.get(User, uid)
        if not member:
            continue
        active = get_user_workload(uid)
        max_allowed = member.max_allowed_tasks or 5
        members_list.append({
            "id": uid,
            "user_id": uid,
            "member_name": member.display_name,
            "member_primary_domain": (
                getattr(member, "professional_field", None)
                or getattr(member, "member_primary_domain", "")
                or ""
            ),
            "member_skills": member.skills or [],
            "current_tasks": active,
            "workload_score": 1.0 - min(active / max(max_allowed, 1), 1.0),
            "availability_encoded": 1 if active < max_allowed else 0,
            "rating": (member.member_on_time_rate or 0.75) * 5,
        })

    assignments = assign_best_members(task_info, members_list)
    return jsonify({"assignments": assignments}), 200


# ─── Summarize Chat ───────────────────────────────────────────────────────────

@ai_bp.route("/summarize-chat", methods=["POST"])
@auth_required
def api_summarize_chat():
    """
    Summarize a chat conversation and extract action items.
    ---
    tags:
      - AI
    security:
      - Bearer: []
    parameters:
      - in: body
        name: body
        schema:
          type: object
          required: [chat_text]
          properties:
            chat_text:
              type: string
    responses:
      200:
        description: Chat summary
      400:
        description: Missing chat_text
    """
    data = request.get_json(silent=True) or {}
    chat_text = data.get("chat_text", "").strip()
    if not chat_text:
        return jsonify({"error": "chat_text is required"}), 400

    result = summarize_chat(chat_text)
    return jsonify(result), 200


# ─── Transcribe Audio (proxy to FastAPI STT) ──────────────────────────────────

@ai_bp.route("/transcribe", methods=["POST"])
@auth_required
def api_transcribe():
    """
    Forward an audio file to the Speech-to-Text microservice.
    ---
    tags:
      - AI
    security:
      - Bearer: []
    consumes:
      - multipart/form-data
    parameters:
      - in: formData
        name: audio
        type: file
        required: true
    responses:
      200:
        description: Transcribed text
      400:
        description: No audio file provided
      502:
        description: STT service unavailable
    """
    audio_file = request.files.get("audio") or request.files.get("file")
    if not audio_file:
        return jsonify({"error": "No audio file provided"}), 400

    language = request.args.get("language", "en")
    task = request.args.get("task", "transcribe")
    stt_base = os.getenv("STT_SERVICE_URL", "http://localhost:8000").rstrip("/")
    stt_url = f"{stt_base}/transcribe"
    filename = audio_file.filename or "audio.wav"
    mimetype = audio_file.mimetype or "application/octet-stream"
    if filename.endswith(".webm") and mimetype == "application/octet-stream":
        mimetype = "audio/webm"
    audio_bytes = audio_file.read()
    if not audio_bytes:
        return jsonify({"error": "Empty audio file"}), 400
    try:
        resp = requests.post(
            stt_url,
            files={"file": (filename, audio_bytes, mimetype)},
            params={"language": language, "task": task},
            timeout=120,
        )
        try:
            body = resp.json()
        except Exception:
            body = {"error": resp.text or "STT returned non-JSON response"}
        if resp.status_code >= 400:
            return jsonify(body), resp.status_code
        return jsonify(body), 200
    except requests.exceptions.ConnectionError:
        return jsonify({
            "error": "STT microservice is not running",
            "hint": "Start Whisper STT: cd teamify_flask_backend/ml_models && uvicorn run:app --host 127.0.0.1 --port 8000",
            "success": False,
        }), 502
    except requests.exceptions.Timeout:
        return jsonify({"error": "STT service timed out"}), 504
    except Exception as exc:
        logger.error(f"[AI/transcribe] Unexpected error: {exc}")
        return jsonify({"error": str(exc)}), 500


# ─── Mentor Report ────────────────────────────────────────────────────────────

@ai_bp.route("/mentor-report/<int:user_id>", methods=["GET"])
@auth_required
def api_mentor_report(user_id):
    """
    Generate an AI career progression and mentoring report for a user.
    ---
    tags:
      - AI
    security:
      - Bearer: []
    parameters:
      - in: path
        name: user_id
        type: integer
        required: true
    responses:
      200:
        description: Mentor report
    """
    from flask_jwt_extended import get_jwt_identity
    from models.user import User

    current_user_id = int(get_jwt_identity())
    current_user = db.session.get(User, current_user_id)
    if not current_user:
        return jsonify({"error": "User not found"}), 404

    if current_user.role != "admin" and current_user_id != user_id:
        return jsonify({
            "error": "Forbidden",
            "detail": "You are not authorized to view this user's mentor report",
        }), 403

    result = generate_mentor_report(user_id)
    return jsonify(result), 200


# ─── Predict User Rating ──────────────────────────────────────────────────────

@ai_bp.route("/predict-rating/<int:user_id>", methods=["GET"])
@auth_required
def api_predict_rating(user_id):
    """
    Predict a user's AI performance rating.
    ---
    tags:
      - AI
    security:
      - Bearer: []
    parameters:
      - in: path
        name: user_id
        type: integer
        required: true
    responses:
      200:
        description: Predicted rating
    """
    from models.user import User
    from services.ai_mentor_service import build_user_ml_stats

    current_user_id = int(get_jwt_identity())
    current_user = db.session.get(User, current_user_id)
    if not current_user:
        return jsonify({"error": "User not found"}), 404

    if current_user.role != "admin" and current_user_id != user_id:
        return jsonify({
            "error": "Forbidden",
            "detail": "You are not authorized to view this user's rating prediction",
        }), 403

    user = db.session.get(User, user_id)
    if not user:
        return jsonify({"error": "User not found"}), 404

    user_stats = build_user_ml_stats(user_id)
    rating_result = predict_user_rating(user_stats)
    teammates = recommend_teammates(
        user_stats,
        top_n=3,
        current_user_id=user_id,
    )

    return jsonify({
        "user_id": user_id,
        **rating_result,
        "teammate_recommendations": teammates
    }), 200


# ─── Recommend Teammates ──────────────────────────────────────────────────────

@ai_bp.route("/recommend-teammates", methods=["POST"])
@auth_required
def api_recommend_teammates():
    """
    Find the most compatible teammates based on user stats.
    ---
    tags:
      - AI
    security:
      - Bearer: []
    parameters:
      - in: body
        name: body
        schema:
          type: object
          properties:
            user_stats:
              type: object
            top_n:
              type: integer
              default: 5
    responses:
      200:
        description: Recommended teammates
    """
    data = request.get_json(silent=True) or {}
    top_n = int(data.get("top_n", 5))
    current_id = int(get_jwt_identity())

    from services.ai_mentor_service import build_user_ml_stats

    cached = _cache_get(_RECOMMEND_CACHE, current_id, _RECOMMEND_TTL_SECONDS)
    if cached is not None:
        return jsonify(cached), 200

    user_stats = build_user_ml_stats(current_id)

    teammates = recommend_teammates(
        user_stats,
        top_n=top_n,
        current_user_id=current_id,
    )
    payload = {"recommendations": teammates}
    _cache_set(_RECOMMEND_CACHE, current_id, payload)
    return jsonify(payload), 200


# ─── Detect Login Anomaly (internal) ─────────────────────────────────────────

@ai_bp.route("/detect-anomaly", methods=["POST"])
@auth_required
def api_detect_anomaly():
    """
    Run the Isolation Forest anomaly detector on a login event.
    ---
    tags:
      - AI
    security:
      - Bearer: []
    parameters:
      - in: body
        name: body
        schema:
          type: object
          properties:
            user_id:
              type: integer
            failed_attempts:
              type: integer
    responses:
      200:
        description: Anomaly detection result
    """
    data = request.get_json(silent=True) or {}
    current_user_id = int(get_jwt_identity())
    current_user = db.session.get(User, current_user_id)
    if not current_user:
        return jsonify({"error": "User not found"}), 404

    target_id = data.get("user_id")
    if target_id is not None and str(target_id) != str(current_user_id):
        if current_user.role != "admin":
            return jsonify({
                "error": "Forbidden",
                "detail": "You can only run anomaly detection for your own account",
            }), 403

    result = detect_anomaly(data)
    return jsonify(result), 200


# ─── Helper ──────────────────────────────────────────────────────────────────

def _extract_section(text: str, heading: str) -> str:
    """Extract the text body of a markdown section identified by *heading*."""
    lines = text.split("\n")
    in_section = False
    result: list = []
    for line in lines:
        if line.strip().startswith(heading):
            in_section = True
            continue
        if in_section:
            if line.strip().startswith("##"):
                break
            result.append(line)
    return "\n".join(result).strip()


# ─── POST /api/ai/assign ──────────────────────────────────────────────────────

@ai_bp.route("/assign", methods=["POST"])
@auth_required
def api_assign():
    """
    Auto-assign the best available project member for a new task.
    ---
    tags:
      - AI
    security:
      - Bearer: []
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          required: [project_id]
          properties:
            project_id:
              type: string
    responses:
      200:
        description: Suggested user
      400:
        description: Missing project_id
      403:
        description: Not a project owner or admin
      404:
        description: Project not found
    """
    current_user_id = int(get_jwt_identity())
    data = request.get_json(silent=True) or {}
    project_id = data.get("project_id")
    if not project_id:
        return jsonify({"error": "project_id is required"}), 400

    project = Project.query.get(int(project_id))
    if not project:
        return jsonify({"error": "Project not found"}), 404

    role = get_project_role(current_user_id, int(project_id))
    if role not in ("owner", "admin"):
        return jsonify({"error": "Only project owners or admins can auto-assign members"}), 403

    suggested_user_id, reason = auto_assign(int(project_id))
    return jsonify({"suggested_user_id": suggested_user_id, "reason": reason}), 200


# ─── POST /api/ai/suggest-priority ───────────────────────────────────────────

@ai_bp.route("/suggest-priority", methods=["POST"])
@auth_required
def api_suggest_priority():
    """
    Suggest a task priority based on project context and keywords.
    ---
    tags:
      - AI
    security:
      - Bearer: []
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          required: [project_id]
          properties:
            project_id:
              type: string
            title:
              type: string
            description:
              type: string
            due_date:
              type: string
    responses:
      200:
        description: Suggested priority and reasons
      400:
        description: Missing project_id
      403:
        description: Not a project member
    """
    current_user_id = int(get_jwt_identity())
    data = request.get_json(silent=True) or {}
    project_id = data.get("project_id")
    if not project_id:
        return jsonify({"error": "project_id is required"}), 400

    role = get_project_role(current_user_id, int(project_id))
    if not role:
        return jsonify({"error": "Not a project member"}), 403

    priority_val, reasons = suggest_priority(
        int(project_id),
        title=data.get("title", ""),
        description=data.get("description", ""),
        due_date_str=data.get("due_date"),
    )
    return jsonify({"priority": priority_val, "reasons": reasons}), 200


# ─── POST /api/ai/suggest-deadline ───────────────────────────────────────────

@ai_bp.route("/suggest-deadline", methods=["POST"])
@auth_required
def api_suggest_deadline():
    """
    Suggest a task deadline based on priority and project history.
    ---
    tags:
      - AI
    security:
      - Bearer: []
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          required: [project_id]
          properties:
            project_id:
              type: string
            priority:
              type: string
            title:
              type: string
            description:
              type: string
    responses:
      200:
        description: Suggested deadline date and reasons
      400:
        description: Missing project_id
      403:
        description: Not a project member
    """
    current_user_id = int(get_jwt_identity())
    data = request.get_json(silent=True) or {}
    project_id = data.get("project_id")
    if not project_id:
        return jsonify({"error": "project_id is required"}), 400

    role = get_project_role(current_user_id, int(project_id))
    if not role:
        return jsonify({"error": "Not a project member"}), 403

    suggested_date, reasons = suggest_deadline(
        int(project_id),
        priority=data.get("priority", "medium"),
        title=data.get("title", ""),
        description=data.get("description", ""),
    )
    return jsonify({"suggested_date": suggested_date, "reasons": reasons}), 200


# ─── POST /api/ai/delay ───────────────────────────────────────────────────────

@ai_bp.route("/delay", methods=["POST"])
@auth_required
def api_delay():
    """
    Predict delay risk for a task or an entire project.
    ---
    tags:
      - AI
    security:
      - Bearer: []
    parameters:
      - in: body
        name: body
        schema:
          type: object
          properties:
            task_id:
              type: string
            project_id:
              type: string
    responses:
      200:
        description: Delay risk result
      400:
        description: Missing task_id and project_id
      403:
        description: Not a project member
      404:
        description: Task not found
    """
    current_user_id = int(get_jwt_identity())
    data = request.get_json(silent=True) or {}
    task_id = data.get("task_id")
    project_id = data.get("project_id")

    if not task_id and not project_id:
        return jsonify({"error": "task_id or project_id is required"}), 400

    if task_id:
        task = Task.query.get(int(task_id))
        if not task:
            return jsonify({"error": "Task not found"}), 404
        role = get_project_role(current_user_id, task.project_id)
        if not role:
            return jsonify({"error": "Not a project member"}), 403
        result = predict_delay(task_id=int(task_id))
    else:
        if project_id is None:
            return jsonify({"error": "project_id is required"}), 400
        pid = int(project_id)
        role = get_project_role(current_user_id, pid)
        if not role:
            return jsonify({"error": "Not a project member"}), 403
        result = predict_delay(project_id=pid)

    return jsonify(result), 200


@ai_bp.route("/delay-model/status", methods=["GET"])
@auth_required
def api_delay_model_status():
    """Whether the trained Delay_Predictor.pkl model is loaded."""
    from services.delay_predictor_service import get_delay_model_status

    return jsonify(get_delay_model_status()), 200


@ai_bp.route("/models/status", methods=["GET"])
@auth_required
def api_ai_models_status():
    """Runtime report: file, dependencies, in-memory load, and inference test.

    REAL_MODEL only when load + inference succeed. Heuristic fallbacks stay
    available on the existing AI endpoints. Never includes secrets.
    """
    from services.ai_models_status_service import get_ai_models_status

    return jsonify(get_ai_models_status()), 200


# ─── GET /api/ai/workload ─────────────────────────────────────────────────────

@ai_bp.route("/workload", methods=["GET"])
@auth_required
def api_workload():
    """
    Get workload details for a user (defaults to the caller).
    Admins may query any user via ?user_id=<id>.
    ---
    tags:
      - AI
    security:
      - Bearer: []
    parameters:
      - in: query
        name: user_id
        type: integer
    responses:
      200:
        description: Workload summary
      403:
        description: Non-admin requesting another user's workload
    """
    from models.user import User
    current_user_id = int(get_jwt_identity())
    user_id = request.args.get("user_id", type=int)

    if user_id and user_id != current_user_id:
        caller = db.session.get(User, current_user_id)
        if not caller or caller.role != "admin":
            return jsonify({"error": "Forbidden"}), 403

    target_id = user_id or current_user_id
    result = calculate_workload(target_id)
    return jsonify(result), 200


# ─── GET /api/ai/mentor/recommendations/<user_id> ────────────────────────────

@ai_bp.route("/mentor/recommendations/<int:user_id>", methods=["GET"])
@auth_required
def api_mentor_recommendations(user_id: int):
    """
    Career recommendations and next steps for a user.
    Only the user themselves or an admin may access.
    ---
    tags:
      - AI
    security:
      - Bearer: []
    parameters:
      - in: path
        name: user_id
        type: integer
        required: true
    responses:
      200:
        description: Career summary, next steps, career path percentage
      403:
        description: Forbidden
      404:
        description: User not found
    """
    from models.user import User
    current_user_id = int(get_jwt_identity())
    current_user = db.session.get(User, current_user_id)
    if not current_user:
        return jsonify({"error": "User not found"}), 404
    if current_user.role != "admin" and current_user_id != user_id:
        return jsonify({"error": "Forbidden"}), 403

    report = generate_mentor_report(user_id)
    if "error" in report:
        return jsonify(report), 404

    mentor_text = report.get("mentor_report", "")
    career_summary = _extract_section(mentor_text, "## Career Summary") or mentor_text[:250]
    gaps = report.get("skill_gaps", {})

    return jsonify({
        "career_summary": career_summary,
        "next_steps": gaps.get("missing_skills", [])[:3],
        "career_path_percentage": report.get("career_progress", {}).get("score", 0),
    }), 200


# ─── GET /api/ai/mentor/performance/<user_id> ────────────────────────────────

@ai_bp.route("/mentor/performance/<int:user_id>", methods=["GET"])
@auth_required
def api_mentor_performance(user_id: int):
    """
    Performance scores and AI coaching tip for a user.
    Only the user themselves or an admin may access.
    ---
    tags:
      - AI
    security:
      - Bearer: []
    parameters:
      - in: path
        name: user_id
        type: integer
        required: true
    responses:
      200:
        description: Scores, overall rating, AI tip, trend
      403:
        description: Forbidden
      404:
        description: User not found
    """
    from models.user import User
    current_user_id = int(get_jwt_identity())
    current_user = db.session.get(User, current_user_id)
    if not current_user:
        return jsonify({"error": "User not found"}), 404
    if current_user.role != "admin" and current_user_id != user_id:
        return jsonify({"error": "Forbidden"}), 403

    try:
        report = generate_mentor_report(user_id)
    except Exception as exc:
        logger.exception("mentor performance failed for user %s", user_id)
        return jsonify({"error": "Mentor analysis failed", "detail": str(exc)}), 500

    if "error" in report:
        return jsonify(report), 404

    snapshot = get_db_performance_snapshot(user_id)
    weaknesses = report.get("weaknesses", [])
    if snapshot.get("feedback_count", 0) == 0 and snapshot.get("rating_count", 0) == 0:
        ai_tip = "No peer feedback yet — ask teammates to rate you on the Feedback tab."
    elif weaknesses:
        ai_tip = weaknesses[0]["message"]
    else:
        ai_tip = "Keep up the great work — no critical issues detected."

    history = snapshot.get("history", [])
    trend = "stable"
    if len(history) >= 2:
        trend = "up" if history[-1]["score"] > history[-2]["score"] else (
            "down" if history[-1]["score"] < history[-2]["score"] else "stable"
        )

    return jsonify({
        "scores": snapshot.get("scores", {}),
        "overall": snapshot.get("overall", 0),
        "history": history,
        "ai_tip": ai_tip,
        "trend": trend,
        "feedback_count": snapshot.get("feedback_count", 0),
        "rating_count": snapshot.get("rating_count", 0),
        "recent_feedback": snapshot.get("recent_feedback", []),
        "source": snapshot.get("source", "peer_feedback"),
    }), 200


# ─── GET /api/ai/mentor/courses/<user_id> ────────────────────────────────────

@ai_bp.route("/mentor/courses/<int:user_id>", methods=["GET"])
@auth_required
def api_mentor_courses(user_id: int):
    """
    Recommended learning courses tailored to a user's skill gaps.
    Only the user themselves or an admin may access.
    ---
    tags:
      - AI
    security:
      - Bearer: []
    parameters:
      - in: path
        name: user_id
        type: integer
        required: true
    responses:
      200:
        description: List of recommended courses
      403:
        description: Forbidden
      404:
        description: User not found
    """
    from models.user import User
    current_user_id = int(get_jwt_identity())
    current_user = db.session.get(User, current_user_id)
    if not current_user:
        return jsonify({"error": "User not found"}), 404
    if current_user.role != "admin" and current_user_id != user_id:
        return jsonify({"error": "Forbidden"}), 403

    try:
        report = generate_mentor_report(user_id)
    except Exception as exc:
        logger.exception("mentor courses failed for user %s", user_id)
        return jsonify({"error": "Mentor analysis failed", "detail": str(exc)}), 500

    if "error" in report:
        return jsonify(report), 404

    courses = report.get("top_courses", [])
    return jsonify({"recommended_courses": courses, "courses": courses}), 200


# ─── POST /api/ai/chat/summarize ─────────────────────────────────────────────

@ai_bp.route("/chat/summarize", methods=["POST"])
@auth_required
def api_chat_summarize():
    """
    Summarize a chat transcript and extract action items.
    ---
    tags:
      - AI
    security:
      - Bearer: []
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          required: [text]
          properties:
            text:
              type: string
              description: 'Raw chat/meeting transcript in "Name: message" format'
            top_n:
              type: integer
              default: 3
              description: Number of key sentences to extract
    responses:
      200:
        description: Summarized result
        schema:
          type: object
          properties:
            participants:
              type: array
              items:
                type: string
            key_points:
              type: array
              items:
                type: string
            action_items:
              type: array
              items:
                type: object
            word_count:
              type: integer
            source:
              type: string
      400:
        description: Missing or empty text
    """
    data = request.get_json(silent=True, force=True) or {}
    text = data.get("text", "").strip()
    if not text:
        # also accept legacy field name used by /summarize-chat
        text = data.get("chat_text", "").strip()
    if not text:
        return jsonify({"error": "text field is required"}), 400

    top_n = int(data.get("top_n", 3))
    result = summarize_chat(text, top_n=top_n)
    return jsonify(result), 200


# ─── GET /api/ai/mentor/insights/<user_id> (single call for Flutter hub) ─────

@ai_bp.route("/mentor/insights/<int:user_id>", methods=["GET"])
@auth_required
def api_mentor_insights(user_id: int):
    """
    One-shot mentor dashboard payload for the AI Career Mentor hub.
    Avoids three parallel /analyse + /performance + /courses calls.
    """
    from models.user import User

    current_user_id = int(get_jwt_identity())
    current_user = db.session.get(User, current_user_id)
    if not current_user:
        return jsonify({"error": "User not found"}), 404
    if current_user.role != "admin" and current_user_id != user_id:
        return jsonify({"error": "Forbidden"}), 403

    try:
        report = generate_mentor_report(user_id)
    except Exception as exc:
        logger.exception("mentor insights failed for user %s", user_id)
        return jsonify({
            "error": "Mentor analysis failed",
            "detail": str(exc),
        }), 500

    if "error" in report:
        return jsonify(report), 404

    snapshot = get_db_performance_snapshot(user_id)
    weaknesses = report.get("weaknesses") or []
    if snapshot.get("feedback_count", 0) == 0 and snapshot.get("rating_count", 0) == 0:
        ai_tip = "No peer feedback yet — ask teammates to rate you on the Feedback tab."
    elif weaknesses and isinstance(weaknesses[0], dict):
        ai_tip = weaknesses[0]["message"]
    else:
        ai_tip = "Keep up the great work — no critical issues detected."
    history = snapshot.get("history", [])
    trend = "stable"
    if len(history) >= 2:
        trend = "up" if history[-1]["score"] > history[-2]["score"] else (
            "down" if history[-1]["score"] < history[-2]["score"] else "stable"
        )

    courses = report.get("top_courses") or []
    return jsonify({
        "analysis": report,
        "profile": report.get("user_profile") or {},
        "generated_at": report.get("generated_at"),
        "performance": {
            "scores": snapshot.get("scores", {}),
            "overall": snapshot.get("overall", 0),
            "history": history,
            "ai_tip": ai_tip,
            "trend": trend,
            "feedback_count": snapshot.get("feedback_count", 0),
            "rating_count": snapshot.get("rating_count", 0),
            "recent_feedback": snapshot.get("recent_feedback", []),
            "source": snapshot.get("source", "peer_feedback"),
        },
        "courses": {
            "courses": courses,
            "recommended_courses": courses,
        },
        "ml": report.get("ml_rating") or {},
    }), 200


# ─── GET /api/ai/mentor/analyse/<user_id> ────────────────────────────────────

@ai_bp.route("/mentor/analyse/<int:target_user_id>", methods=["GET"])
@auth_required
def api_mentor_analyse(target_user_id: int):
    """
    Full AI mentor analysis — career score, weaknesses, skill gaps, and
    course recommendations for a user.
    SECURITY: only the user themselves or an admin can view.
    ---
    tags:
      - AI
    security:
      - Bearer: []
    parameters:
      - in: path
        name: target_user_id
        type: integer
        required: true
    responses:
      200:
        description: Full mentor analysis
        schema:
          type: object
          properties:
            user_id:
              type: integer
            career_progress:
              type: object
            weaknesses:
              type: array
              items:
                type: object
            strengths:
              type: array
              items:
                type: object
            skill_gaps:
              type: object
            top_courses:
              type: array
              items:
                type: object
            mentor_report:
              type: string
      403:
        description: Forbidden
      404:
        description: User not found
    """
    from flask_jwt_extended import get_jwt_identity
    from models import db
    from models.user import User

    current_user_id = int(get_jwt_identity())
    current_user = db.session.get(User, current_user_id)
    if not current_user:
        return jsonify({"error": "User not found"}), 404

    if current_user.role != "admin" and current_user_id != target_user_id:
        return jsonify({
            "error": "Forbidden",
            "detail": "You are not authorized to view this user's analysis",
        }), 403

    try:
        result = generate_mentor_report(target_user_id)
    except Exception as exc:
        logger.exception("mentor analyse failed for user %s", target_user_id)
        return jsonify({"error": "Mentor analysis failed", "detail": str(exc)}), 500

    if "error" in result:
        return jsonify(result), 404

    try:
        from services.audit_log_service import log_ai_event
        log_ai_event(
            "MENTOR_ANALYSE",
            user_id=current_user_id,
            ip=request.remote_addr or "unknown",
            details={"target_user_id": target_user_id},
        )
    except Exception:
        logger.warning("audit log skipped for MENTOR_ANALYSE", exc_info=True)

    return jsonify(result), 200


# ─── POST /api/ai/cv/build ────────────────────────────────────────────────────

@ai_bp.route("/cv/build", methods=["POST"])
@auth_required
def api_cv_build():
    """
    Build an AI-generated CV for the calling user (or an admin-specified user).
    ---
    tags:
      - AI
    security:
      - Bearer: []
    parameters:
      - in: body
        name: body
        required: false
        schema:
          type: object
          properties:
            target_user_id:
              type: integer
              description: >
                Admin-only: generate CV for this user instead of the caller.
                Non-admins receive 403 if this differs from their own id.
            include_pdf:
              type: boolean
              default: false
              description: Reserved — PDF generation is not yet exposed.
    responses:
      200:
        description: Structured CV JSON
        schema:
          type: object
          properties:
            generated_at:
              type: string
            user:
              type: object
            summary:
              type: string
            skills:
              type: object
              properties:
                technical:
                  type: array
                  items:
                    type: string
                soft:
                  type: array
                  items:
                    type: string
            projects:
              type: array
              items:
                type: object
            achievements:
              type: array
              items:
                type: string
            metadata:
              type: object
            source:
              type: string
      400:
        description: Validation error
      403:
        description: Forbidden — non-admin requesting another user's CV
      404:
        description: Target user not found
    """
    from models import db
    from models.user import User
    from marshmallow import ValidationError as MarshmallowError

    current_user_id = int(get_jwt_identity())

    body = request.get_json(silent=True, force=True)
    if not isinstance(body, dict):
        body = {}
    try:
        data = cast(dict[str, Any], cv_build_schema.load(body))
    except MarshmallowError as exc:
        return jsonify({"error": "Validation failed", "details": exc.messages}), 400

    target_id = data.get("target_user_id") or current_user_id

    # RBAC: only admins may request another user's CV
    if target_id != current_user_id:
        caller = db.session.get(User, current_user_id)
        if not caller or caller.role != "admin":
            return jsonify({
                "error": "Forbidden",
                "detail": "Only admins may generate CVs for other users.",
            }), 403

    result = build_cv_for_user(target_id)

    if "error" in result:
        status_code = 404 if "not found" in result["error"].lower() else 500
        return jsonify(result), status_code

    try:
        persist_cv_from_ai_build(target_id, result)
    except Exception:
        current_app.logger.exception(
            "Failed to persist AI CV for user %s", target_id
        )

    from services.audit_log_service import log_ai_event
    log_ai_event(
        "CV_BUILD",
        user_id=current_user_id,
        ip=request.remote_addr or "unknown",
        details={"target_user_id": target_id, "source": result.get("source")},
    )

    return jsonify(result), 200


# ─── GET /api/ai/mentor/chat/history ──────────────────────────────────────────

def _mentor_thread_key(
    body: dict[str, Any],
    task_context: dict[str, Any],
) -> str:
    explicit = (body.get("thread_key") or "").strip()
    if explicit:
        return explicit[:120]
    if (
        isinstance(task_context, dict)
        and task_context.get("focus") == "skill_exploration"
        and task_context.get("skill_name")
    ):
        name = str(task_context["skill_name"]).strip().lower()
        if name:
            return f"skill:{name}"[:120]
    return "general"


@ai_bp.route("/mentor/chat/history", methods=["GET"])
@auth_required
def api_mentor_chat_history():
    """Return persisted mentor chat messages for the current user."""
    from models.mentor_chat_message import MentorChatMessage

    user_id = int(get_jwt_identity())
    limit = min(request.args.get("limit", 50, type=int), 100)
    thread_key = (request.args.get("thread_key") or "general").strip()[:120]
    rows = (
        MentorChatMessage.query.filter_by(user_id=user_id, thread_key=thread_key)
        .order_by(MentorChatMessage.created_at.asc())
        .limit(limit)
        .all()
    )
    return jsonify({"messages": [m.to_dict() for m in rows], "thread_key": thread_key}), 200


# ─── POST /api/ai/mentor/chat ─────────────────────────────────────────────────

@ai_bp.route("/mentor/chat", methods=["POST"])
@auth_required
def api_mentor_chat():
    """
    AI Career Mentor conversational chat.

    Generates a personalised reply using the caller's live data (tasks,
    skills, performance, project history) and the supplied conversation
    history.  Falls back to a rule-based reply when the Claude API is
    unavailable or not configured.
    ---
    tags:
      - AI
    security:
      - Bearer: []
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          required: [question]
          properties:
            question:
              type: string
              description: The user's question to the AI mentor
            history:
              type: array
              description: Previous messages in the conversation
              items:
                type: object
                properties:
                  role:
                    type: string
                    enum: [user, assistant]
                  content:
                    type: string
            task_context:
              type: object
              description: Optional current task context
            user_context:
              type: object
              description: Optional extra user context
    responses:
      200:
        description: AI mentor reply
        schema:
          type: object
          properties:
            reply:
              type: string
            suggestions:
              type: array
              items:
                type: string
      400:
        description: Missing question
      404:
        description: User not found
    """
    from models.mentor_chat_message import MentorChatMessage
    from models.user import User
    from services.ai_mentor_service import generate_mentor_report, generate_mentor_chat_reply

    current_user_id = int(get_jwt_identity())
    user = db.session.get(User, current_user_id)
    if not user:
        return jsonify({"error": "User not found"}), 404

    body: dict[str, Any] = request.get_json(silent=True, force=True) or {}
    question: str = (body.get("question") or "").strip()
    if not question:
        return jsonify({"error": "question is required"}), 400

    history: list[dict[str, Any]] = body.get("history") or []
    persist_history: bool = body.get("persist_history", True)
    task_context: dict[str, Any] = body.get("task_context") or {}
    user_context: dict[str, Any] = body.get("user_context") or {}
    skill_context: dict[str, Any] = {}
    if isinstance(task_context, dict) and task_context.get("focus") == "skill_exploration":
        skill_context = {
            "name": task_context.get("skill_name"),
            "level": task_context.get("skill_level"),
            "score": task_context.get("relevance_score"),
        }

    thread_key = _mentor_thread_key(body, task_context)

    try:
        mentor_data = generate_mentor_report(current_user_id)
    except Exception as exc:
        logger.exception("mentor chat context failed for user %s", current_user_id)
        return jsonify({"error": "Mentor analysis failed", "detail": str(exc)}), 500

    if "error" in mentor_data:
        return jsonify(mentor_data), 404

    if persist_history:
        db.session.add(
            MentorChatMessage(
                user_id=current_user_id,
                role="user",
                content=question,
                thread_key=thread_key,
            )
        )

    ml_meta: dict[str, Any] = {}
    suggestions: list[str] = []

    # ── Optional Claude layer (enriched with ML stats) ───────────────────
    anthropic_key: str = current_app.config.get("ANTHROPIC_API_KEY", "")
    ml_rating = mentor_data.get("ml_rating") or {}
    career_progress = mentor_data.get("career_progress") or {}
    reply_text: str = ""

    if anthropic_key:
        try:
            import anthropic  # type: ignore[import-untyped]

            weaknesses = mentor_data.get("weaknesses") or []
            strengths = mentor_data.get("strengths") or []
            top_courses = (mentor_data.get("top_courses") or [])[:3]
            skill_gaps = [
                str(w.get("area"))
                for w in weaknesses
                if isinstance(w, dict) and w.get("area")
            ]
            strength_list = [
                str(s.get("area"))
                for s in strengths
                if isinstance(s, dict) and s.get("area")
            ]
            current_level = career_progress.get("level", "Developer")
            career_score = career_progress.get("score", 0)
            pred = ml_rating.get("predicted_rating", 3.0)

            system_prompt = (
                f"You are an expert AI Career Mentor helping {user.display_name or user.full_name}.\n"
                f"ML model rating: {pred}/5 ({ml_rating.get('percentile_label', 'Good')}).\n"
                f"Level={current_level}, career_score={career_score:.0f}/100.\n"
                f"Skill gaps: {', '.join(skill_gaps) or 'none'}.\n"
                f"Strengths: {', '.join(strength_list) or 'none'}.\n"
                f"Courses: {', '.join(c.get('title', '') for c in top_courses)}.\n"
            )
            if skill_context.get("name"):
                system_prompt += (
                    f"\nThe user is exploring the skill **{skill_context.get('name')}** "
                    f"({skill_context.get('level', 'Intermediate')}, relevance "
                    f"{skill_context.get('score', '—')}/100). "
                    "Tailor every answer to that skill."
                )
            if user_context.get("models"):
                models = ", ".join(str(m) for m in user_context.get("models", []))
                system_prompt += (
                    f"\nUse Teamify ML models ({models}) and the user's live profile "
                    "when answering. Reference ML rating and career score when relevant."
                )
            system_prompt += " Give specific, actionable advice. Be concise (2-3 paragraphs max)."

            messages: list[dict[str, Any]] = []
            for h in history[-10:]:
                role = h.get("role")
                content = h.get("content")
                if role in ("user", "assistant") and content:
                    messages.append({"role": role, "content": str(content)})
            messages.append({"role": "user", "content": question})

            client = anthropic.Anthropic(api_key=anthropic_key)
            message = client.messages.create(
                model="claude-3-haiku-20240307",
                max_tokens=512,
                system=system_prompt,
                messages=messages,
            )
            reply_text = message.content[0].text if message.content else ""
            ml_meta = {
                "source": ml_rating.get("source", "formula"),
                "predicted_rating": ml_rating.get("predicted_rating"),
                "performance_label": ml_rating.get("percentile_label"),
                "career_score": career_score,
                "career_level": current_level,
                "model": "Profiles&AI Rating/teamify_model.pkl",
                "llm": "claude-3-haiku",
            }
            if skill_gaps:
                suggestions.append(f"How do I improve my {skill_gaps[0]}?")
            if top_courses:
                suggestions.append(f"Tell me about '{top_courses[0].get('title', '')}'")
            suggestions.append("What should I focus on this week?")
        except Exception as exc:
            logger.warning("Claude API call failed: %s — using ML mentor", exc)
            reply_text = ""

    if not reply_text:
        reply_text, suggestions, ml_meta = generate_mentor_chat_reply(
            current_user_id, question, mentor_data, skill_context=skill_context or None
        )
    elif not ml_meta:
        ml_meta = {
            "source": ml_rating.get("source", "formula"),
            "predicted_rating": ml_rating.get("predicted_rating"),
            "performance_label": ml_rating.get("percentile_label"),
            "career_score": career_progress.get("score", 0),
            "career_level": career_progress.get("level", "Developer"),
            "model": "Profiles&AI Rating/teamify_model.pkl",
        }

    if persist_history:
        db.session.add(
            MentorChatMessage(
                user_id=current_user_id,
                role="assistant",
                content=reply_text,
                thread_key=thread_key,
            )
        )
        db.session.commit()
    else:
        db.session.rollback()

    return jsonify({
        "reply": reply_text,
        "suggestions": suggestions[:3],
        "ml": ml_meta,
        "thread_key": thread_key,
    }), 200


def _rule_based_mentor_reply(
    question: str,
    level: str,
    skill_gaps: list[str],
    strengths: list[str],
    score: float,
    courses: list[dict[str, Any]],
) -> str:
    """
    Deterministic mentor reply built from the user's live profile data.
    Used when Claude is unavailable.
    """
    q_lower = question.lower()

    # Routing by intent
    if any(kw in q_lower for kw in ("focus", "improve", "next", "should i")):
        if skill_gaps:
            gap = skill_gaps[0]
            course_hint = ""
            for c in courses:
                if gap.lower() in (c.get("skills_covered") or "").lower():
                    course_hint = f" I recommend '{c['title']}' on {c.get('platform', 'online')}."
                    break
            return (
                f"Based on your profile, the highest-impact area to improve is **{gap}**."
                f"{course_hint} "
                f"Your current level is {level} with a career score of {score:.0f}/100. "
                "Consistent daily practice and working on real projects will accelerate your growth."
            )
        return (
            f"You are currently at {level} level with a score of {score:.0f}/100. "
            "Keep completing tasks on time and collaborating effectively with your team — "
            "those are the fastest paths to the next level."
        )

    if any(kw in q_lower for kw in ("promot", "level up", "senior", "lead")):
        return (
            f"To advance from {level}, focus on: "
            f"{', '.join(skill_gaps[:3]) if skill_gaps else 'deepening your technical skills'}. "
            "Demonstrate leadership by mentoring juniors and driving project outcomes. "
            f"Your current score is {score:.0f}/100 — aim for 75+ to be considered for promotion."
        )

    if any(kw in q_lower for kw in ("course", "learn", "study", "recommend")):
        if courses:
            titles = ", ".join(f"'{c.get('title', '')}' ({c.get('platform', '')})"
                               for c in courses)
            return (
                f"Based on your skill gaps ({', '.join(skill_gaps[:3]) or 'general areas'}), "
                f"I recommend: {titles}. "
                "Start with the one most relevant to your current project challenges."
            )
        return "Keep building your skills through hands-on projects and structured courses online."

    if any(kw in q_lower for kw in ("strength", "good at", "what am i")):
        if strengths:
            return (
                f"Your key strengths are: {', '.join(strengths[:3])}. "
                "Leverage these in high-visibility projects to build your reputation. "
                "Pair them with your areas for improvement to become well-rounded."
            )
        return "You are building strong fundamentals. Keep delivering quality work consistently."

    # Default fallback
    return (
        f"Great question! At your {level} level (score: {score:.0f}/100), "
        "focus on consistency, communication, and continuous learning. "
        f"Your top areas to develop are: {', '.join(skill_gaps[:3]) or 'technical depth'}. "
        "Would you like specific advice on any of these?"
    )
