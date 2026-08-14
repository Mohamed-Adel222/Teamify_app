"""Unit tests for the aggregated AI model status report."""
from unittest.mock import patch

from services.ai_models_status_service import get_ai_models_status


def _ok(path="ml_models/example.pkl"):
    return {
        "file_present": True,
        "loaded": True,
        "error": None,
        "path": path,
        "model_available": True,
        "model_path": path,
    }


def _missing(path="ml_models/missing.pkl"):
    return {
        "file_present": False,
        "loaded": False,
        "error": "not found",
        "path": path,
        "model_available": False,
        "model_path": path,
    }


@patch("services.ai_models_status_service.get_cv_builder_status", return_value=_ok())
@patch("services.ai_models_status_service.get_security_model_status", return_value=_ok())
@patch("services.ai_models_status_service.get_chat_summarization_model_status", return_value=_ok())
@patch("services.ai_models_status_service.get_profile_rating_model_status", return_value=_ok())
@patch("services.ai_models_status_service.get_delay_model_status", return_value=_ok())
@patch("services.ai_models_status_service.get_assignment_model_status", return_value=_ok())
@patch("services.ai_models_status_service.get_category_model_status", return_value=_missing())
def test_models_status_counts_unlinked_category(*_mocks):
    report = get_ai_models_status()
    assert report["total"] == 7
    assert report["linked_count"] == 6
    assert report["loaded_count"] == 6
    assert report["all_linked"] is False
    by_id = {m["id"]: m for m in report["models"]}
    assert by_id["task_category"]["linked"] is False
    assert by_id["delay_predictor"]["linked"] is True
    assert by_id["delay_predictor"]["endpoint"] == "POST /api/ai/delay"
