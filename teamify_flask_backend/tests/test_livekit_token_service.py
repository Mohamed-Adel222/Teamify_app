"""Unit tests for LiveKit env loading and URL normalization."""
from __future__ import annotations

from services.livekit_token_service import (
    livekit_api_key,
    livekit_api_secret,
    livekit_configured,
    livekit_http_url,
    livekit_url,
    normalize_livekit_url,
)


def test_normalize_https_and_bare_host():
    assert (
        normalize_livekit_url("https://example.livekit.cloud/")
        == "wss://example.livekit.cloud"
    )
    assert normalize_livekit_url("http://localhost:7880") == "ws://localhost:7880"
    assert (
        normalize_livekit_url("wss://example.livekit.cloud")
        == "wss://example.livekit.cloud"
    )
    assert (
        normalize_livekit_url("example.livekit.cloud")
        == "wss://example.livekit.cloud"
    )
    assert normalize_livekit_url("") == ""


def test_quoted_and_alias_env(monkeypatch):
    monkeypatch.delenv("LIVEKIT_URL", raising=False)
    monkeypatch.delenv("LIVEKIT_API_KEY", raising=False)
    monkeypatch.delenv("LIVEKIT_API_SECRET", raising=False)
    monkeypatch.setenv("LIVEKIT_HOST", '"https://example.livekit.cloud"')
    monkeypatch.setenv("LIVEKIT_KEY", "'devkey'")
    monkeypatch.setenv("LIVEKIT_SECRET", "secretsecretsecretsecret")

    assert livekit_url() == "wss://example.livekit.cloud"
    assert livekit_http_url() == "https://example.livekit.cloud"
    assert livekit_api_key() == "devkey"
    assert livekit_api_secret() == "secretsecretsecretsecret"
    assert livekit_configured() is True


def test_missing_livekit_env(monkeypatch):
    for name in (
        "LIVEKIT_URL",
        "LIVEKIT_HOST",
        "LIVEKIT_API_KEY",
        "LIVEKIT_KEY",
        "LIVEKIT_API_SECRET",
        "LIVEKIT_SECRET",
    ):
        monkeypatch.delenv(name, raising=False)
    assert livekit_configured() is False
    assert livekit_url() == ""
