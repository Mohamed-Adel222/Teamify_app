"""Integration tests for direct chat rooms and LiveKit meeting APIs."""
from __future__ import annotations

from datetime import timedelta

import pytest
from flask_jwt_extended import create_access_token

from models import db
from models.chat import ChatRoom, ChatRoomMember
from models.user import User


@pytest.fixture()
def chat_meeting_app():
    from app import create_app

    app = create_app(
        test_config={
            "TESTING": True,
            "SQLALCHEMY_DATABASE_URI": "sqlite:///:memory:",
            "JWT_SECRET_KEY": "chat-meeting-test-secret",
            "RATELIMIT_ENABLED": False,
        }
    )
    with app.app_context():
        db.create_all()
        host = User(
            display_name="host_user",
            email="host@test.com",
            password="x",
            role="member",
            user_type="freelancer",
            full_name="Host User",
            account_status="approved",
        )
        peer = User(
            display_name="peer_user",
            email="peer@test.com",
            password="x",
            role="member",
            user_type="freelancer",
            full_name="Peer User",
            account_status="approved",
        )
        outsider = User(
            display_name="outsider_user",
            email="outsider@test.com",
            password="x",
            role="member",
            user_type="freelancer",
            full_name="Outsider User",
            account_status="approved",
        )
        db.session.add_all([host, peer, outsider])
        db.session.flush()
        room = ChatRoom(name="Project Chat", is_group=True)
        db.session.add(room)
        db.session.flush()
        db.session.add(ChatRoomMember(room_id=room.id, user_id=host.id))
        db.session.add(ChatRoomMember(room_id=room.id, user_id=peer.id))
        db.session.commit()
        yield app, host.id, peer.id, outsider.id, room.id
        db.drop_all()


def _headers(app, user_id):
    with app.app_context():
        token = create_access_token(identity=str(user_id))
    return {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}


@pytest.mark.integration
def test_direct_room_find_or_create_and_dedup(chat_meeting_app):
    app, host_id, peer_id, _, _ = chat_meeting_app
    with app.test_client() as client:
        first = client.post(
            "/api/chat/direct",
            headers=_headers(app, host_id),
            json={"user_id": peer_id},
        )
        assert first.status_code == 200
        room = first.get_json()["room"]
        assert isinstance(room["id"], int)
        assert room["is_group"] is False

        second = client.post(
            "/api/chat/direct",
            headers=_headers(app, peer_id),
            json={"user_id": host_id},
        )
        assert second.status_code == 200
        assert second.get_json()["room"]["id"] == room["id"]


@pytest.mark.integration
def test_direct_room_cannot_message_self(chat_meeting_app):
    app, host_id, _, _, _ = chat_meeting_app
    with app.test_client() as client:
        res = client.post(
            "/api/chat/direct",
            headers=_headers(app, host_id),
            json={"user_id": host_id},
        )
        assert res.status_code == 403


@pytest.mark.integration
def test_send_message_rest_and_idempotency(chat_meeting_app):
    app, host_id, _, _, room_id = chat_meeting_app
    with app.test_client() as client:
        headers = _headers(app, host_id)
        payload = {
            "content": "hello team",
            "message_type": "text",
            "idempotency_key": "same-key-123",
        }
        first = client.post(
            f"/api/chat/rooms/{room_id}/messages",
            headers=headers,
            json=payload,
        )
        assert first.status_code in (200, 201)
        first_id = first.get_json()["data"]["id"]

        second = client.post(
            f"/api/chat/rooms/{room_id}/messages",
            headers=headers,
            json=payload,
        )
        assert second.status_code in (200, 201)
        second_id = second.get_json()["data"]["id"]
        assert second_id == first_id


@pytest.mark.integration
def test_unauthorized_room_message(chat_meeting_app):
    app, _, _, outsider_id, room_id = chat_meeting_app
    with app.test_client() as client:
        res = client.post(
            f"/api/chat/rooms/{room_id}/messages",
            headers=_headers(app, outsider_id),
            json={"content": "nope"},
        )
        assert res.status_code in (403, 404)


