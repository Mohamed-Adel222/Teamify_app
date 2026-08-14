"""
Profile Rating Service
======================
Provides two functions consumed by routes/ai.py:

  predict_user_rating(user_stats) → predicted AI rating score
    Attempts Profiles&AI Rating/teamify_model.pkl prediction.
    Falls back to a weighted formula if the model is unavailable.

  recommend_teammates(user_stats, top_n) → ranked list of similar users
    Uses cosine similarity on feature vectors drawn from the DB.
"""
from __future__ import annotations

import logging
import os
from typing import Any, Optional

logger = logging.getLogger(__name__)

_MODEL_PATH = os.path.abspath(
    os.path.join(
        os.path.dirname(__file__), "..", "ml_models",
        "Profiles&AI Rating", "teamify_model.pkl"
    )
)

_model_cache: Any = None
_model_load_error: Optional[str] = None


def _load_model():
    global _model_cache, _model_load_error
    if _model_cache is not None:
        return _model_cache
    if _model_load_error:
        return None
    try:
        import sys
        import joblib

        # The pkl was pickled with TeamifyModel from the ml_models directory.
        # Add that directory to sys.path temporarily so pickle can find the class.
        rating_dir = os.path.dirname(_MODEL_PATH)
        if rating_dir not in sys.path:
            sys.path.insert(0, rating_dir)

        _model_cache = joblib.load(_MODEL_PATH)
        logger.info("Profile rating model loaded from %s", _MODEL_PATH)
        return _model_cache
    except FileNotFoundError:
        _model_load_error = f"teamify_model.pkl not found at {_MODEL_PATH}"
        logger.warning(_model_load_error)
    except ModuleNotFoundError as exc:
        _model_load_error = (
            f"Cannot unpickle teamify_model.pkl — class module not found ({exc}). "
            "Using formula fallback."
        )
        logger.warning(_model_load_error)
    except Exception as exc:
        _model_load_error = f"Failed to load teamify_model.pkl: {exc}"
        logger.error(_model_load_error, exc_info=True)
    return None


def _formula_rating(stats: dict) -> float:
    """
    Weighted formula fallback that mirrors the GradientBoosting target.
    Produces a 0-5 score from standard user stat fields.
    """
    tasks_assigned = float(stats.get("tasks_assigned", 10))
    tasks_completed = float(stats.get("tasks_completed", 7))
    overdue = float(stats.get("overdue_tasks", 1))
    quality = float(stats.get("quality_score", 3.5))
    teamwork = float(stats.get("teamwork_score", 3.5))
    attendance = float(stats.get("attendance_rate", 0.9))
    skill_match = float(stats.get("skill_match_score", 0.7))
    avg_rating = float(stats.get("avg_rating", 3.5))
    availability = float(stats.get("availability_score", 0.8))

    completion_rate = min(tasks_completed / max(tasks_assigned, 1), 1.0)
    overdue_rate = min(overdue / max(tasks_assigned, 1), 1.0)

    score = (
        completion_rate * 1.5
        + (1 - overdue_rate) * 1.0
        + (quality / 5.0) * 0.8
        + (teamwork / 5.0) * 0.5
        + attendance * 0.4
        + skill_match * 0.4
        + (avg_rating / 5.0) * 0.4
        + availability * 0.3
        + float(stats.get("project_similarity", 0.5)) * 0.2
    )
    return round(min(score, 5.0), 2)


