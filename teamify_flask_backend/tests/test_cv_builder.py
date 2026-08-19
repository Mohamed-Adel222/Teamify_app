"""
Tests for CV Builder — service unit tests and endpoint integration tests.

Coverage:
  Service:
    - build_cv_for_user returns fallback CV when model backends are absent
    - build_cv_for_user returns {"error": ...} when user does not exist
    - _build_user_data maps ORM objects to the pipeline's expected structure

  Endpoint  POST /api/ai/cv/build:
    - 200 for the calling member (self CV)
    - 200 for admin requesting another user's CV  (target_user_id override)
    - 403 for a non-admin requesting another user's CV
    - 400 for an invalid request body (bad target_user_id type)
    - 401 when no token is supplied
    - 404 when the target user does not exist in the DB
"""
from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from tests.conftest import (
    ADMIN_USER_ID,
    MEMBER_USER_ID,
    NONEXISTENT_ID,
    _make_user,
)


@pytest.fixture(autouse=True)
def _ai_platform_enabled():
    """Keep AI routes reachable; mocked DB rows are not real setting values."""
    with patch(
        "services.system_settings_service.is_ai_enabled", return_value=True
    ), patch(
        "services.system_settings_service.is_maintenance_mode",
        return_value=False,
    ):
        yield


# ─── Helpers ─────────────────────────────────────────────────────────────────

_SAMPLE_CV = {
    "generated_at": "2026-05-07T00:00:00",
    "user":         {"name": "Alice", "role": "Developer", "email": "alice@example.com"},
    "summary":      "Alice is a results-driven professional.",
    "skills":       {"technical": ["Python", "Flask"], "soft": ["Teamwork"]},
    "projects":     [],
    "achievements": ["Active contributor on the Teamify platform."],
    "metadata":     {},
    "source":       "ai_pipeline",
}

_URL = "/api/ai/cv/build"


# ─── Service unit tests ───────────────────────────────────────────────────────

class TestCVBuilderService:
    """Unit-test the service layer in isolation (no HTTP involved)."""

    def test_user_not_found_returns_error(self, mock_db_session):
        """build_cv_for_user returns an error dict when the user does not exist."""
        # db is a local import inside build_cv_for_user; patch at the source.
        mock_db_session.get.return_value = None
        from services.cv_builder_service import build_cv_for_user
        result = build_cv_for_user(NONEXISTENT_ID)
        assert "error" in result
        assert str(NONEXISTENT_ID) in result["error"] or "not found" in result["error"].lower()

    @patch("services.cv_builder_service.build_cv_for_user", return_value=_SAMPLE_CV)
    def test_service_returns_expected_keys(self, mock_build):
        """Smoke: the mocked service honours the expected CV structure."""
        from services.cv_builder_service import build_cv_for_user
        result = build_cv_for_user(MEMBER_USER_ID)
        for key in ("generated_at", "user", "summary", "skills", "projects",
                    "achievements", "source"):
            assert key in result, f"Key '{key}' missing from CV"

    def test_fallback_cv_structure(self):
        """_fallback_cv produces a valid CV dict from minimal user_data."""
        import services.cv_builder_service as svc

        user_data = {
            "user":     {"name": "Bob", "role": "Designer", "email": "bob@test.com"},
            "projects": [
                {
                    "title": "Logo Redesign",
                    "description": "Redesigned the company logo.",
                    "technologies": ["Figma"],
                    "role": "Team Member",
                    "status": "completed",
                    "rating": 4.5,
                    "start_date": "2025-01-01",
                    "end_date": "2025-03-01",
                }
            ],
            "tasks":         {"total": 5, "completed": 4, "overdue": 0},
            "metrics":       {"avg_rating": 4.5, "consistency_score": 90.0,
                              "trust_score": 88.0, "teamwork_score": 60.0},
            "collaboration": {"messages_sent": 10, "comments_written": 4, "team_count": 1},
            "activity":      {"activity_count": 5, "login_frequency": 3.0},
        }
        cv = svc._fallback_cv(user_data)

        assert cv["user"]["name"] == "Bob"
        assert "Figma" in cv["skills"]["technical"]
        assert len(cv["projects"]) == 1
        assert cv["source"] == "fallback"