@pytest.mark.integration
def test_create_meeting_and_authorization(chat_meeting_app):
    app, host_id, peer_id, outsider_id, room_id = chat_meeting_app
    with app.test_client() as client:
        created = client.post(
            "/api/meetings",
            headers=_headers(app, host_id),
            json={"chat_room_id": room_id, "title": "Standup"},
        )
        assert created.status_code in (200, 201)
        meeting = created.get_json()["meeting"]
        public_id = meeting["public_id"]
        assert public_id
        assert meeting["id"] != public_id
        assert meeting["provider"] == "livekit"

        again = client.post(
            "/api/meetings",
            headers=_headers(app, host_id),
            json={"chat_room_id": room_id, "title": "Standup"},
        )
        assert again.status_code in (200, 201)
        assert again.get_json()["meeting"]["public_id"] == public_id

        listed = client.get("/api/meetings", headers=_headers(app, host_id))
        assert listed.status_code == 200
        assert any(m["public_id"] == public_id for m in listed.get_json()["meetings"])

        got = client.get(f"/api/meetings/{public_id}", headers=_headers(app, peer_id))
        assert got.status_code == 200

        hidden = client.get(
            f"/api/meetings/{public_id}", headers=_headers(app, outsider_id)
        )
        assert hidden.status_code == 404

        token = client.post(
            f"/api/meetings/{public_id}/token",
            headers=_headers(app, outsider_id),
        )
        assert token.status_code == 404

        outsider_end = client.post(
            f"/api/meetings/{public_id}/end",
            headers=_headers(app, outsider_id),
        )
        assert outsider_end.status_code == 404

        missing = client.get(
            "/api/meetings/00000000-0000-0000-0000-000000000000",
            headers=_headers(app, host_id),
        )
        assert missing.status_code == 404


@pytest.mark.integration
def test_meeting_token_requires_livekit_config(chat_meeting_app, monkeypatch):
    app, host_id, _, _, room_id = chat_meeting_app
    monkeypatch.delenv("LIVEKIT_URL", raising=False)
    monkeypatch.delenv("LIVEKIT_API_KEY", raising=False)
    monkeypatch.delenv("LIVEKIT_API_SECRET", raising=False)
    with app.test_client() as client:
        created = client.post(
            "/api/meetings",
            headers=_headers(app, host_id),
            json={"chat_room_id": room_id},
        )
        public_id = created.get_json()["meeting"]["public_id"]
        token = client.post(
            f"/api/meetings/{public_id}/token",
            headers=_headers(app, host_id),
        )
        assert token.status_code == 503
        assert "LiveKit" in token.get_json()["error"]


@pytest.mark.integration
def test_meeting_token_and_host_end(chat_meeting_app, monkeypatch):
    app, host_id, peer_id, _, room_id = chat_meeting_app
    monkeypatch.setenv("LIVEKIT_URL", "wss://example.livekit.cloud")
    monkeypatch.setenv("LIVEKIT_API_KEY", "devkey")
    monkeypatch.setenv("LIVEKIT_API_SECRET", "secretsecretsecretsecret")
    deleted = []

    def _fake_delete(room_name):
        deleted.append(room_name)
        return True

    monkeypatch.setattr(
        "services.meeting_service.delete_livekit_room", _fake_delete
    )
    with app.test_client() as client:
        created = client.post(
            "/api/meetings",
            headers=_headers(app, host_id),
            json={"chat_room_id": room_id, "title": "Call"},
        )
        public_id = created.get_json()["meeting"]["public_id"]
        token = client.post(
            f"/api/meetings/{public_id}/token",
            headers=_headers(app, peer_id),
        )
        assert token.status_code == 200
        body = token.get_json()
        assert body["token"]
        assert body["url"].startswith("wss://")
        assert "API_SECRET" not in str(body)
        assert "secretsecretsecretsecret" not in str(body)
        import jwt

        decoded = jwt.decode(
            body["token"],
            "secretsecretsecretsecret",
            algorithms=["HS256"],
        )
        assert decoded["sub"] == str(peer_id)
        assert decoded["video"]["room"] == body["room"]
        assert decoded["video"]["roomJoin"] is True
        assert decoded["video"]["canPublish"] is True
        assert decoded["video"]["canSubscribe"] is True
        assert body["room"] == f"teamify_{public_id}"

        leave = client.post(
            f"/api/meetings/{public_id}/leave",
            headers=_headers(app, peer_id),
        )
        assert leave.status_code == 200

        forbidden_end = client.post(
            f"/api/meetings/{public_id}/end",
            headers=_headers(app, peer_id),
        )
        assert forbidden_end.status_code == 403

        ended = client.post(
            f"/api/meetings/{public_id}/end",
            headers=_headers(app, host_id),
        )
        assert ended.status_code == 200
        assert ended.get_json()["meeting"]["status"] == "ended"
        assert deleted == [body["room"]]


