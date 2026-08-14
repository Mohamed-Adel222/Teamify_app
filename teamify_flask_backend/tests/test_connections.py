"""Tests for /api/connections/<id>."""
from unittest.mock import MagicMock, patch

from tests.conftest import MEMBER_USER_ID, MEMBER2_USER_ID, GUEST_USER_ID


def _connection(cid=11, requester=MEMBER2_USER_ID, addressee=MEMBER_USER_ID, status="pending"):
    conn = MagicMock()
    conn.id = cid
    conn.requester_id = requester
    conn.addressee_id = addressee
    conn.status = status
    conn.STATUS_ACCEPTED = "accepted"
    conn.STATUS_PENDING = "pending"
    conn.STATUS_DECLINED = "declined"
    conn.to_dict.return_value = {
        "id": cid,
        "requester_id": requester,
        "addressee_id": addressee,
        "status": status,
    }
    return conn


class TestGetConnection:
    URL = "/api/connections/11"

    @patch("routes.connections.db")
    def test_addressee_200(self, m_db, client, member_headers):
        conn = _connection()
        m_db.session.get.return_value = conn
        r = client.get(self.URL, headers=member_headers)
        assert r.status_code == 200
        body = r.get_json()
        assert body["status"] == "pending_received"
        assert body["other_user_id"] == MEMBER2_USER_ID
        assert body["connection"]["id"] == 11

    @patch("routes.connections.db")
    def test_not_found_404(self, m_db, client, member_headers):
        m_db.session.get.return_value = None
        r = client.get(self.URL, headers=member_headers)
        assert r.status_code == 404

    @patch("routes.connections.db")
    def test_forbidden_403(self, m_db, client, member_headers):
        conn = _connection(requester=GUEST_USER_ID, addressee=MEMBER2_USER_ID)
        m_db.session.get.return_value = conn
        r = client.get(self.URL, headers=member_headers)
        assert r.status_code == 403

    def test_no_token_401(self, client):
        assert client.get(self.URL).status_code == 401
