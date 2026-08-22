# ============================================================
# CRITICAL: gevent monkey-patch MUST be the very first thing
# that executes — before ANY other import, including stdlib.
# Placing it here prevents the Werkzeug write()-before-
# start_response AssertionError and makes the process-level
# I/O fully async-compatible for Flask-SocketIO.
#
# ssl=False: psycopg2/libpq performs its own TLS. Gevent's ssl
# monkey-patch is a known cause of Render Postgres failing with
# "SSL connection has been closed unexpectedly".
# ============================================================
from gevent import monkey as _monkey
_monkey.patch_all(ssl=False)
# ============================================================

# urllib3/requests wrap gevent sockets with stdlib ssl when ssl is left
# unpatched. That raises:
#   TypeError: _wrap_socket() argument 'sock' must be _socket.socket, not SSLSocket
# Google and GitHub login both need outbound HTTPS, so switch urllib3 to
# PyOpenSSL, which is compatible with this monkey-patch mode.
try:
    from urllib3.contrib.pyopenssl import inject_into_urllib3 as _inject_pyopenssl

    _inject_pyopenssl()
except Exception as _pyopenssl_exc:  # pragma: no cover
    import logging as _bootstrap_logging

    _bootstrap_logging.getLogger(__name__).warning(
        "PyOpenSSL HTTPS adapter unavailable; Google/GitHub login may fail: %s",
        _pyopenssl_exc,
    )

import os
import logging

from flask import Flask, jsonify, request
from flask_cors import CORS
from flask_jwt_extended import JWTManager
from flask_bcrypt import Bcrypt
from flask_migrate import Migrate
from flasgger import Swagger
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from flask_socketio import SocketIO

try:
    from flask_caching import Cache  # pyright: ignore[reportMissingImports]
except ImportError:  # pragma: no cover
    Cache = None  # type: ignore[misc,assignment]
from config import Config
from models import db

# ---------------------------------------------------------------------------
# Module-level singletons — safe to import from routes/sockets because they
# are created *before* any blueprint import happens.
# ---------------------------------------------------------------------------

# Module-level limiter so routes can import it without circular deps
_redis_url = os.getenv("REDIS_URL", "").strip()
_limiter_storage = _redis_url if _redis_url else "memory://"
limiter = Limiter(key_func=get_remote_address, storage_uri=_limiter_storage)

cache = Cache() if Cache is not None else None

# SocketIO singleton — do NOT pass the app yet; we call init_app() inside
# create_app() so test configs are respected.
#
# async_mode="gevent":
#   - Fully compatible with Python 3.13 (eventlet is NOT).
#   - Enables true WebSocket upgrades without Werkzeug's WSGI middleware
#     intercepting the connection mid-flight.
#   - Uses gevent greenlets — no GIL contention on I/O-heavy paths.
#
# ping_interval / ping_timeout:
#   - Must be kept well inside the Flutter socket_io_client default
#     reconnect window (20 s).  25/60 means a missed pong triggers a
#     clean server-side disconnect before the client decides to reconnect
#     on its own, preventing the dreaded dual-reconnect race.
socketio = SocketIO(
    async_mode="gevent",
    ping_interval=25,
    ping_timeout=60,
    cors_allowed_origins="*",
    logger=False,
    engineio_logger=False,
)


