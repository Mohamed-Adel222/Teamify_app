"""
Delay Predictor Service
=======================
Wraps ml_models/Delay_Predictor.pkl — a trained sklearn pipeline that
predicts whether a task is at risk of being delayed.

Features consumed by the model (19 columns, matching the notebook training data):
  estimated_duration_days, progress_percent, priority_level,
  complexity_level, num_subtasks, status (str: ongoing|completed),
  days_since_start, days_remaining, expected_progress_percent,
  progress_gap, member_experience_years, member_on_time_rate,
  member_avg_delay_days, max_allowed_tasks, member_current_tasks,
  workload_ratio, projects_completed, technical_skill, communication_skill
"""
from __future__ import annotations

import logging
import os
from typing import Any, Optional

logger = logging.getLogger(__name__)

_MODEL_PATH = os.path.join(
    os.path.dirname(__file__), "..", "ml_models", "Delay Predictor", "Delay_Predictor.pkl"
)

_FEATURE_COLS = [
    "estimated_duration_days",
    "progress_percent",
    "priority_level",
    "complexity_level",
    "num_subtasks",
    "status",
    "days_since_start",
    "days_remaining",
    "expected_progress_percent",
    "progress_gap",
    "member_experience_years",
    "member_on_time_rate",
    "member_avg_delay_days",
    "max_allowed_tasks",
    "member_current_tasks",
    "workload_ratio",
    "projects_completed",
    "technical_skill",
    "communication_skill",
]

_PRIORITY_MAP = {"low": 1, "medium": 2, "high": 3}

# Map ORM status values → the two training-set labels
_STATUS_MAP = {
    "pending":     "ongoing",
    "in_progress": "ongoing",
    "done":        "completed",
    "completed":   "completed",
}

# LabelEncoder was fit alphabetically on ["completed", "ongoing"]
# completed → 0,  ongoing → 1
_STATUS_ENCODE = {"completed": 0, "ongoing": 1}

_model_cache: Any = None
_model_load_error: Optional[str] = None


def _load_model() -> Any:
    """Lazy-load the pkl model once per process."""
    global _model_cache, _model_load_error

    if _model_cache is not None:
        return _model_cache
    if _model_load_error:
        return None

    try:
        import joblib

        from services.ml_artifacts import (
            ensure_sklearn_unpickle_compat,
            require_joblib_artifact,
        )

        path = require_joblib_artifact(_MODEL_PATH, "Delay_Predictor.pkl")
        ensure_sklearn_unpickle_compat()
        obj = joblib.load(path)

        # Validate: must be a trained model or the {model, feature_columns} bundle
        if isinstance(obj, dict) and "cells" in obj:
            _model_load_error = (
                "Delay_Predictor.pkl still contains a Jupyter notebook. "
                "Re-run the training cells and save with: "
                "joblib.dump({'model': clf, 'feature_columns': cols}, 'Delay_Predictor.pkl')"
            )
            logger.warning(_model_load_error)
            return None

        # Verify expected bundle keys when it's a dict
        if isinstance(obj, dict) and "model" not in obj:
            _model_load_error = "Delay_Predictor.pkl is a dict but has no 'model' key"
            logger.warning(_model_load_error)
            return None

        _model_cache = obj
        logger.info("Delay predictor model loaded from %s", path)
        return _model_cache
    except FileNotFoundError:
        _model_load_error = f"Delay_Predictor.pkl not found at {_MODEL_PATH}"
        logger.warning(_model_load_error)
    except Exception as exc:
        _model_load_error = f"Failed to load Delay_Predictor.pkl: {exc}"
        logger.error(_model_load_error, exc_info=True)

    return None


def startup_check() -> None:
    """Log a structured warning at boot when the delay predictor pkl is missing."""
    _load_model()
    if _model_load_error:
        logger.warning("AI startup: delay predictor unavailable — %s", _model_load_error)
    else:
        logger.info("AI startup: delay predictor model loaded")


