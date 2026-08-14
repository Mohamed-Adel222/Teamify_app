"""Aggregate status of on-disk ML models wired into Teamify APIs."""
from __future__ import annotations

import os

from services.anomaly_service_ml import get_security_model_status
from services.chat_summarization_service import get_chat_summarization_model_status
from services.cv_builder_service import get_cv_builder_status
from services.delay_predictor_service import get_delay_model_status
from services.profile_rating_service import get_profile_rating_model_status
from services.task_pipeline_service import (
    get_assignment_model_status,
    get_category_model_status,
)


def _rel(path: str | None) -> str:
    if not path:
        return ""
    backend_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    abs_path = os.path.abspath(path)
    try:
        return os.path.relpath(abs_path, backend_root)
    except ValueError:
        return abs_path


def _entry(
    *,
    model_id: str,
    name: str,
    description: str,
    endpoint: str,
    status: dict,
) -> dict:
    file_present = bool(status.get("file_present") or status.get("model_available"))
    loaded = bool(status.get("loaded") or status.get("model_available"))
    error = status.get("error")
    return {
        "id": model_id,
        "name": name,
        "description": description,
        "endpoint": endpoint,
        "file_present": file_present,
        "loaded": loaded,
        "linked": file_present,
        "uses_fallback": not loaded,
        "path": _rel(status.get("path") or status.get("model_path")),
        "error": error,
    }


def get_ai_models_status() -> dict:
    """Return a report of every ML artifact the app is wired to."""
    models = [
        _entry(
            model_id="task_category",
            name="DistilBERT task category",
            description="Classifies a task into a domain (frontend, backend, ui_ux, …).",
            endpoint="POST /api/ai/classify-task",
            status=get_category_model_status(),
        ),
        _entry(
            model_id="task_assignment",
            name="Assignment Gradient Boosting",
            description="Ranks project members for a task using skill, rating, and workload.",
            endpoint="POST /api/ai/assign-members",
            status=get_assignment_model_status(),
        ),
        _entry(
            model_id="delay_predictor",
            name="Delay Predictor",
            description="Estimates whether a task or project is likely to slip.",
            endpoint="POST /api/ai/delay",
            status=get_delay_model_status(),
        ),
        _entry(
            model_id="profile_rating",
            name="Profile AI rating",
            description="Scores a member profile and powers teammate recommendations.",
            endpoint="GET /api/ai/predict-rating/<user_id>",
            status=get_profile_rating_model_status(),
        ),
        _entry(
            model_id="chat_summarization",
            name="Chat / meeting summarization",
            description="Extracts summaries, key points, and action items from transcripts.",
            endpoint="POST /api/ai/summarize-chat",
            status=get_chat_summarization_model_status(),
        ),
        _entry(
            model_id="security_anomaly",
            name="Security IsolationForest",
            description="Flags unusual login behaviour from failed-attempt patterns.",
            endpoint="POST /api/ai/detect-anomaly",
            status=get_security_model_status(),
        ),
        _entry(
            model_id="cv_builder",
            name="CV builder",
            description="Builds a structured resume from the member's live profile data.",
            endpoint="POST /api/ai/cv/build",
            status=get_cv_builder_status(),
        ),
    ]

    linked = sum(1 for m in models if m["linked"])
    loaded = sum(1 for m in models if m["loaded"])
    try:
        from services.system_settings_service import is_ai_enabled
        ai_enabled = bool(is_ai_enabled())
    except Exception:
        ai_enabled = True
    return {
        "models": models,
        "total": len(models),
        "linked_count": linked,
        "loaded_count": loaded,
        "fallback_count": len(models) - loaded,
        "all_linked": linked == len(models),
        "all_loaded": loaded == len(models),
        "ai_enabled": ai_enabled,
    }
