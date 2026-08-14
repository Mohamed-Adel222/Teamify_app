import json

import pytest
from unittest.mock import MagicMock

from models.chat import Message
from models.file_metadata import FileMetadata
from services.chat_message_service import create_chat_message
from tests.conftest import FILE_ID, MEMBER_USER_ID


def _room(project_id=None):
    room = MagicMock()
    room.id = 11
    room.project_id = project_id
    return room


def _file_meta(owner_id=MEMBER_USER_ID, mime="image/jpeg", name="photo.jpg"):
    meta = MagicMock()
    meta.id = FILE_ID
    meta.owner_id = owner_id
    meta.original_filename = name
    meta.mime_type = mime
    meta.project_id = None
    return meta


class TestCreateChatMessageAttachments:
    def test_rejects_filename_as_file_id(self, client, mock_db_session):
        msg, err = create_chat_message(
            11,
            MEMBER_USER_ID,
            {
                "content": "Camera Photo",
                "message_type": "image",
                "file_id": "camera_photo.jpg",
            },
        )
        assert msg is None
        assert err is not None
        body, status = err
        assert status == 400
        assert body.get_json()["error"] == "Invalid file_id"

    def test_poll_json_in_content(self, client, mock_db_session):
        mock_db_session.get.return_value = _room()
        payload = {
            "question": "Lunch?",
            "options": [{"text": "Pizza", "votes": 0}, {"text": "Salad", "votes": 0}],
        }
        msg, err = create_chat_message(
            11,
            MEMBER_USER_ID,
            {"content": json.dumps(payload), "message_type": "poll"},
        )
        assert err is None
        assert isinstance(msg, Message)
        assert msg.message_type == "poll"
        assert msg.file_id is None
        assert json.loads(msg.content)["question"] == "Lunch?"

    def test_poll_json_recovered_from_file_id(self, client, mock_db_session):
        mock_db_session.get.return_value = _room()
        payload = {"question": "Ship it?", "options": [{"text": "Yes"}, {"text": "No"}]}
        msg, err = create_chat_message(
            11,
            MEMBER_USER_ID,
            {
                "content": "Ship it?",
                "message_type": "poll",
                "file_id": json.dumps(payload),
            },
        )
        assert err is None
        assert msg.message_type == "poll"
        assert msg.file_id is None
        assert json.loads(msg.content)["question"] == "Ship it?"

    def test_event_requires_json_object(self, client, mock_db_session):
        msg, err = create_chat_message(
            11,
            MEMBER_USER_ID,
            {"content": "not-json", "message_type": "event"},
        )
        assert msg is None
        assert err is not None
        _, status = err
        assert status == 400

    def test_image_requires_file_id(self, client, mock_db_session):
        msg, err = create_chat_message(
            11,
            MEMBER_USER_ID,
            {"content": "Photo", "message_type": "image"},
        )
        assert msg is None
        _, status = err
        assert status == 400
        assert "file_id" in err[0].get_json()["error"]

    def test_valid_image_file_id(self, client, mock_db_session):
        meta = _file_meta()
        room = _room()

        def _get(model, pk):
            if model is FileMetadata:
                return meta
            return room

        mock_db_session.get.side_effect = _get
        msg, err = create_chat_message(
            11,
            MEMBER_USER_ID,
            {"content": "Caption", "message_type": "image", "file_id": FILE_ID},
        )
        assert err is None
        assert msg.message_type == "image"
        assert msg.file_id == FILE_ID

    def test_audio_and_video_types_persist(self, client, mock_db_session):
        meta = _file_meta(mime="audio/webm", name="voice_note.webm")
        room = _room()
        mock_db_session.get.side_effect = lambda model, pk: (
            meta if model is FileMetadata else room
        )
        msg, err = create_chat_message(
            11,
            MEMBER_USER_ID,
            {"content": "Voice message", "message_type": "audio", "file_id": FILE_ID},
        )
        assert err is None
        assert msg.message_type == "audio"
