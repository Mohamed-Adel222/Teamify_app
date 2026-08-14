"""Runtime status of ML models wired into Teamify AI APIs.

A model is REAL_MODEL only when the artifact exists, required packages import,
the weights load into memory, AND a synthetic inference call succeeds.
File presence alone is never enough. APIs keep their heuristic fallbacks.
"""
from __future__ import annotations

import importlib.util
import os
import platform
import sys
from typing import Any, Callable

from services.anomaly_service_ml import score_login_features
from services.chat_summarization_service import summarize_chat
from services.cv_builder_service import probe_cv_builder_inference
from services.delay_predictor_service import predict_delay_probability
from services.profile_rating_service import predict_user_rating
from services.task_pipeline_service import assign_best_members, classify_task

REAL_MODEL = "REAL_MODEL"
FALLBACK = "FALLBACK"

_BACKEND_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

_SECRET_KEY_FRAGMENTS = (
    "SECRET",
    "PASSWORD",
    "TOKEN",
    "API_KEY",
    "DATABASE",
    "CREDENTIAL",
    "JWT",
    "PRIVATE",
    "AUTH",
    "ACCESS_KEY",
)

_SAMPLE_CV_USER = {
    "user": {
        "name": "Status Probe",
        "role": "Backend Developer",
        "email": "probe@teamify.local",
    },
    "projects": [
        {
            "title": "Sample API",
            "description": "REST API for status probes",
            "technologies": ["Python", "Flask"],
            "role": "Developer",
            "status": "completed",
            "rating": 4.5,
            "start_date": "2025-01-01",
            "end_date": "2025-06-01",
        }
    ],
    "tasks": {"completed": 8, "total": 10, "overdue": 1},
    "metrics": {
        "trust_score": 80,
        "consistency_score": 75,
        "teamwork_score": 70,
        "avg_rating": 4.2,
    },
    "collaboration": {
        "messages_sent": 20,
        "comments_written": 5,
        "team_count": 3,
    },
    "activity": {"activity_count": 40, "login_frequency": 5},
    "skills": ["Python", "Flask"],
    "experience": 3,
}


def _rel(path: str | None) -> str:
    if not path:
        return ""
    abs_path = os.path.abspath(path)
    try:
        return os.path.relpath(abs_path, _BACKEND_ROOT)
    except ValueError:
        return abs_path


def _module_available(name: str) -> bool:
    try:
        return importlib.util.find_spec(name) is not None
    except (ImportError, ValueError, ModuleNotFoundError):
        return False


def check_dependencies(names: list[str]) -> tuple[bool, str | None]:
    missing = [n for n in names if not _module_available(n)]
    if missing:
        return False, f"No module named '{missing[0]}'"
    return True, None


def find_secret_leaks(payload: Any) -> list[str]:
    """Return secret-like substrings found in a JSON-able status payload."""
    hits: list[str] = []

    def walk(value: Any) -> None:
        if isinstance(value, dict):
            for key, nested in value.items():
                key_up = str(key).upper()
                if any(frag in key_up for frag in _SECRET_KEY_FRAGMENTS):
                    hits.append(str(key))
                walk(nested)
        elif isinstance(value, list):
            for item in value:
                walk(item)
        elif isinstance(value, str):
            up = value.upper()
            for frag in ("BEGIN PRIVATE", "POSTGRES://", "MYSQL://", "MONGODB://"):
                if frag in up:
                    hits.append(value[:32])

    walk(payload)
    return hits


def _environment_payload() -> dict[str, Any]:
    """Non-secret runtime facts for production verification."""
    packages = {
        name: _module_available(name)
        for name in (
            "joblib",
            "sklearn",
            "pandas",
            "numpy",
            "torch",
            "transformers",
            "reportlab",
        )
    }
    flask_env = os.getenv("FLASK_ENV") or os.getenv("APP_ENV") or "unspecified"
    return {
        "python_version": sys.version.split()[0],
        "platform": platform.platform(),
        "hostname": platform.node(),
        "implementation": platform.python_implementation(),
        "flask_env": flask_env,
        "packages": packages,
    }


def finalize_probe(
    *,
    model_id: str,
    name: str,
    description: str,
    endpoint: str,
    path: str,
    file_exists: bool,
    dependencies_ok: bool,
    loaded: bool,
    inference_test: bool,
    error: str | None,
    extra: dict | None = None,
) -> dict:
    """Turn raw probe flags into the public status contract.

    REAL_MODEL requires file + deps + in-memory load + successful inference.
    """
    real = bool(file_exists and dependencies_ok and loaded and inference_test)
    if real:
        mode = REAL_MODEL
        status = "loaded"
        error = None
    elif loaded and not inference_test:
        mode = FALLBACK
        status = "error"
    else:
        mode = FALLBACK
        status = "fallback"

    payload = {
        "id": model_id,
        "name": name,
        "description": description,
        "endpoint": endpoint,
        "path": _rel(path),
        "file_exists": bool(file_exists),
        "file_present": bool(file_exists),
        "dependencies_ok": bool(dependencies_ok),
        "loaded": bool(loaded),
        "inference_test": bool(inference_test),
        "mode": mode,
        "status": status,
        "error": error,
        # Compatibility: "linked" only means the artifact is wired + on disk.
        "linked": bool(file_exists),
        "uses_fallback": mode != REAL_MODEL,
    }
    if extra:
        payload.update(extra)
    return payload


