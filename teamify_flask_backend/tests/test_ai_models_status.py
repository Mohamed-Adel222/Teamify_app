"""Runtime AI model status: file ≠ loaded; REAL_MODEL requires inference."""
from unittest.mock import patch

from services.ai_models_status_service import (
    FALLBACK,
    REAL_MODEL,
    check_dependencies,
    finalize_probe,
    find_secret_leaks,
    get_ai_models_status,
    run_probe,
)


def _base(**overrides):
    payload = dict(
        model_id="task_category",
        name="DistilBERT task category",
        description="classifier",
        endpoint="POST /api/ai/classify-task",
        path="ml_models/model1_category/model.safetensors",
        file_exists=True,
        dependencies_ok=True,
        loaded=False,
        inference_test=False,
        error=None,
    )
    payload.update(overrides)
    return finalize_probe(**payload)


def test_file_exists_does_not_mean_loaded():
    result = _base(file_exists=True, loaded=False, inference_test=False, error="not loaded")
    assert result["file_exists"] is True
    assert result["loaded"] is False
    assert result["mode"] == FALLBACK
    assert result["status"] == "fallback"


def test_missing_dependencies_result_in_fallback():
    result = _base(
        file_exists=True,
        dependencies_ok=False,
        loaded=False,
        inference_test=False,
        error="No module named 'torch'",
    )
    assert result["mode"] == FALLBACK
    assert result["status"] == "fallback"
    assert result["error"] == "No module named 'torch'"
    assert result["inference_test"] is False


def test_failed_load_results_in_fallback():
    result = _base(
        file_exists=True,
        dependencies_ok=True,
        loaded=False,
        inference_test=False,
        error="Failed to load model into memory",
    )
    assert result["mode"] == FALLBACK
    assert result["loaded"] is False
    assert result["status"] == "fallback"


def test_successful_load_and_inference_is_real_model():
    result = _base(
        file_exists=True,
        dependencies_ok=True,
        loaded=True,
        inference_test=True,
        error=None,
    )
    assert result["mode"] == REAL_MODEL
    assert result["status"] == "loaded"
    assert result["loaded"] is True
    assert result["inference_test"] is True
    assert result["error"] is None


def test_failed_inference_is_not_real_model():
    result = _base(
        file_exists=True,
        dependencies_ok=True,
        loaded=True,
        inference_test=False,
        error="Inference test failed: boom",
    )
    assert result["mode"] == FALLBACK
    assert result["loaded"] is True
    assert result["inference_test"] is False
    assert result["status"] == "error"
    assert result["mode"] != REAL_MODEL


def test_run_probe_missing_deps_skips_load():
    load_calls = []

    def load():
        load_calls.append(1)
        return True

    with patch(
        "services.ai_models_status_service.check_dependencies",
        return_value=(False, "No module named 'torch'"),
    ), patch("os.path.exists", return_value=True):
        result = run_probe(
            model_id="task_category",
            name="DistilBERT task category",
            description="x",
            endpoint="POST /api/ai/classify-task",
            file_paths=["/tmp/model.safetensors"],
            dependencies=["torch"],
            load_fn=load,
            infer_fn=lambda: True,
        )
    assert load_calls == []
    assert result["mode"] == FALLBACK
    assert result["loaded"] is False
    assert result["error"] == "No module named 'torch'"


def test_run_probe_inference_failure_not_real_model():
    with patch("os.path.exists", return_value=True), patch(
        "services.ai_models_status_service.check_dependencies",
        return_value=(True, None),
    ):
        result = run_probe(
            model_id="delay_predictor",
            name="Delay Predictor",
            description="x",
            endpoint="POST /api/ai/delay",
            file_paths=["/tmp/Delay_Predictor.pkl"],
            dependencies=["joblib"],
            load_fn=lambda: True,
            infer_fn=lambda: (_ for _ in ()).throw(RuntimeError("bad input shape")),
        )
    assert result["loaded"] is True
    assert result["inference_test"] is False
    assert result["mode"] == FALLBACK
    assert "bad input shape" in result["error"]


