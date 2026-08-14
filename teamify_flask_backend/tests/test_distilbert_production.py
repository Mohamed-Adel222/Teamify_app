"""DistilBERT is optional; production uses the keyword fallback by design."""
import os

from services.task_pipeline_service import (
    DISTILBERT_DISABLED_REASON,
    classify_task,
    distilbert_enabled,
    is_usable_weight_file,
    reset_category_model_cache,
    startup_check,
    _load_category_model,
)


def test_distilbert_disabled_by_default(monkeypatch):
    monkeypatch.delenv("AI_ENABLE_DISTILBERT", raising=False)
    assert distilbert_enabled() is False


def test_lfs_pointer_is_not_a_usable_weight(tmp_path):
    pointer = tmp_path / "model.safetensors"
    pointer.write_bytes(
        b"version https://git-lfs.github.com/spec/v1\n"
        b"oid sha256:8d537d226e3a3eab071dfcfb743abd75fb8c4216efdccfbbc676ec30cceb61b4\n"
        b"size 267866404\n"
    )
    assert is_usable_weight_file(str(pointer)) is False
    assert is_usable_weight_file(str(tmp_path / "missing.bin")) is False


def test_tiny_non_lfs_file_is_not_usable(tmp_path):
    blob = tmp_path / "model.safetensors"
    blob.write_bytes(b"not a real distilbert checkpoint")
    assert is_usable_weight_file(str(blob)) is False


def test_classify_task_uses_keyword_fallback_when_disabled(monkeypatch):
    monkeypatch.setenv("AI_ENABLE_DISTILBERT", "false")
    reset_category_model_cache()
    result = classify_task("Build a Flask REST API endpoint with JWT")
    assert result["source"] == "keyword_fallback"
    assert result["category"] == "backend"
    assert "Python" in result["required_skills"]


def test_load_records_intentional_production_reason(monkeypatch):
    monkeypatch.setenv("AI_ENABLE_DISTILBERT", "false")
    reset_category_model_cache()
    model, tokenizer, le = _load_category_model()
    assert model is None and tokenizer is None and le is None
    from services import task_pipeline_service as tps

    assert tps._cat_load_error == DISTILBERT_DISABLED_REASON
    assert "not used in production" in tps._cat_load_error


def test_startup_check_does_not_load_when_disabled(monkeypatch):
    monkeypatch.setenv("AI_ENABLE_DISTILBERT", "false")
    reset_category_model_cache()
    startup_check()
    from services import task_pipeline_service as tps

    assert tps._cat_model_cache is None
    assert tps._cat_load_error is None


def test_enabled_but_lfs_pointer_stays_on_fallback(monkeypatch, tmp_path):
    pointer = tmp_path / "model.safetensors"
    pointer.write_bytes(
        b"version https://git-lfs.github.com/spec/v1\n"
        b"oid sha256:abc\nsize 267866404\n"
    )
    monkeypatch.setenv("AI_ENABLE_DISTILBERT", "true")
    monkeypatch.setattr(
        "services.task_pipeline_service.category_weight_candidates",
        lambda: [str(pointer)],
    )
    reset_category_model_cache()
    model, tokenizer, _le = _load_category_model()
    assert model is None and tokenizer is None
    from services import task_pipeline_service as tps

    assert tps._cat_load_error is not None
    assert "LFS" in tps._cat_load_error
    result = classify_task("Write pytest coverage for the API")
    assert result["source"] == "keyword_fallback"
    assert result["category"] == "testing"


def test_requirements_deploy_does_not_install_torch():
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    text = open(os.path.join(root, "requirements-deploy.txt"), encoding="utf-8").read()
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        assert not stripped.lower().startswith("torch")
        assert not stripped.lower().startswith("transformers")
    assert "not required" in text.lower() or "keyword fallback" in text.lower()