def _apply_runtime_schema_patches(app: Flask) -> None:
    """Add columns introduced after the last successful Alembic upgrade."""
    from sqlalchemy import inspect, text

    try:
        insp = inspect(db.engine)
        if "meeting_sessions" in insp.get_table_names():
            col_names = {c["name"] for c in insp.get_columns("meeting_sessions")}
            if "ai_summary" not in col_names:
                dialect = db.engine.dialect.name
                if dialect == "postgresql":
                    sql = (
                        "ALTER TABLE meeting_sessions "
                        "ADD COLUMN IF NOT EXISTS ai_summary JSONB"
                    )
                else:
                    sql = "ALTER TABLE meeting_sessions ADD COLUMN ai_summary JSON"

                with db.engine.begin() as conn:
                    conn.execute(text(sql))
                app.logger.info("Schema patch: added meeting_sessions.ai_summary")
    except Exception as exc:
        app.logger.warning("Schema patch meeting_sessions.ai_summary skipped: %s", exc)

    try:
        insp = inspect(db.engine)
        if "mentor_chat_messages" not in insp.get_table_names():
            return
        col_names = {c["name"] for c in insp.get_columns("mentor_chat_messages")}
        if "thread_key" not in col_names:
            dialect = db.engine.dialect.name
            if dialect == "postgresql":
                sql = (
                    "ALTER TABLE mentor_chat_messages "
                    "ADD COLUMN IF NOT EXISTS thread_key VARCHAR(120) "
                    "NOT NULL DEFAULT 'general'"
                )
            else:
                sql = (
                    "ALTER TABLE mentor_chat_messages "
                    "ADD COLUMN thread_key VARCHAR(120) NOT NULL DEFAULT 'general'"
                )

            with db.engine.begin() as conn:
                conn.execute(text(sql))
            app.logger.info("Schema patch: added mentor_chat_messages.thread_key")
    except Exception as exc:
        app.logger.warning(
            "Schema patch mentor_chat_messages.thread_key skipped: %s", exc
        )

    try:
        insp = inspect(db.engine)
        if "users" in insp.get_table_names():
            col_names = {c["name"] for c in insp.get_columns("users")}
            if "preferred_language" not in col_names:
                dialect = db.engine.dialect.name
                if dialect == "postgresql":
                    sql = (
                        "ALTER TABLE users "
                        "ADD COLUMN IF NOT EXISTS preferred_language VARCHAR(10)"
                    )
                else:
                    sql = "ALTER TABLE users ADD COLUMN preferred_language VARCHAR(10)"

                with db.engine.begin() as conn:
                    conn.execute(text(sql))
                app.logger.info("Schema patch: added users.preferred_language")
    except Exception as exc:
        app.logger.warning("Schema patch users.preferred_language skipped: %s", exc)

    for column, pg_type, sqlite_type in (
        ("university_id", "VARCHAR(64)", "VARCHAR(64)"),
        ("university_name", "VARCHAR(200)", "VARCHAR(200)"),
        ("is_custom_university", "BOOLEAN DEFAULT FALSE", "BOOLEAN DEFAULT 0"),
        ("notification_prefs", "JSONB", "JSON"),
        ("portfolio_url", "VARCHAR(300)", "VARCHAR(300)"),
    ):
        try:
            insp = inspect(db.engine)
            if "users" not in insp.get_table_names():
                break
            if column in {c["name"] for c in insp.get_columns("users")}:
                continue
            if db.engine.dialect.name == "postgresql":
                sql = f"ALTER TABLE users ADD COLUMN IF NOT EXISTS {column} {pg_type}"
            else:
                sql = f"ALTER TABLE users ADD COLUMN {column} {sqlite_type}"
            with db.engine.begin() as conn:
                conn.execute(text(sql))
            app.logger.info("Schema patch: added users.%s", column)
        except Exception as exc:
            app.logger.warning("Schema patch users.%s skipped: %s", column, exc)

    try:
        insp = inspect(db.engine)
        if "chat_rooms" in insp.get_table_names():
            col_names = {c["name"] for c in insp.get_columns("chat_rooms")}
            if "direct_pair_key" not in col_names:
                dialect = db.engine.dialect.name
                if dialect == "postgresql":
                    sql = (
                        "ALTER TABLE chat_rooms "
                        "ADD COLUMN IF NOT EXISTS direct_pair_key VARCHAR(64)"
                    )
                else:
                    sql = "ALTER TABLE chat_rooms ADD COLUMN direct_pair_key VARCHAR(64)"
                with db.engine.begin() as conn:
                    conn.execute(text(sql))
                app.logger.info("Schema patch: added chat_rooms.direct_pair_key")
    except Exception as exc:
        app.logger.warning("Schema patch chat_rooms.direct_pair_key skipped: %s", exc)

    try:
        insp = inspect(db.engine)
        if "meeting_sessions" in insp.get_table_names():
            col_names = {c["name"] for c in insp.get_columns("meeting_sessions")}
            if "meeting_id" not in col_names:
                dialect = db.engine.dialect.name
                if dialect == "postgresql":
                    sql = (
                        "ALTER TABLE meeting_sessions "
                        "ADD COLUMN IF NOT EXISTS meeting_id INTEGER"
                    )
                else:
                    sql = "ALTER TABLE meeting_sessions ADD COLUMN meeting_id INTEGER"
                with db.engine.begin() as conn:
                    conn.execute(text(sql))
                app.logger.info("Schema patch: added meeting_sessions.meeting_id")
    except Exception as exc:
        app.logger.warning("Schema patch meeting_sessions.meeting_id skipped: %s", exc)

    try:
        insp = inspect(db.engine)
        if "messages" in insp.get_table_names():
            col_names = {c["name"] for c in insp.get_columns("messages")}
            if "idempotency_key" not in col_names:
                dialect = db.engine.dialect.name
                if dialect == "postgresql":
                    sql = (
                        "ALTER TABLE messages "
                        "ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(64)"
                    )
                else:
                    sql = "ALTER TABLE messages ADD COLUMN idempotency_key VARCHAR(64)"
                with db.engine.begin() as conn:
                    conn.execute(text(sql))
                app.logger.info("Schema patch: added messages.idempotency_key")
    except Exception as exc:
        app.logger.warning("Schema patch messages.idempotency_key skipped: %s", exc)

    try:
        insp = inspect(db.engine)
        if "users" in insp.get_table_names():
            col = next(
                (c for c in insp.get_columns("users") if c["name"] == "otp_code"),
                None,
            )
            if col is not None:
                col_type = str(col.get("type") or "")
                if "6" in col_type and "128" not in col_type and db.engine.dialect.name == "postgresql":
                    with db.engine.begin() as conn:
                        conn.execute(text("ALTER TABLE users ALTER COLUMN otp_code TYPE VARCHAR(128)"))
                    app.logger.info("Schema patch: widened users.otp_code")
    except Exception as exc:
        app.logger.warning("Schema patch users.otp_code skipped: %s", exc)

    _ensure_runtime_indexes(app)