def run_probe(
    *,
    model_id: str,
    name: str,
    description: str,
    endpoint: str,
    file_paths: list[str],
    dependencies: list[str],
    load_fn: Callable[[], Any],
    infer_fn: Callable[[], Any],
    load_error_fn: Callable[[], str | None] | None = None,
) -> dict:
    """Check file → deps → load → inference. Never writes to the database."""
    existing = [p for p in file_paths if p and os.path.exists(p)]
    path = existing[0] if existing else (file_paths[0] if file_paths else "")
    file_exists = bool(existing)
    deps_ok, dep_err = check_dependencies(dependencies)

    loaded = False
    inference_test = False
    error: str | None = None

    if not file_exists:
        error = f"Model file not found at {path}"
    elif not deps_ok:
        error = dep_err
    else:
        try:
            loaded_obj = load_fn()
            loaded = bool(loaded_obj)
            if not loaded:
                err = load_error_fn() if load_error_fn else None
                error = err or "Failed to load model into memory"
            else:
                try:
                    infer_result = infer_fn()
                    inference_test = bool(infer_result)
                    if not inference_test:
                        error = "Inference test did not use the real model"
                except Exception as exc:
                    loaded = True
                    inference_test = False
                    error = f"Inference test failed: {exc}"
        except Exception as exc:
            loaded = False
            inference_test = False
            error = f"Failed to load model: {exc}"

    return finalize_probe(
        model_id=model_id,
        name=name,
        description=description,
        endpoint=endpoint,
        path=path,
        file_exists=file_exists,
        dependencies_ok=deps_ok,
        loaded=loaded,
        inference_test=inference_test,
        error=error,
    )


def _probe_task_category() -> dict:
    from services import task_pipeline_service as tps

    weights = [
        os.path.join(tps._CATEGORY_MODEL_DIR, "model.safetensors"),
        os.path.join(tps._CATEGORY_MODEL_DIR, "pytorch_model.bin"),
    ]

    def load():
        model, tokenizer, _le = tps._load_category_model()
        return model is not None and tokenizer is not None

    def infer():
        result = classify_task(
            "Build a REST API endpoint in Flask with JWT authentication"
        )
        return result.get("source") == "ml_model"

    return run_probe(
        model_id="task_category",
        name="DistilBERT task category",
        description="Classifies a task into a domain (frontend, backend, ui_ux, …).",
        endpoint="POST /api/ai/classify-task",
        file_paths=weights,
        dependencies=["torch", "transformers", "joblib"],
        load_fn=load,
        infer_fn=infer,
        load_error_fn=lambda: tps._cat_load_error,
    )


def _probe_assignment() -> dict:
    from services import task_pipeline_service as tps

    def load():
        model, feats = tps._load_assignment_model()
        return model is not None and feats is not None

    def infer():
        ranked = assign_best_members(
            {"category": "backend", "required_skills": ["Python", "Flask"]},
            [
                {
                    "id": 1,
                    "member_primary_domain": "backend",
                    "member_skills": ["Python", "Flask"],
                    "rating": 4.2,
                    "current_tasks": 1,
                },
                {
                    "id": 2,
                    "member_primary_domain": "frontend",
                    "member_skills": ["React"],
                    "rating": 3.1,
                    "current_tasks": 4,
                },
            ],
        )
        return bool(ranked) and ranked[0].get("score_source") == "ml_model"

    return run_probe(
        model_id="task_assignment",
        name="Assignment Gradient Boosting",
        description="Ranks project members for a task using skill, rating, and workload.",
        endpoint="POST /api/ai/assign-members",
        file_paths=[tps._ASSIGNMENT_MODEL_PATH, tps._ASSIGNMENT_FEATURES_PATH],
        dependencies=["joblib", "pandas", "sklearn"],
        load_fn=load,
        infer_fn=infer,
        load_error_fn=lambda: tps._assign_load_error,
    )


def _probe_delay() -> dict:
    from services import delay_predictor_service as dps

    def load():
        return dps._load_model() is not None

    def infer():
        result = predict_delay_probability(
            {
                "estimated_duration_days": 7,
                "progress_percent": 20,
                "priority_level": "medium",
                "complexity_level": 2,
                "num_subtasks": 1,
                "status": "in_progress",
                "days_since_start": 3,
                "days_remaining": 4,
                "member_experience_years": 2,
                "member_on_time_rate": 0.8,
                "member_current_tasks": 2,
                "workload_ratio": 0.4,
            }
        )
        return result.get("source") == "ml_model"

    return run_probe(
        model_id="delay_predictor",
        name="Delay Predictor",
        description="Estimates whether a task or project is likely to slip.",
        endpoint="POST /api/ai/delay",
        file_paths=[os.path.abspath(dps._MODEL_PATH)],
        dependencies=["joblib", "pandas", "sklearn"],
        load_fn=load,
        infer_fn=infer,
        load_error_fn=lambda: dps._model_load_error,
    )


