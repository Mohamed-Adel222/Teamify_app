"""Connection requests between users (profile "Connect" button)."""
from __future__ import annotations

from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt_identity
from sqlalchemy import or_

from middleware.auth import auth_required
from models import db
from models.connection import Connection
from models.user import User
from routes.notifications import create_notification

connections_bp = Blueprint("connections", __name__, url_prefix="/api/connections")


def _display_name(user: User | None) -> str:
    if not user:
        return "Someone"
    return user.full_name or user.display_name or "Someone"


def _pair_connection(user_a: int, user_b: int) -> Connection | None:
    """The connection row between two users, regardless of direction."""
    return Connection.query.filter(
        or_(
            (Connection.requester_id == user_a) & (Connection.addressee_id == user_b),
            (Connection.requester_id == user_b) & (Connection.addressee_id == user_a),
        )
    ).first()


def _status_payload(conn: Connection | None, viewer_id: int) -> dict:
    """Viewer-relative status: none | pending_sent | pending_received |
    connected | declined."""
    if conn is None:
        return {"status": "none", "connection": None}
    if conn.status == Connection.STATUS_ACCEPTED:
        status = "connected"
    elif conn.status == Connection.STATUS_PENDING:
        status = (
            "pending_sent" if conn.requester_id == viewer_id else "pending_received"
        )
    else:
        status = "declined"
    return {"status": status, "connection": conn.to_dict()}


# ── GET /api/connections — list my connections ───────────────────────────────
@connections_bp.route("", methods=["GET"])
@auth_required
def list_connections():
    """List all connection rows involving the caller."""
    user_id = int(get_jwt_identity())
    rows = Connection.query.filter(
        or_(
            Connection.requester_id == user_id,
            Connection.addressee_id == user_id,
        )
    ).order_by(Connection.created_at.desc()).all()
    return jsonify({
        "connections": [r.to_dict() for r in rows],
        "total": len(rows),
    }), 200


# ── GET /api/connections/status/<user_id> — status with one user ─────────────
@connections_bp.route("/status/<int:other_id>", methods=["GET"])
@auth_required
def connection_status(other_id: int):
    """Status of the connection between the caller and another user."""
    user_id = int(get_jwt_identity())
    conn = _pair_connection(user_id, other_id)
    return jsonify(_status_payload(conn, user_id)), 200


# ── POST /api/connections — send a request ───────────────────────────────────
@connections_bp.route("", methods=["POST"])
@auth_required
def send_connection_request():
    """
    Send a connection request to another user.
    Body: {"user_id": <int>}
    """
    user_id = int(get_jwt_identity())
    data = request.get_json(silent=True) or {}

    try:
        other_id = int(data.get("user_id"))
    except (TypeError, ValueError):
        return jsonify({"error": "user_id is required"}), 400

    if other_id == user_id:
        return jsonify({"error": "Cannot connect with yourself"}), 400

    other = db.session.get(User, other_id)
    if not other:
        return jsonify({"error": "User not found"}), 404

    conn = _pair_connection(user_id, other_id)
    if conn:
        # Declined requests may be retried by either side.
        if conn.status == Connection.STATUS_DECLINED:
            conn.status = Connection.STATUS_PENDING
            conn.requester_id = user_id
            conn.addressee_id = other_id
        else:
            return jsonify(_status_payload(conn, user_id)), 200
    else:
        conn = Connection(
            requester_id=user_id,
            addressee_id=other_id,
            status=Connection.STATUS_PENDING,
        )
        db.session.add(conn)
        db.session.flush()

    me = db.session.get(User, user_id)
    create_notification(
        user_id=other_id,
        notif_type="connection_request",
        title="New connection request",
        body=f"{_display_name(me)} wants to connect with you. "
             "Open their profile from Search to accept.",
        entity_type="Connection",
        entity_id=conn.id,
    )

    from services.email_service import send_connection_request_email
    send_connection_request_email(other, _display_name(me))

    db.session.commit()
    return jsonify(_status_payload(conn, user_id)), 201


# ── POST /api/connections/<id>/respond — accept or decline ───────────────────
@connections_bp.route("/<int:connection_id>/respond", methods=["POST"])
@auth_required
def respond_connection(connection_id: int):
    """
    Accept or decline a pending request.
    Body: {"accept": true|false}
    """
    user_id = int(get_jwt_identity())
    data = request.get_json(silent=True) or {}
    accept = bool(data.get("accept"))

    conn = db.session.get(Connection, connection_id)
    if not conn:
        return jsonify({"error": "Connection request not found"}), 404
    if conn.addressee_id != user_id:
        return jsonify({
            "error": "Forbidden",
            "message": "Only the recipient can respond to this request",
        }), 403
    if conn.status != Connection.STATUS_PENDING:
        return jsonify(_status_payload(conn, user_id)), 200

    conn.status = (
        Connection.STATUS_ACCEPTED if accept else Connection.STATUS_DECLINED
    )

    if accept:
        me = db.session.get(User, user_id)
        create_notification(
            user_id=conn.requester_id,
            notif_type="connection_accepted",
            title="Connection accepted",
            body=f"{_display_name(me)} accepted your connection request.",
            entity_type="Connection",
            entity_id=conn.id,
        )
    db.session.commit()
    return jsonify(_status_payload(conn, user_id)), 200