def _ensure_runtime_indexes(app: Flask) -> None:
    """Create unique indexes Alembic would add, for hosts that only run patches."""
    from sqlalchemy import inspect, text

    def _exec(description: str, sql: str) -> None:
        try:
            with db.engine.begin() as conn:
                conn.execute(text(sql))
            app.logger.info("Schema patch: %s", description)
        except Exception as exc:
            app.logger.warning("Schema patch %s skipped: %s", description, exc)

    try:
        insp = inspect(db.engine)
        tables = set(insp.get_table_names())
    except Exception as exc:
        app.logger.warning("Schema patch index inspect skipped: %s", exc)
        return

    if "meetings" in tables:
        try:
            dialect = db.engine.dialect.name
            if dialect == "postgresql":
                _exec(
                    "ended duplicate live meetings",
                    """
                    UPDATE meetings
                    SET status = 'ended', ended_at = NOW()
                    WHERE status = 'live'
                      AND id NOT IN (
                        SELECT keep_id FROM (
                          SELECT MAX(id) AS keep_id FROM meetings
                          WHERE status = 'live'
                          GROUP BY chat_room_id
                        ) keepers
                      )
                    """,
                )
            else:
                _exec(
                    "ended duplicate live meetings",
                    """
                    UPDATE meetings
                    SET status = 'ended', ended_at = CURRENT_TIMESTAMP
                    WHERE status = 'live'
                      AND id NOT IN (
                        SELECT keep_id FROM (
                          SELECT MAX(id) AS keep_id FROM meetings
                          WHERE status = 'live'
                          GROUP BY chat_room_id
                        ) keepers
                      )
                    """,
                )
            _exec(
                "uq_meetings_one_live_per_room",
                "CREATE UNIQUE INDEX IF NOT EXISTS uq_meetings_one_live_per_room "
                "ON meetings (chat_room_id) WHERE status = 'live'",
            )
        except Exception as exc:
            app.logger.warning("Schema patch live meeting uniqueness skipped: %s", exc)

    if "messages" in tables:
        _exec(
            "uq_msg_idempotency",
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_msg_idempotency "
            "ON messages (room_id, sender_id, idempotency_key)",
        )

    if "chat_rooms" in tables:
        _exec(
            "uq_chat_rooms_direct_pair_key",
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_chat_rooms_direct_pair_key "
            "ON chat_rooms (direct_pair_key)",
        )


