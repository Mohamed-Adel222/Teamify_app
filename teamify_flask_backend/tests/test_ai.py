"""
Tests for AI blueprint (/api/ai/*).
Endpoints: POST /assign, POST /suggest-priority, POST /suggest-deadline, POST /delay, GET /workload
"""
from unittest.mock import patch, MagicMock
import pytest
from tests.conftest import (
    ADMIN_USER_ID, MEMBER_USER_ID, GUEST_USER_ID,
    PROJECT_ID, TASK_ID, NONEXISTENT_ID,
    _make_user, _make_project, _make_task,
)


class TestAIAssign:
    URL = "/api/ai/assign"

    @patch("routes.ai.auto_assign")
    @patch("routes.ai.get_project_role")
    @patch("routes.ai.Project")
    def test_owner_200(self, m_proj, m_role, m_assign, client, member_headers):
        m_proj.query.get.return_value = _make_project()
        m_role.return_value = "owner"
        m_assign.return_value = (MEMBER_USER_ID, "least busy")
        r = client.post(self.URL, headers=member_headers, json={"project_id": str(PROJECT_ID)})
        assert r.status_code == 200 and "suggested_user_id" in r.get_json()

    @patch("routes.ai.get_project_role")
    @patch("routes.ai.Project")
    def test_member_forbidden_403(self, m_proj, m_role, client, member_headers):
        m_proj.query.get.return_value = _make_project()
        m_role.return_value = "member"
        assert client.post(self.URL, headers=member_headers, json={"project_id": str(PROJECT_ID)}).status_code == 403

    @patch("routes.ai.get_project_role")
    @patch("routes.ai.Project")
    def test_guest_forbidden_403(self, m_proj, m_role, client, guest_headers):
        m_proj.query.get.return_value = _make_project()
        m_role.return_value = "guest"
        assert client.post(self.URL, headers=guest_headers, json={"project_id": str(PROJECT_ID)}).status_code == 403

    def test_missing_project_id_400(self, client, member_headers):
        assert client.post(self.URL, headers=member_headers, json={}).status_code == 400

    @patch("routes.ai.Project")
    def test_project_not_found_404(self, m_proj, client, member_headers):
        m_proj.query.get.return_value = None
        assert client.post(self.URL, headers=member_headers, json={"project_id": str(NONEXISTENT_ID)}).status_code == 404

    def test_no_token_401(self, client):
        assert client.post(self.URL, json={"project_id": str(PROJECT_ID)}).status_code == 401


class TestAISuggestPriority:
    URL = "/api/ai/suggest-priority"

    @patch("routes.ai.suggest_priority")
    @patch("routes.ai.get_project_role")
    def test_member_200(self, m_role, m_sp, client, member_headers):
        m_role.return_value = "member"
        m_sp.return_value = ("high", ["urgent keyword"])
        r = client.post(self.URL, headers=member_headers, json={"project_id": str(PROJECT_ID), "title": "Fix bug"})
        assert r.status_code == 200

    @patch("routes.ai.get_project_role")
    def test_non_member_403(self, m_role, client, member_headers):
        m_role.return_value = None
        assert client.post(self.URL, headers=member_headers, json={"project_id": str(PROJECT_ID)}).status_code == 403

    def test_missing_project_id_400(self, client, member_headers):
        assert client.post(self.URL, headers=member_headers, json={}).status_code == 400

    def test_no_token_401(self, client):
        assert client.post(self.URL, json={"project_id": str(PROJECT_ID)}).status_code == 401


class TestAISuggestDeadline:
    URL = "/api/ai/suggest-deadline"

    @patch("routes.ai.suggest_deadline")
    @patch("routes.ai.get_project_role")
    def test_member_200(self, m_role, m_sd, client, member_headers):
        m_role.return_value = "member"
        m_sd.return_value = ("2026-05-01", ["based on priority"])
        assert client.post(self.URL, headers=member_headers, json={"project_id": str(PROJECT_ID)}).status_code == 200

    @patch("routes.ai.get_project_role")
    def test_non_member_403(self, m_role, client, member_headers):
        m_role.return_value = None
        assert client.post(self.URL, headers=member_headers, json={"project_id": str(PROJECT_ID)}).status_code == 403

    def test_no_token_401(self, client):
        assert client.post(self.URL, json={"project_id": str(PROJECT_ID)}).status_code == 401