def predict_user_rating(user_stats: dict) -> dict:
    """
    Predict an AI performance rating for a user.

    Parameters
    ----------
    user_stats : dict
        Numeric feature dict from the user's ORM data.

    Returns
    -------
    dict with keys: predicted_rating, max_rating, source, percentile_label
    """
    model = _load_model()
    predicted = None
    source = "formula"

    if model is not None:
        try:
            import pandas as pd

            feature_cols = [
                "tasks_assigned", "tasks_completed", "overdue_tasks",
                "quality_score", "teamwork_score", "attendance_rate",
                "skill_match_score", "avg_rating", "availability_score",
                "project_similarity",
            ]
            row = {col: float(user_stats.get(col, 0)) for col in feature_cols}
            row["completion_rate"] = min(
                row["tasks_completed"] / max(row["tasks_assigned"], 1), 1.0
            )
            row["overdue_rate"] = min(
                row["overdue_tasks"] / max(row["tasks_assigned"], 1), 1.0
            )
            df = pd.DataFrame([row])

            if hasattr(model, "predict_rating"):
                # TeamifyModel.predict_rating(dict) → {"predicted_rating": float, ...}
                raw = model.predict_rating(row)
                predicted = float(raw["predicted_rating"] if isinstance(raw, dict) else raw)
                source = "ml_model"
            elif hasattr(model, "predict"):
                predicted = float(model.predict(df)[0])
                source = "ml_model"
        except Exception as exc:
            logger.error("Profile rating ML prediction failed: %s", exc, exc_info=True)

    if predicted is None:
        predicted = _formula_rating(user_stats)

    predicted = round(min(max(predicted, 0.0), 5.0), 2)

    if predicted >= 4.5:
        label = "Excellent"
    elif predicted >= 3.5:
        label = "Good"
    elif predicted >= 2.5:
        label = "Average"
    else:
        label = "Needs Improvement"

    return {
        "predicted_rating": predicted,
        "max_rating": 5.0,
        "percentile_label": label,
        "source": source,
    }


def recommend_teammates(
    user_stats: dict,
    top_n: int = 5,
    *,
    current_user_id: int | None = None,
) -> list:
    """
    Rank compatible teammates using the same ML feature vector as mentor/rating
    services, blended with skill overlap for readable match percentages.
    """
    try:
        import numpy as np
        from models.user import User
        from services.ai_mentor_service import build_user_ml_stats
        from utils.skills import normalize_skills_list

        _FEAT_KEYS = [
            "tasks_assigned",
            "tasks_completed",
            "overdue_tasks",
            "quality_score",
            "teamwork_score",
            "attendance_rate",
            "skill_match_score",
            "avg_rating",
            "availability_score",
            "project_similarity",
        ]

        def _vec(stats: dict) -> np.ndarray:
            return np.array(
                [float(stats.get(k, 0) or 0) for k in _FEAT_KEYS],
                dtype=float,
            )

        def _cosine(a: np.ndarray, b: np.ndarray) -> float:
            na = float(np.linalg.norm(a))
            nb = float(np.linalg.norm(b))
            if na == 0.0 or nb == 0.0:
                return 0.0
            return float(np.dot(a, b) / (na * nb))

        if not user_stats and current_user_id:
            user_stats = build_user_ml_stats(current_user_id)

        ref_vec = _vec(user_stats or {})
        current_skills: set[str] = set()
        if current_user_id:
            current = User.query.get(current_user_id)
            if current:
                current_skills = set(normalize_skills_list(current.skills))

        q = User.query.filter(User.account_status == "approved")
        if current_user_id:
            q = q.filter(User.id != current_user_id)

        scored = []
        for u in q.all():
            u_stats = build_user_ml_stats(u.id)
            similarity = _cosine(ref_vec, _vec(u_stats))

            u_skills = set(normalize_skills_list(u.skills))
            skill_overlap = 0.0
            if current_skills and u_skills:
                skill_overlap = len(current_skills & u_skills) / len(current_skills | u_skills)

            match_pct = round(min(100.0, similarity * 100 * 0.65 + skill_overlap * 100 * 0.35), 1)
            if match_pct <= 0 and skill_overlap > 0:
                match_pct = round(skill_overlap * 100, 1)

            scored.append({
                "user_id": u.id,
                "display_name": u.display_name,
                "full_name": u.full_name or u.display_name,
                "email": u.email,
                "user_type": u.user_type,
                "professional_field": u.professional_field,
                "similarity_score": round(similarity, 4),
                "match_percent": match_pct,
                "experience_level": u.experience_level,
                "skills": normalize_skills_list(u.skills)[:8],
            })

        scored.sort(key=lambda x: (x["match_percent"], x["similarity_score"]), reverse=True)
        return scored[:top_n]

    except Exception as exc:
        logger.error("Teammate recommendation failed: %s", exc, exc_info=True)
        return []


def get_profile_rating_model_status() -> dict:
    """Report whether teamify_model.pkl is present and loaded."""
    model = _load_model()
    return {
        "file_present": os.path.exists(_MODEL_PATH),
        "loaded": model is not None,
        "error": _model_load_error,
        "path": os.path.abspath(_MODEL_PATH),
    }