def _init_database_with_retry(app: Flask, attempts: int = 5) -> None:
    """Create tables / schema patches, retrying Render Postgres wake-ups.

    Free-tier Postgres often drops the first TLS handshake. Failing
    ``create_all()`` here used to crash gunicorn before /api/health could
    answer, so Render marked the instance as failed.
    """
    delay = 1.0
    last_exc: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            db.create_all()
            _apply_runtime_schema_patches(app)
            if attempt > 1:
                app.logger.info("Database init succeeded on attempt %s", attempt)
            return
        except Exception as exc:
            last_exc = exc
            app.logger.warning(
                "Database init failed (attempt %s/%s): %s", attempt, attempts, exc
            )
            try:
                db.session.rollback()
            except Exception:
                pass
            try:
                db.session.remove()
            except Exception:
                pass
            try:
                db.engine.dispose()
            except Exception:
                pass
            if attempt < attempts:
                try:
                    import gevent
                    gevent.sleep(delay)
                except Exception:
                    import time
                    time.sleep(delay)
                delay = min(delay * 2, 16)
    app.logger.error(
        "Starting without a verified DB connection after %s attempts: %s",
        attempts,
        last_exc,
    )


def create_app(test_config=None):
    """Create and configure the Flask application."""

    app = Flask(__name__)
    app.config.from_object(Config)
    if test_config is not None:
        app.config.update(test_config)

    # --- Initialize Extensions ---
    db.init_app(app)
    Migrate(app, db)          # enables: flask db init / migrate / upgrade

    # CORS — allow socket.io polling path too (needed during upgrade handshake)
    # Default covers local dev plus the Firebase / Netlify hosts the Flutter
    # web app deploys to; override with CORS_ORIGINS for a stricter list.
    _cors_origins = [
        o.strip()
        for o in os.getenv(
            "CORS_ORIGINS",
            ",".join([
                "http://localhost:3000",
                "http://localhost:8080",
                "https://*.web.app",
                "https://*.firebaseapp.com",
                "https://*.netlify.app",
            ]),
        ).split(",")
        if o.strip()
    ]
    cors_settings = {
        "origins": _cors_origins,
        "methods": ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        "allow_headers": ["Content-Type", "Authorization"],
    }
    CORS(
        app,
        resources={
            r"/api/*": cors_settings,
            r"/admin/*": cors_settings,
            r"/socket.io/*": {
                "origins": "*",
                "allow_headers": ["Content-Type", "Authorization"],
            },
        },
    )

    jwt = JWTManager(app)
    Bcrypt(app)
    limiter.init_app(app)
    if cache is not None:
        cache.init_app(app)

    # Re-initialise SocketIO with the concrete app instance.
    # All parameters are already set on the singleton; init_app() just wires
    # the Flask app without creating a second SocketIO object.
    socketio.init_app(
        app,
        cors_allowed_origins="*",
        async_mode="gevent",
        ping_interval=25,
        ping_timeout=60,
        logger=False,
        engineio_logger=False,
        # Allow the upgrade probe to reach the server even when
        # Flask-Limiter rejects the polling XHR (different IP buckets).
        manage_session=False,
    )

    # --- JWT Token Blocklist (DB-backed, survives restarts) ---
    @jwt.token_in_blocklist_loader
    def check_if_token_revoked(jwt_header, jwt_payload):
        from models.token_blocklist import TokenBlocklist
        return TokenBlocklist.is_revoked(jwt_payload["jti"])

    # --- Swagger Configuration ---
    is_production = os.getenv("FLASK_ENV") == "production"

    swagger_config = {
        "headers": [],
        "specs": [
            {
                "endpoint": "apispec",
                "route": "/apispec.json",
                "rule_filter": lambda rule: True,
                "model_filter": lambda tag: True,
            }
        ],
        "static_url_path": "/flasgger_static",
        "swagger_ui": not is_production,
        "specs_route": "/swagger/",
    }

    swagger_template = {
        "info": {
            "title": "Backend Task 1 API",
            "description": "REST API with Auth, JWT, and DB Schema",
            "version": "1.0.0",
        },
        "securityDefinitions": {
            "Bearer": {
                "type": "apiKey",
                "name": "Authorization",
                "in": "header",
                "description": "JWT token. Format: Bearer <token>",
            }
        },
    }

    Swagger(app, config=swagger_config, template=swagger_template)

    # --- Security Headers ---
    @app.after_request
    def set_security_headers(response):
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        if is_production:
            response.headers["Strict-Transport-Security"] = (
                "max-age=31536000; includeSubDomains"
            )
        return response

    # --- Global Error Handlers ---
    @app.errorhandler(413)
    def request_entity_too_large(e):
        return jsonify({"error": "Payload Too Large", "message": "Request body exceeds the 5 MB limit"}), 413

    @app.errorhandler(404)
    def not_found(e):
        return jsonify({"error": "Not Found", "message": "The requested URL was not found"}), 404

    @app.errorhandler(405)
    def method_not_allowed(e):
        return jsonify({"error": "Method Not Allowed"}), 405

    @app.errorhandler(500)
    def internal_server_error(e):
        return jsonify({"error": "Internal Server Error"}), 500

    # --- Register Blueprints ---
    from routes.auth import auth_bp
    from routes.users import users_bp
    from routes.projects import projects_bp
    from routes.tasks import tasks_bp
    from routes.logs import logs_bp
    from routes.ai import ai_bp
    from routes.stats import stats_bp
    from routes.reminders import reminders_bp
    from routes.notifications import notifications_bp
    from routes.dashboard import dashboard_bp
    from routes.search import search_bp
    from routes.admin import admin_bp
    from routes.files import files_bp
    from routes.comments import comments_bp
    from routes.feedback import feedback_bp
    from routes.ratings import ratings_bp
    from routes.cv import cv_bp
    from routes.disputes import disputes_bp
    from routes.chat import chat_bp
    from routes.meetings import meetings_bp
    from routes.universities import universities_bp
    from routes.connections import connections_bp

    app.register_blueprint(auth_bp)
    app.register_blueprint(users_bp)
    app.register_blueprint(projects_bp)
    app.register_blueprint(tasks_bp)
    app.register_blueprint(logs_bp)
    app.register_blueprint(ai_bp)
    app.register_blueprint(stats_bp)
    app.register_blueprint(reminders_bp)
    app.register_blueprint(notifications_bp)
    app.register_blueprint(dashboard_bp)
    app.register_blueprint(search_bp)
    app.register_blueprint(admin_bp)
    app.register_blueprint(files_bp)
    app.register_blueprint(comments_bp)
    app.register_blueprint(feedback_bp)
    app.register_blueprint(ratings_bp)
    app.register_blueprint(cv_bp)
    app.register_blueprint(disputes_bp)
    app.register_blueprint(chat_bp)
    app.register_blueprint(meetings_bp)
    app.register_blueprint(universities_bp)
    app.register_blueprint(connections_bp)

    @app.before_request
    def enforce_maintenance_mode():
        if request.method == "OPTIONS":
            return None
        path = request.path or ""
        if (
            path.startswith("/admin")
            or path.startswith("/swagger")
            or path.startswith("/api/auth")
            or path.startswith("/api/health")
            or path.startswith("/socket.io")
            or path.rstrip("/").endswith("/api/ai/models/status")
        ):
            return None
        try:
            from services.system_settings_service import is_maintenance_mode
            if not is_maintenance_mode():
                return None
            from flask_jwt_extended import verify_jwt_in_request, get_jwt_identity
            from models.user import User

            verify_jwt_in_request(optional=True)
            caller_id = get_jwt_identity()
            if caller_id:
                caller = User.query.filter_by(id=int(caller_id)).first()
                if caller and caller.role == "admin":
                    return None
        except Exception:
            pass
        return jsonify({
            "error": "Maintenance mode",
            "message": "The platform is temporarily unavailable for maintenance.",
        }), 503

    # ─── Health Check ─────────────────────────────────────────────────────────
    @app.route("/api/health", methods=["GET"])
    def health():
        """
        Health check — confirms the API and database are reachable.
        ---
        tags:
          - Health
        responses:
          200:
            description: API is healthy
            schema:
              type: object
              properties:
                status:
                  type: string
                  example: ok
                database:
                  type: string
                  example: ok
          503:
            description: Database unreachable
        """
        from sqlalchemy import text
        try:
            db.session.execute(text("SELECT 1"))
            db_status = "ok"
            http_status = 200
        except Exception:
            db_status = "error"
            http_status = 503
        from services.email_service import mail_status
        from services.livekit_token_service import livekit_configured

        return jsonify({
            "status": "ok" if http_status == 200 else "degraded",
            "database": db_status,
            "video_meetings": livekit_configured(),
            "email": mail_status(),
        }), http_status

    # --- Import models + create tables if they don't exist ---
    with app.app_context():
        from models.user import User
        from models.project import Project
        from models.project_member import ProjectMember
        from models.project_invitation import ProjectInvitation  # noqa: F401
        from models.task import Task
        from models.log import Log
        from models.notification import Notification
        from models.login_log import LoginLog
        from models.alert import Alert
        from models.file_metadata import FileMetadata
        from models.task_comment import TaskComment
        from models.feedback import Feedback
        from models.rating import Rating
        from models.cv import CV
        from models.cv_download_token import CVDownloadToken
        from models.audit_log import AuditLog
        from models.dispute import Dispute
        from models.chat import ChatRoom, ChatRoomMember, Message
        from models.connection import Connection  # noqa: F401
        from models.meeting_session import MeetingSession  # noqa: F401
        from models.meeting import Meeting, MeetingParticipant  # noqa: F401
        from models.mentor_chat_message import MentorChatMessage  # noqa: F401
        from models.token_blocklist import TokenBlocklist  # noqa: F401
        from models.admin_panel import (  # noqa: F401
            AdminAnalyticsSnapshot,
            BroadcastHistory,
            RolePermission,
            AdminSession,
        )
        from models.system_setting import SystemSetting  # noqa: F401
        from models.email_delivery import EmailDelivery  # noqa: F401

        from services.delay_predictor_service import startup_check as delay_startup_check
        from services.chat_summarization_service import startup_check as chat_startup_check
        from services.task_pipeline_service import startup_check as task_pipeline_startup_check

        def _boot_database() -> None:
            with app.app_context():
                _init_database_with_retry(app)
                delay_startup_check()
                chat_startup_check()
                task_pipeline_startup_check()

        db_uri = str(app.config.get("SQLALCHEMY_DATABASE_URI") or "")
        # Bind the HTTP port immediately in production. Waiting on Postgres
        # retries made Render report "No open ports detected".
        if test_config is not None or db_uri.startswith("sqlite"):
            _boot_database()
        else:
            import gevent
            gevent.spawn(_boot_database)

    # --- Start reminders scheduler ---
    from services.scheduler import init_scheduler
    init_scheduler(app)

    # --- Register SocketIO events ---
    from sockets.chat_sockets import register_chat_events
    register_chat_events(socketio)

    return app


