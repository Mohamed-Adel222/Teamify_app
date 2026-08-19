"""Live sklearn model checks: REAL_MODEL only after load + inference.

When Git LFS weights are still pointer files (typical CI clone), the live
tests skip instead of failing. They never treat file_exists as proof.
"""
from unittest.mock import patch

import pytest

from services.anomaly_service_ml import _MODEL_PATH as SECURITY_PATH
from services.anomaly_service_ml import score_login_features
from services.ai_models_status_service import REAL_MODEL, get_ai_models_status
from services.chat_summarization_service import _MODEL_PATH as CHAT_PATH
from services.chat_summarization_service import summarize_chat
from services.delay_predictor_service import _MODEL_PATH as DELAY_PATH
from services.delay_predictor_service import predict_delay_probability
from services.ml_artifacts import (
    ModelArtifactError,
    is_git_lfs_pointer,
    require_joblib_artifact,
)
from services.profile_rating_service import _MODEL_PATH as PROFILE_PATH
from services.profile_rating_service import predict_user_rating
from services.task_pipeline_service import (
    _ASSIGNMENT_FEATURES_PATH,
    _ASSIGNMENT_MODEL_PATH,
    assign_best_members,
)

_SKLEARN_PATHS = {
    "task_assignment": [_ASSIGNMENT_MODEL_PATH, _ASSIGNMENT_FEATURES_PATH],
    "delay_predictor": [DELAY_PATH],
    "profile_rating": [PROFILE_PATH],
    "chat_summarization": [CHAT_PATH],
    "security_anomaly": [SECURITY_PATH],
}


def _sklearn_weights_ready() -> bool:
    try:
        for paths in _SKLEARN_PATHS.values():
            for path in paths:
                require_joblib_artifact(path, path)
        return True
    except ModelArtifactError:
        return False


def test_lfs_pointer_helper_rejects_missing(tmp_path):
    missing = tmp_path / "nope.pkl"
    with pytest.raises(ModelArtifactError):
        require_joblib_artifact(str(missing), "nope")


def test_lfs_pointer_helper_rejects_pointer(tmp_path):
    pointer = tmp_path / "model.pkl"
    pointer.write_bytes(
        b"version https://git-lfs.github.com/spec/v1\n"
        b"oid sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        b"size 1\n"
    )
    assert is_git_lfs_pointer(str(pointer)) is True
    with pytest.raises(ModelArtifactError, match="Git LFS pointer"):
        require_joblib_artifact(str(pointer), "model.pkl")


@pytest.mark.skipif(
    not _sklearn_weights_ready(),
    reason="sklearn Git LFS .pkl weights are not materialized",
)
def test_assignment_inference_uses_ml_model():
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
    assert ranked
    assert all(row.get("score_source") == "ml_model" for row in ranked)
    assert ranked[0]["id"] == 1
    assert ranked[0]["score"] > ranked[1]["score"]


@pytest.mark.skipif(
    not _sklearn_weights_ready(),
    reason="sklearn Git LFS .pkl weights are not materialized",
)
def test_delay_inference_uses_ml_model():
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
    assert result["source"] == "ml_model"
    assert result["model_available"] is True
    assert result["delay_probability"] is not None


@pytest.mark.skipif(
    not _sklearn_weights_ready(),
    reason="sklearn Git LFS .pkl weights are not materialized",
)
def test_profile_rating_inference_uses_ml_model():
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
    assert result["source"] == "ml_model"
    assert 0.0 <= result["predicted_rating"] <= 5.0


@pytest.mark.skipif(
    not _sklearn_weights_ready(),
    reason="sklearn Git LFS .pkl weights are not materialized",
)
def test_chat_summarization_inference_uses_ml_model():
    result = summarize_chat(
        "Alice: Let's ship the API today.\n"
        "Bob: I will write the tests this afternoon.",
        top_n=2,
    )
    assert result["source"] == "ml_model"
    assert "Alice" in result["participants"]
    assert result["key_points"]


@pytest.mark.skipif(
    not _sklearn_weights_ready(),
    reason="sklearn Git LFS .pkl weights are not materialized",
)
def test_security_inference_uses_ml_model():
    result = score_login_features({"user_id": 1, "failed_attempts": 0})
    assert result["source"] == "ml_model"
    assert result["model_available"] is True
    assert result["anomaly_score"] is not None


@pytest.mark.skipif(
    not _sklearn_weights_ready(),
    reason="sklearn Git LFS .pkl weights are not materialized",
)
@patch("services.system_settings_service.is_ai_enabled", return_value=True)
def test_models_status_reports_five_sklearn_real_models(_enabled):
    report = get_ai_models_status()
    by_id = {m["id"]: m for m in report["models"]}
    for model_id, paths in _SKLEARN_PATHS.items():
        model = by_id[model_id]
        assert model["mode"] == REAL_MODEL, model
        assert model["loaded"] is True
        assert model["inference_test"] is True
        assert model["error"] is None
        for path in paths:
            assert is_git_lfs_pointer(path) is False
    distilbert = by_id["task_category"]
    assert distilbert["mode"] != REAL_MODEL
    assert distilbert["inference_test"] is False