def predict_delay_probability(task_features: dict) -> dict:
    """
    Predict delay probability for a single task using the ML model.

    Parameters
    ----------
    task_features : dict
        Task and assignee feature values. Keys should match _FEATURE_COLS.
        Missing keys are filled with safe defaults.

    Returns
    -------
    dict with keys:
        model_available (bool)
        delay_predicted (bool | None)
        delay_probability (float 0–100 | None)
        source ("ml_model" | "fallback")
        error (str, only when source is "fallback")
    """
    model = _load_model()
    if model is None:
        return {
            "model_available": False,
            "delay_predicted": None,
            "delay_probability": None,
            "source": "fallback",
            "error": _model_load_error or "Model not loaded",
        }

    try:
        import pandas as pd

        priority_raw = str(task_features.get("priority_level", "medium")).lower()
        priority_int = (
            priority_raw if priority_raw.isdigit()
            else str(_PRIORITY_MAP.get(priority_raw, 2))
        )

        status_raw = str(task_features.get("status", "pending")).lower()
        status_mapped = _STATUS_MAP.get(status_raw, "ongoing")

        days_since_start = int(task_features.get("days_since_start", 0))
        estimated = int(task_features.get("estimated_duration_days", 7))
        progress = float(task_features.get("progress_percent", 0.0))

        expected_progress = (
            (days_since_start / estimated * 100) if estimated > 0 else 0.0
        )
        progress_gap = float(
            task_features.get(
                "progress_gap", expected_progress - progress
            )
        )

        member_on_time = float(task_features.get("member_on_time_rate", 0.75))
        workload_hours = float(task_features.get("workload_ratio", 0.4))

        # Encode status to int: completed=0, ongoing=1 (LabelEncoder alphabetical)
        status_encoded = _STATUS_ENCODE.get(status_mapped, 1)

        row = {
            "estimated_duration_days": estimated,
            "progress_percent": progress,
            "priority_level": int(priority_int),
            "complexity_level": int(task_features.get("complexity_level", 2)),
            "num_subtasks": int(task_features.get("num_subtasks", 0)),
            "status": status_encoded,
            "days_since_start": days_since_start,
            "days_remaining": int(task_features.get("days_remaining", 7)),
            "expected_progress_percent": round(expected_progress, 2),
            "progress_gap": round(progress_gap, 2),
            "member_experience_years": int(
                task_features.get("member_experience_years", 2)
            ),
            "member_on_time_rate": member_on_time,
            "member_avg_delay_days": float(
                task_features.get(
                    "member_avg_delay_days", (1 - member_on_time) * 15
                )
            ),
            "max_allowed_tasks": int(task_features.get("max_allowed_tasks", 5)),
            "member_current_tasks": int(task_features.get("member_current_tasks", 2)),
            "workload_ratio": workload_hours,
            "projects_completed": int(task_features.get("projects_completed", 5)),
            "technical_skill": int(task_features.get("technical_skill", 75)),
            "communication_skill": int(task_features.get("communication_skill", 75)),
        }

        df = pd.DataFrame([row])[_FEATURE_COLS]

        # Handle both raw estimator and {"model": ..., "scaler": ...} bundle
        estimator = model
        if isinstance(model, dict):
            estimator = model.get("model") or model.get("classifier") or model.get("pipeline")
            scaler = model.get("scaler") or model.get("preprocessor")
            if estimator is None:
                raise ValueError("Delay_Predictor.pkl dict has no 'model' key")
            if scaler is not None:
                numeric_cols = df.select_dtypes(include="number").columns
                df[numeric_cols] = scaler.transform(df[numeric_cols])

        if hasattr(estimator, "predict_proba"):
            proba = estimator.predict_proba(df)[0]
            delay_prob = float(proba[1]) * 100
            delay_predicted = delay_prob >= 50.0
        else:
            pred = estimator.predict(df)[0]
            delay_predicted = bool(pred)
            delay_prob = 100.0 if delay_predicted else 0.0

        return {
            "model_available": True,
            "delay_predicted": delay_predicted,
            "delay_probability": round(delay_prob, 1),
            "source": "ml_model",
        }

    except Exception as exc:
        logger.error("Delay prediction inference failed: %s", exc, exc_info=True)
        return {
            "model_available": True,
            "delay_predicted": None,
            "delay_probability": None,
            "source": "fallback",
            "error": str(exc),
        }


