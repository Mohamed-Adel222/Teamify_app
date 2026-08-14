"""Integration tests for persisted meeting sessions."""
from __future__ import annotations

import pytest
from flask_jwt_extended import create_access_token

from models import db
from models.chat import ChatRoom, ChatRoomMember, Message
from models.meeting_session import MeetingSession
from models.user import User


@pytest.fixture()
def meeting_app():
    from app import create_app

    app = create_app(
        test_config={
            "TESTING": True,
            "SQLALCHEMY_DATABASE_URI": "sqlite:///:memory:",
            "JWT_SECRET_KEY": "meeting-test-secret",
            "RATELIMIT_ENABLED": False,
        }
    )
    with app.app_context():
        db.create_all()
        user = User(
            display_name="host",
            email="host@test.com",
            password="x",
            role="member",
            user_type="freelancer",
        )
        db.session.add(user)
        db.session.flush()
        room = ChatRoom(name="Standup", is_group=True)
        db.session.add(room)
        db.session.flush()
        db.session.add(ChatRoomMember(room_id=room.id, user_id=user.id))
        db.session.commit()
        yield app, user.id, room.id
        db.drop_all()


@pytest.mark.integration
def test_meeting_session_start_stop(meeting_app):
    app, user_id, room_id = meeting_app
    token = create_access_token(identity=str(user_id))

    with app.test_client() as client:
        headers = {"Authorization": f"Bearer {token}"}

        start = client.post(
            f"/api/chat/rooms/{room_id}/meetings/start", headers=headers
        )
        assert start.status_code == 201
        session_id = start.get_json()["session"]["id"]

        with app.app_context():
            msg = Message(room_id=room_id, sender_id=user_id, content="hello team")
            db.session.add(msg)
            db.session.commit()
            msg_id = msg.id
            created_at = msg.created_at.isoformat()

        stop = client.post(
            f"/api/chat/rooms/{room_id}/meetings/{session_id}/stop",
            headers=headers,
            json={
                "transcript": [
                    {
                        "id": msg_id,
                        "sender_name": "host",
                        "content": "hello team",
                        "created_at": created_at,
                    }
                ],
                "participant_ids": [user_id],
            },
        )
        assert stop.status_code == 200
        body = stop.get_json()["session"]
        assert body["is_active"] is False
        assert len(body["transcript"]) == 1
        assert body["duration_seconds"] is not None
        assert body.get("summary")
        assert "hello team" in body["summary"].lower() or body.get("key_points")

        get_resp = client.get(
            f"/api/chat/rooms/{room_id}/meetings/{session_id}",
            headers=headers,
        )
        assert get_resp.status_code == 200
        assert get_resp.get_json()["session"]["id"] == session_id


@pytest.mark.integration
def test_list_meetings_returns_real_session(meeting_app):
    app, user_id, room_id = meeting_app
    token = create_access_token(identity=str(user_id))

    with app.test_client() as client:
        headers = {"Authorization": f"Bearer {token}"}
        start = client.post(
            f"/api/chat/rooms/{room_id}/meetings/start", headers=headers
        )
        assert start.status_code == 201
        session_id = start.get_json()["session"]["id"]

        listed = client.get("/api/chat/meetings", headers=headers)
        assert listed.status_code == 200
        meetings = listed.get_json()["meetings"]
        assert len(meetings) == 1
        assert meetings[0]["session_id"] == session_id
        assert meetings[0]["room_id"] == room_id
        assert meetings[0]["status"] == "Live"
        assert meetings[0]["host_name"]


@pytest.mark.integration
def test_get_room_members_use_real_display_name(meeting_app):
    app, user_id, room_id = meeting_app
    token = create_access_token(identity=str(user_id))

    with app.test_client() as client:
        headers = {"Authorization": f"Bearer {token}"}
        resp = client.get(f"/api/chat/rooms/{room_id}", headers=headers)
        assert resp.status_code == 200
        members = resp.get_json()["members"]
        assert len(members) == 1
        assert members[0]["display_name"] == "host"
        assert members[0]["user_id"] == user_id
        assert "sarah_m" not in str(members).lower()
        assert "alex chen" not in str(members).lower()