@pytest.mark.integration
def test_invalid_and_expired_jwt(chat_meeting_app):
    app, host_id, _, _, room_id = chat_meeting_app
    with app.test_client() as client:
        bad = client.get(
            "/api/meetings",
            headers={"Authorization": "Bearer not-a-jwt"},
        )
        assert bad.status_code in (401, 422)

        with app.app_context():
            expired = create_access_token(
                identity=str(host_id),
                expires_delta=timedelta(seconds=-30),
            )
        stale = client.post(
            "/api/meetings",
            headers={"Authorization": f"Bearer {expired}"},
            json={"chat_room_id": room_id},
        )
        assert stale.status_code in (401, 422)


@pytest.mark.integration
def test_meeting_does_not_attach_unrelated_room_session(chat_meeting_app):
    from models.meeting_session import MeetingSession

    app, host_id, _, _, room_id = chat_meeting_app
    with app.app_context():
        leftover = MeetingSession(
            room_id=room_id,
            started_by=host_id,
            is_active=True,
            transcript=[{"content": "SECRET FROM OLD CALL"}],
            participant_ids=[host_id],
        )
        db.session.add(leftover)
        db.session.commit()
        leftover_id = leftover.id

    with app.test_client() as client:
        headers = _headers(app, host_id)
        created = client.post(
            "/api/meetings",
            headers=headers,
            json={"chat_room_id": room_id, "title": "Fresh"},
        )
        public_id = created.get_json()["meeting"]["public_id"]
        meeting_pk = created.get_json()["meeting"]["id"]

        got = client.get(f"/api/meetings/{public_id}", headers=headers)
        assert got.status_code == 200
        assert got.get_json()["meeting"]["session"] is None

        start = client.post(
            f"/api/chat/rooms/{room_id}/meetings/start",
            headers=headers,
        )
        assert start.status_code == 201
        session = start.get_json()["session"]
        assert session["id"] != leftover_id
        assert session["meeting_id"] == meeting_pk

        got2 = client.get(f"/api/meetings/{public_id}", headers=headers)
        linked = got2.get_json()["meeting"]["session"]
        assert linked["id"] == session["id"]
        assert "SECRET FROM OLD CALL" not in str(linked.get("transcript"))

        ended = client.post(f"/api/meetings/{public_id}/end", headers=headers)
        assert ended.status_code == 200

    with app.app_context():
        leftover = db.session.get(MeetingSession, leftover_id)
        assert leftover is not None
        assert leftover.meeting_id is None
        assert leftover.is_active is False


@pytest.mark.integration
def test_new_meeting_after_end_uses_new_provider_room(chat_meeting_app):
    app, host_id, _, _, room_id = chat_meeting_app
    with app.test_client() as client:
        headers = _headers(app, host_id)
        first = client.post(
            "/api/meetings",
            headers=headers,
            json={"chat_room_id": room_id, "title": "One"},
        )
        first_body = first.get_json()["meeting"]
        ended = client.post(
            f"/api/meetings/{first_body['public_id']}/end",
            headers=headers,
        )
        assert ended.status_code == 200
        second = client.post(
            "/api/meetings",
            headers=headers,
            json={"chat_room_id": room_id, "title": "Two"},
        )
        assert second.status_code in (200, 201)
        second_body = second.get_json()["meeting"]
        assert second_body["public_id"] != first_body["public_id"]
        assert second_body["provider_room"] != first_body["provider_room"]
        assert second_body["status"] == "live"


@pytest.mark.integration
def test_two_chat_rooms_do_not_share_livekit_room(chat_meeting_app):
    app, host_id, peer_id, _, room_id = chat_meeting_app
    with app.app_context():
        other = ChatRoom(name="Other Chat", is_group=True)
        db.session.add(other)
        db.session.flush()
        db.session.add(ChatRoomMember(room_id=other.id, user_id=host_id))
        db.session.add(ChatRoomMember(room_id=other.id, user_id=peer_id))
        db.session.commit()
        other_id = other.id

    with app.test_client() as client:
        first = client.post(
            "/api/meetings",
            headers=_headers(app, host_id),
            json={"chat_room_id": room_id},
        )
        second = client.post(
            "/api/meetings",
            headers=_headers(app, host_id),
            json={"chat_room_id": other_id},
        )
        a = first.get_json()["meeting"]
        b = second.get_json()["meeting"]
        assert a["provider_room"] != b["provider_room"]
        assert a["public_id"] != b["public_id"]


def test_production_ignores_localhost_stt(monkeypatch):
    monkeypatch.setenv("FLASK_ENV", "production")
    monkeypatch.setenv("STT_SERVICE_URL", "http://localhost:8000")
    from config import resolved_stt_service_url

    assert resolved_stt_service_url() == ""
