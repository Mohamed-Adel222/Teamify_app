"""REST API for Teamify meetings (LiveKit-backed)."""
from __future__ import annotations

from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt_identity

from middleware.auth import auth_required
from models import db
from models.meeting_session import MeetingSession
from services.meeting_service import (
    create_instant_meeting,
    end_meeting,
    get_meeting_by_public_id,
    issue_join_token,
    leave_meeting,
    list_meetings_for_user,
    user_can_access_meeting,
)

meetings_bp = Blueprint("meetings", __name__, url_prefix="/api/meetings")


def _public_id_or_404(public_id: str):
    meeting = get_meeting_by_public_id(public_id)
    if meeting is None:
        return None, (jsonify({"error": "Meeting not found"}), 404)
    return meeting, None


@meetings_bp.route("", methods=["GET"])
@auth_required
def list_meetings():
    user_id = int(get_jwt_identity())
    meetings = list_meetings_for_user(user_id)
    return jsonify({"meetings": [m.to_dict() for m in meetings]}), 200


@meetings_bp.route("", methods=["POST"])
@auth_required
def create_meeting():
    user_id = int(get_jwt_identity())
    data = request.get_json(silent=True) or {}
    try:
        chat_room_id = int(data.get("chat_room_id"))
    except (TypeError, ValueError):
        return jsonify({"error": "chat_room_id is required and must be an integer"}), 400

    project_id = data.get("project_id")
    if project_id is not None and str(project_id).strip() != "":
        try:
            project_id = int(project_id)
        except (TypeError, ValueError):
            return jsonify({"error": "project_id must be an integer"}), 400
    else:
        project_id = None

    title = (data.get("title") or "").strip() or None
    meeting, err, status = create_instant_meeting(
        host_user_id=user_id,
        chat_room_id=chat_room_id,
        title=title,
        project_id=project_id,
    )
    if err or meeting is None:
        return jsonify({"error": err or "Could not create meeting"}), status
    return jsonify({"meeting": meeting.to_dict()}), status


@meetings_bp.route("/<public_id>", methods=["GET"])
@auth_required
def get_meeting(public_id: str):
    user_id = int(get_jwt_identity())
    meeting, err = _public_id_or_404(public_id)
    if err:
        return err
    if not user_can_access_meeting(user_id, meeting):
        return jsonify({"error": "Meeting not found"}), 404
    payload = meeting.to_dict()
    session = (
        MeetingSession.query.filter_by(meeting_id=meeting.id)
        .order_by(MeetingSession.started_at.desc())
        .first()
    )
    payload["session"] = session.to_dict() if session else None
    return jsonify({"meeting": payload}), 200


@meetings_bp.route("/<public_id>/token", methods=["POST"])
@auth_required
def meeting_token(public_id: str):
    user_id = int(get_jwt_identity())
    meeting, err = _public_id_or_404(public_id)
    if err:
        return err
    body, error, status = issue_join_token(meeting, user_id)
    if error:
        return jsonify({"error": error}), status
    return jsonify(body), status


@meetings_bp.route("/<public_id>/leave", methods=["POST"])
@auth_required
def meeting_leave(public_id: str):
    user_id = int(get_jwt_identity())
    meeting, err = _public_id_or_404(public_id)
    if err:
        return err
    body, error, status = leave_meeting(meeting, user_id)
    if error:
        return jsonify({"error": error}), status
    return jsonify(body), status


@meetings_bp.route("/<public_id>/end", methods=["POST"])
@auth_required
def meeting_end(public_id: str):
    user_id = int(get_jwt_identity())
    meeting, err = _public_id_or_404(public_id)
    if err:
        return err
    body, error, status = end_meeting(meeting, user_id)
    if error:
        return jsonify({"error": error}), status
    return jsonify(body), status