if __name__ == "__main__":
    app = create_app()
    port = int(os.getenv("PORT", 5022))
    debug = os.getenv("FLASK_DEBUG", "False").lower() in ("true", "1")
    host = "127.0.0.1" if debug else "0.0.0.0"

    print(f"[OK] Async mode : gevent (Python {__import__('sys').version.split()[0]})")
    print(f"[OK] Server     : http://{host}:{port}")
    print(f"[OK] Debug      : {debug}")
    print(f"[OK] Swagger UI : http://localhost:{port}/swagger/")
    print(f"[OK] WebSocket  : ws://localhost:{port}  (Socket.IO via gevent)")
    print(f"[OK] Endpoints  :")
    print(f"     POST /api/auth/register")
    print(f"     POST /api/auth/login")
    print(f"     GET  /api/chat/rooms            (chat)")
    print(f"     GET  /api/users/profile          (protected)")
    print(f"     GET  /api/users/admin-dashboard  (admin only)")

    # socketio.run() wraps the WSGI app in gevent's WSGIServer +
    # WebSocket-aware handler automatically.  Never call app.run()
    # directly — that bypasses the WebSocket layer entirely.
    socketio.run(
        app,
        host=host,
        port=port,
        debug=debug,
        use_reloader=False,   # avoid double-startup under gevent
        log_output=True,
    )