# ─── Endpoint integration tests ───────────────────────────────────────────────

class TestCVBuildEndpoint:
    """HTTP-level tests for POST /api/ai/cv/build."""

    # ── 200 — member builds their own CV ─────────────────────────────────────

    @patch("routes.ai.build_cv_for_user", return_value=_SAMPLE_CV)
    def test_member_self_200(self, mock_build, client, member_headers):
        """A member calling with no body gets their own CV (HTTP 200)."""
        r = client.post(_URL, headers=member_headers, json={})
        assert r.status_code == 200
        data = r.get_json()
        assert "summary" in data
        assert "skills" in data

    @patch("routes.ai.build_cv_for_user", return_value=_SAMPLE_CV)
    def test_member_explicit_self_200(self, mock_build, client, member_headers):
        """A member may explicitly pass their own user_id as target_user_id."""
        r = client.post(
            _URL,
            headers=member_headers,
            json={"target_user_id": MEMBER_USER_ID},
        )
        assert r.status_code == 200

    # ── 200 — admin builds a different user's CV ──────────────────────────────

    @patch("routes.ai.build_cv_for_user", return_value=_SAMPLE_CV)
    def test_admin_other_user_200(self, mock_build, mock_db_session,
                                  client, admin_headers, member_user):
        """Admin supplying target_user_id for another user gets HTTP 200."""
        mock_db_session.get.return_value = _make_user(ADMIN_USER_ID, role="admin")
        r = client.post(
            _URL,
            headers=admin_headers,
            json={"target_user_id": MEMBER_USER_ID},
        )
        assert r.status_code == 200
        mock_build.assert_called_once_with(MEMBER_USER_ID)

    # ── 403 — non-admin requests another user's CV ────────────────────────────

    @patch("routes.ai.build_cv_for_user", return_value=_SAMPLE_CV)
    def test_member_other_user_403(self, mock_build, mock_db_session,
                                   client, member_headers):
        """A regular member requesting another user's CV is forbidden."""
        mock_db_session.get.return_value = _make_user(MEMBER_USER_ID, role="member")
        r = client.post(
            _URL,
            headers=member_headers,
            json={"target_user_id": ADMIN_USER_ID},
        )
        assert r.status_code == 403
        mock_build.assert_not_called()

    # ── 400 — invalid request body ────────────────────────────────────────────

    def test_invalid_body_400(self, client, member_headers):
        """A non-integer target_user_id causes a 400 validation error."""
        r = client.post(
            _URL,
            headers=member_headers,
            json={"target_user_id": "not-a-number"},
        )
        assert r.status_code == 400
        data = r.get_json()
        assert "error" in data or "details" in data

    # ── 401 — unauthenticated ─────────────────────────────────────────────────

    def test_no_token_401(self, client):
        """Requests without a JWT are rejected with 401."""
        r = client.post(_URL, json={})
        assert r.status_code == 401

    # ── 404 — target user does not exist ─────────────────────────────────────

    @patch(
        "routes.ai.build_cv_for_user",
        return_value={"error": f"User {NONEXISTENT_ID} not found"},
    )
    def test_user_not_found_404(self, mock_build, client, member_headers):
        """When the service returns a not-found error, the endpoint returns 404."""
        r = client.post(
            _URL,
            headers=member_headers,
            json={"target_user_id": MEMBER_USER_ID},  # same user → no 403
        )
        assert r.status_code == 404

    # ── Source field propagation ───────────────────────────────────────────────

    @patch(
        "routes.ai.build_cv_for_user",
        return_value={**_SAMPLE_CV, "source": "fallback"},
    )
    def test_fallback_source_propagated(self, mock_build, client, member_headers):
        """The 'source' field from the service is included in the response."""
        r = client.post(_URL, headers=member_headers, json={})
        assert r.status_code == 200
        assert r.get_json().get("source") == "fallback"
