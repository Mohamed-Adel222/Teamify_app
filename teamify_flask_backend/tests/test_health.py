"""
Tests for Health check endpoint (/api/health).
"""
from unittest.mock import patch, MagicMock
import pytest


class TestHealth:
    URL = "/api/health"

    @patch("app.db")
    def test_healthy_200(self, m_db, client):
        m_db.session.execute.return_value = True
        r = client.get(self.URL)
        assert r.status_code == 200
        d = r.get_json()
        assert d["status"] == "ok"
        assert "video_meetings" in d
        assert isinstance(d["video_meetings"], bool)

    @patch("app.db")
    def test_db_down_503(self, m_db, client):
        m_db.session.execute.side_effect = Exception("DB down")
        r = client.get(self.URL)
        assert r.status_code == 503
        d = r.get_json()
        assert d["database"] == "error"
        assert "video_meetings" in d

    def test_no_auth_required(self, client):
        """Health endpoint should be accessible without authentication."""
        r = client.get(self.URL)
        assert r.status_code in (200, 503)  # either healthy or degraded, but not 401