class TestAIDelay:
    URL = "/api/ai/delay"

    @patch("routes.ai.predict_delay")
    @patch("routes.ai.get_project_role")
    @patch("routes.ai.Task")
    def test_by_task_200(self, m_task, m_role, m_delay, client, member_headers):
        m_task.query.get.return_value = _make_task()
        m_role.return_value = "member"
        m_delay.return_value = {"risk_level": "low", "reasons": []}
        r = client.post(self.URL, headers=member_headers, json={"task_id": str(TASK_ID)})
        assert r.status_code == 200

    def test_missing_ids_400(self, client, member_headers):
        assert client.post(self.URL, headers=member_headers, json={}).status_code == 400

    def test_no_token_401(self, client):
        assert client.post(self.URL, json={"project_id": str(PROJECT_ID)}).status_code == 401


class TestAIWorkload:
    URL = "/api/ai/workload"

    @patch("routes.ai.calculate_workload")
    def test_own_workload_200(self, m_wl, client, member_headers, mock_db_session):
        mock_db_session.get.return_value = _make_user(MEMBER_USER_ID)
        m_wl.return_value = {"total_tasks": 3, "pending": 1}
        r = client.get(self.URL, headers=member_headers)
        assert r.status_code == 200

    def test_non_admin_other_user_403(self, client, member_headers, mock_db_session):
        mock_db_session.get.return_value = _make_user(MEMBER_USER_ID)
        assert client.get(f"{self.URL}?user_id={ADMIN_USER_ID}", headers=member_headers).status_code == 403

    def test_no_token_401(self, client):
        assert client.get(self.URL).status_code == 401


class TestAIModelsStatus:
    URL = "/api/ai/models/status"

    @pytest.fixture(autouse=True)
    def _platform_available(self):
        with patch(
            "services.system_settings_service.is_ai_enabled", return_value=True
        ), patch(
            "services.system_settings_service.is_maintenance_mode",
            return_value=False,
        ):
            yield

    def test_no_token_401(self, client):
        assert client.get(self.URL).status_code == 401

    @patch("services.ai_models_status_service.get_ai_models_status")
    def test_member_200(self, m_status, client, member_headers):
        m_status.return_value = {
            "models": [
                {
                    "id": "delay_predictor",
                    "name": "Delay Predictor",
                    "file_exists": True,
                    "dependencies_ok": False,
                    "loaded": False,
                    "inference_test": False,
                    "mode": "FALLBACK",
                    "status": "fallback",
                    "error": "No module named 'joblib'",
                    "endpoint": "POST /api/ai/delay",
                }
            ],
            "total": 1,
            "real_model_count": 0,
            "fallback_count": 1,
            "error_count": 0,
            "loaded_count": 0,
            "linked_count": 1,
            "environment": {"python_version": "3.12", "packages": {}},
        }
        r = client.get(self.URL, headers=member_headers)
        assert r.status_code == 200
        body = r.get_json()
        assert body["models"][0]["mode"] == "FALLBACK"
        assert body["models"][0]["loaded"] is False
        blob = str(body).upper()
        assert "JWT_SECRET" not in blob
        assert "DATABASE_URL" not in blob
        assert "ANTHROPIC_API_KEY" not in blob

    @patch("routes.ai.classify_task")
    def test_classify_task_still_works_with_fallback(
        self, m_cls, client, member_headers
    ):
        m_cls.return_value = {
            "category": "backend",
            "difficulty": "medium",
            "required_skills": ["Python"],
            "source": "keyword_fallback",
        }
        r = client.post(
            "/api/ai/classify-task",
            headers=member_headers,
            json={"text": "Build a Flask API"},
        )
        assert r.status_code == 200
        assert r.get_json()["source"] == "keyword_fallback"

    def test_live_status_contract_and_no_secrets(self, client, member_headers):
        r = client.get(self.URL, headers=member_headers)
        assert r.status_code == 200
        body = r.get_json()
        assert "models" in body
        assert "environment" in body
        blob = str(body).upper()
        assert "JWT_SECRET" not in blob
        assert "DATABASE_URL" not in blob
        assert "ANTHROPIC_API_KEY" not in blob
        for model in body["models"]:
            for key in (
                "name",
                "file_exists",
                "dependencies_ok",
                "loaded",
                "inference_test",
                "mode",
                "status",
                "error",
                "path",
            ):
                assert key in model
            if model["mode"] == "REAL_MODEL":
                assert model["file_exists"] is True
                assert model["dependencies_ok"] is True
                assert model["loaded"] is True
                assert model["inference_test"] is True