def predict_task_delay(task_data: dict, user_data: dict | None = None) -> dict:
    """
    Compatibility wrapper used by routes/ai.py.
    Merges task_data and user_data dicts, maps field name aliases,
    then delegates to predict_delay_probability.

    Returns a dict with risk_level, delay_probability, and source.
    """
    features = dict(task_data or {})

    if user_data:
        mapping = {
            "experience_years": "member_experience_years",
            "on_time_rate": "member_on_time_rate",
            "avg_delay_days": "member_avg_delay_days",
            "current_tasks": "member_current_tasks",
        }
        for src, dst in mapping.items():
            if src in user_data and dst not in features:
                features[dst] = user_data[src]
        for k, v in user_data.items():
            if k not in mapping and k not in features:
                features[k] = v

    result = predict_delay_probability(features)

    prob = result.get("delay_probability") or 0
    if prob >= 70:
        risk = "high"
    elif prob >= 40:
        risk = "medium"
    else:
        risk = "low"

    return {
        "risk_level": risk,
        "delay_probability": prob,
        "delay_predicted": result.get("delay_predicted"),
        "source": result.get("source", "fallback"),
    }


def get_delay_model_status() -> dict:
    """Report whether Delay_Predictor.pkl is loaded and ready."""
    model = _load_model()
    path = os.path.abspath(_MODEL_PATH)
    return {
        "model_available": model is not None,
        "file_present": os.path.exists(path),
        "loaded": model is not None,
        "model_name": "Delay_Predictor",
        "model_path": path,
        "path": path,
        "feature_count": len(_FEATURE_COLS),
        "error": _model_load_error,
    }


def _hydrate_task_fields_from_db(task) -> None:
    """Fill missing ML inputs from real task columns (in-memory only)."""
    from datetime import date

    if not task.start_date and task.created_at:
        task.start_date = task.created_at.date()

    if not task.estimated_duration_days or task.estimated_duration_days < 1:
        if task.deadline_days and task.deadline_days > 0:
            task.estimated_duration_days = int(task.deadline_days)
        elif task.due_date:
            start = task.start_date or date.today()
            task.estimated_duration_days = max((task.due_date - start).days, 1)
        else:
            task.estimated_duration_days = 7

    if task.priority:
        mapped = _PRIORITY_MAP.get(str(task.priority).lower())
        if mapped is not None:
            task.priority_level = mapped

    if task.status == "done":
        task.progress_percent = max(float(task.progress_percent or 0), 100.0)
    elif task.status == "in_progress" and (task.progress_percent or 0) <= 0:
        task.progress_percent = 25.0


def build_task_features_from_orm(task, assignee=None) -> dict:
    """
    Build ML feature dict from live Task/User ORM rows (database-backed).
    """
    from models.project import Project
    from services.ai_features import get_member_features, get_task_features
    from services.ai_service import get_user_workload

    _hydrate_task_fields_from_db(task)

    project = Project.query.get(task.project_id) if task.project_id else None
    features = get_task_features(task)
    features["status"] = task.status or "pending"

    days_rem = task.days_remaining
    features["days_remaining"] = days_rem if days_rem is not None else 7

    if assignee is not None:
        mf = (
            get_member_features(assignee, project)
            if project is not None
            else get_member_features(assignee)
        )
        active = get_user_workload(assignee.id)
        max_allowed = int(assignee.max_allowed_tasks or 5)
        quality = float(mf.get("quality_score") or getattr(assignee, "quality_score", 0.75) or 0.75)
        attendance = float(mf.get("attendance_rate") or getattr(assignee, "attendance_rate", 0.75) or 0.75)
        features.update({
            "member_experience_years": int(assignee.member_experience_years or 0),
            "member_on_time_rate": float(assignee.member_on_time_rate or 0.75),
            "member_avg_delay_days": float(assignee.member_avg_delay_days or 0.0),
            "max_allowed_tasks": max_allowed,
            "member_current_tasks": active,
            "workload_ratio": min(active / max(max_allowed, 1), 1.0),
            "projects_completed": int(getattr(assignee, "tasks_completed", 0) or 0),
            "technical_skill": int(quality * 100),
            "communication_skill": int(attendance * 100),
        })
    else:
        features.update({
            "member_experience_years": 2,
            "member_on_time_rate": 0.75,
            "member_avg_delay_days": 3.0,
            "max_allowed_tasks": 5,
            "member_current_tasks": 0,
            "workload_ratio": 0.0,
            "projects_completed": 0,
            "technical_skill": 75,
            "communication_skill": 75,
        })

    return features