def _probe_profile_rating() -> dict:
    from services import profile_rating_service as prs

    def load():
        return prs._load_model() is not None

    def infer():
        result = predict_user_rating(
            {
                "tasks_assigned": 10,
                "tasks_completed": 7,
                "overdue_tasks": 1,
                "quality_score": 3.5,
                "teamwork_score": 3.8,
                "attendance_rate": 0.9,
                "skill_match_score": 0.7,
                "avg_rating": 3.6,
                "availability_score": 0.8,
                "project_similarity": 0.5,
            }
        )
        return result.get("source") == "ml_model"

    return run_probe(
        model_id="profile_rating",
        name="Profile AI rating",
        description="Scores a member profile and powers teammate recommendations.",
        endpoint="GET /api/ai/predict-rating/<user_id>",
        file_paths=[prs._MODEL_PATH],
        dependencies=["joblib", "pandas"],
        load_fn=load,
        infer_fn=infer,
        load_error_fn=lambda: prs._model_load_error,
    )


def _probe_summarization() -> dict:
    from services import chat_summarization_service as css

    def load():
        return css._load_model() is not None

    def infer():
        model = css._load_model()
        if model is None or not hasattr(model, "summarize"):
            raise RuntimeError(
                "Chat_Summarization.pkl loaded but has no summarize(); "
                "using built-in extractive fallback"
            )
        result = summarize_chat(
            "Alice: Let's ship the API today.\n"
            "Bob: I will write the tests this afternoon.",
            top_n=2,
        )
        return result.get("source") == "ml_model"

    return run_probe(
        model_id="chat_summarization",
        name="Chat / meeting summarization",
        description="Extracts summaries, key points, and action items from transcripts.",
        endpoint="POST /api/ai/summarize-chat",
        file_paths=[os.path.abspath(css._MODEL_PATH)],
        dependencies=["joblib"],
        load_fn=load,
        infer_fn=infer,
        load_error_fn=lambda: css._model_load_error,
    )


def _probe_security() -> dict:
    from services import anomaly_service_ml as asm

    def load():
        return asm._load_bundle() is not None

    def infer():
        result = score_login_features({"user_id": 1, "failed_attempts": 0})
        return (
            result.get("source") == "ml_model"
            and result.get("anomaly_score") is not None
        )

    return run_probe(
        model_id="security_anomaly",
        name="Security IsolationForest",
        description="Flags unusual login behaviour from failed-attempt patterns.",
        endpoint="POST /api/ai/detect-anomaly",
        file_paths=[os.path.abspath(asm._MODEL_PATH)],
        dependencies=["joblib", "pandas", "sklearn"],
        load_fn=load,
        infer_fn=infer,
        load_error_fn=lambda: asm._load_error,
    )


def _probe_cv_builder() -> dict:
    from services import cv_builder_service as cvs

    def load():
        cvs._load_pipeline()
        return cvs._cv_module is not None or cvs._pkl_model is not None

    def infer():
        result = probe_cv_builder_inference(_SAMPLE_CV_USER)
        return bool(result.get("ok"))

    return run_probe(
        model_id="cv_builder",
        name="CV builder",
        description="Builds a structured resume from the member's live profile data.",
        endpoint="POST /api/ai/cv/build",
        file_paths=[cvs._MODULE_FILE, cvs._PKL_FILE],
        dependencies=[],
        load_fn=load,
        infer_fn=infer,
        load_error_fn=lambda: cvs._load_error,
    )


def get_ai_models_status() -> dict:
    """Probe every wired ML artifact. Does not persist anything."""
    models = [
        _probe_task_category(),
        _probe_assignment(),
        _probe_delay(),
        _probe_profile_rating(),
        _probe_summarization(),
        _probe_security(),
        _probe_cv_builder(),
    ]

    real = sum(1 for m in models if m["mode"] == REAL_MODEL)
    fallback = sum(
        1 for m in models if m["mode"] == FALLBACK and m["status"] != "error"
    )
    errors = sum(1 for m in models if m["status"] == "error")
    try:
        from services.system_settings_service import is_ai_enabled

        ai_enabled = bool(is_ai_enabled())
    except Exception:
        ai_enabled = True

    return {
        "models": models,
        "total": len(models),
        "real_model_count": real,
        "fallback_count": fallback,
        "error_count": errors,
        "loaded_count": real,
        "linked_count": sum(1 for m in models if m["linked"]),
        "all_linked": all(m["linked"] for m in models),
        "all_loaded": real == len(models),
        "ai_enabled": ai_enabled,
        "environment": _environment_payload(),
    }