def test_run_probe_success_real_model():
    with patch("os.path.exists", return_value=True), patch(
        "services.ai_models_status_service.check_dependencies",
        return_value=(True, None),
    ):
        result = run_probe(
            model_id="security_anomaly",
            name="Security IsolationForest",
            description="x",
            endpoint="POST /api/ai/detect-anomaly",
            file_paths=["/tmp/security_model.pkl"],
            dependencies=["joblib"],
            load_fn=lambda: object(),
            infer_fn=lambda: True,
        )
    assert result["mode"] == REAL_MODEL
    assert result["status"] == "loaded"
    assert result["inference_test"] is True


@patch("services.ai_models_status_service._probe_cv_builder")
@patch("services.ai_models_status_service._probe_security")
@patch("services.ai_models_status_service._probe_summarization")
@patch("services.ai_models_status_service._probe_profile_rating")
@patch("services.ai_models_status_service._probe_delay")
@patch("services.ai_models_status_service._probe_assignment")
@patch("services.ai_models_status_service._probe_task_category")
def test_status_report_counts_and_hides_secrets(
    m_cat, m_asg, m_delay, m_rate, m_sum, m_sec, m_cv
):
    real = _base(loaded=True, inference_test=True)
    fallback = _base(
        model_id="delay_predictor",
        name="Delay Predictor",
        loaded=False,
        error="No module named 'joblib'",
        dependencies_ok=False,
    )
    m_cat.return_value = real
    m_asg.return_value = fallback
    m_delay.return_value = fallback
    m_rate.return_value = fallback
    m_sum.return_value = fallback
    m_sec.return_value = fallback
    m_cv.return_value = fallback

    report = get_ai_models_status()
    assert report["total"] == 7
    assert report["real_model_count"] == 1
    assert report["loaded_count"] == 1
    assert report["fallback_count"] == 6
    assert "environment" in report
    assert "packages" in report["environment"]
    assert find_secret_leaks(report) == []
    env_blob = str(report["environment"]).upper()
    for secret in ("JWT_SECRET", "DATABASE_URL", "ANTHROPIC_API_KEY", "PASSWORD"):
        assert secret not in env_blob


def test_check_dependencies_reports_missing_module():
    ok, err = check_dependencies(["definitely_not_a_real_module_xyz"])
    assert ok is False
    assert "No module named" in err


def test_find_secret_leaks_detects_credential_keys():
    assert find_secret_leaks({"jwt_secret_key": "abc"}) == ["jwt_secret_key"]
    leaks = find_secret_leaks({"database_url": "postgres://x"})
    assert "database_url" in leaks
    assert find_secret_leaks({"python_version": "3.12"}) == []


def test_live_status_file_exists_is_not_loaded_and_hides_secrets():
    with patch(
        "services.system_settings_service.is_ai_enabled", return_value=True
    ):
        report = get_ai_models_status()
    assert find_secret_leaks(report) == []
    blob = str(report).upper()
    for secret in ("JWT_SECRET", "DATABASE_URL", "ANTHROPIC_API_KEY"):
        assert secret not in blob
    assert "environment" in report
    assert "packages" in report["environment"]
    assert len(report["models"]) == 7
    for model in report["models"]:
        if model["file_exists"] and not model["dependencies_ok"]:
            assert model["loaded"] is False
            assert model["mode"] == FALLBACK
        if not model["inference_test"]:
            assert model["mode"] != REAL_MODEL
        if model["mode"] == REAL_MODEL:
            assert model["file_exists"] is True
            assert model["dependencies_ok"] is True
            assert model["loaded"] is True
            assert model["inference_test"] is True
            assert model["error"] is None


def test_cv_status_probe_does_not_clobber_reportlab():
    from reportlab.platypus import ListFlowable

    with patch(
        "services.system_settings_service.is_ai_enabled", return_value=True
    ):
        get_ai_models_status()
    from reportlab.platypus import ListFlowable as again

    assert again is ListFlowable
    assert getattr(again, "__module__", "").startswith("reportlab")
