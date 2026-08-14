import os
import secrets
from datetime import timedelta
from dotenv import load_dotenv

load_dotenv()


def resolved_stt_service_url() -> str:
    """Return the Whisper/STT base URL, or empty when it must not be used.

    Local development still defaults to localhost. Production never silently
    posts audio to localhost / loopback even if .env.example was copied.
    """
    raw = (os.getenv("STT_SERVICE_URL") or "").strip()
    is_prod = os.getenv("FLASK_ENV") == "production"
    if not raw:
        return "" if is_prod else "http://localhost:8000"
    lowered = raw.lower()
    if is_prod and any(
        host in lowered for host in ("localhost", "127.0.0.1", "0.0.0.0")
    ):
        return ""
    return raw.rstrip("/")


def _require_secret(env_var: str) -> str:
    """Return env var value or generate a random key (warns in dev)."""
    val = os.getenv(env_var)
    if val:
        return val
    import warnings
    warnings.warn(
        f"{env_var} is not set – using a random key. "
        "Set it in .env for production.",
        stacklevel=2,
    )
    return secrets.token_hex(32)


class Config:
    """Application configuration class."""

    # Flask
    SECRET_KEY = _require_secret("JWT_SECRET_KEY")

    # Database — fix "postgres://" → "postgresql://" (required by SQLAlchemy 1.4+)
    _db_url = os.getenv("DATABASE_URL", "sqlite:///app.db")
    if _db_url.startswith("postgres://"):
        _db_url = _db_url.replace("postgres://", "postgresql://", 1)
    SQLALCHEMY_DATABASE_URI = _db_url
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SQLALCHEMY_ENGINE_OPTIONS = {
        "pool_pre_ping": True,
        "pool_recycle": 280,
        "connect_args": {"sslmode": "require"} if _db_url.startswith("postgresql") else {},
    }

    # Request size limit (5 MB)
    MAX_CONTENT_LENGTH = 5 * 1024 * 1024

    # JWT
    JWT_SECRET_KEY = _require_secret("JWT_SECRET_KEY")
    JWT_ALGORITHM = "HS256"
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(
        seconds=int(os.getenv("JWT_ACCESS_TOKEN_EXPIRES", 3600))
    )
    JWT_REFRESH_TOKEN_EXPIRES = timedelta(
        days=int(os.getenv("JWT_REFRESH_TOKEN_EXPIRES_DAYS", 7))
    )

    # ── VULN-002 FIX: JWT Cookie Security ─────────────────────────────────────
    # Allow JWTs from BOTH Authorization header (mobile) AND HttpOnly cookies
    # (web). This dual-mode setup is safe: the header path keeps native apps
    # working; the cookie path protects web clients from XSS.
    JWT_TOKEN_LOCATION = ["headers", "cookies"]

    # Cookies are HttpOnly by default in flask-jwt-extended.
    # Set JWT_COOKIE_SECURE = True in production (requires HTTPS).
    _is_prod = os.getenv("FLASK_ENV") == "production"
    JWT_COOKIE_SECURE = _is_prod          # True in prod, False in dev (no HTTPS locally)

    # CSRF double-submit cookie protection (guards cookie path against CSRF).
    # When enabled, POSTs must include the X-CSRF-TOKEN header.
    JWT_COOKIE_CSRF_PROTECT = _is_prod    # True in prod; relaxed in dev for ease of testing

    # Each access_token cookie expires when the browser session ends
    # (i.e. it is a session cookie, not a persistent cookie).
    JWT_SESSION_COOKIE = False            # Use expiring cookies, not session cookies

    # OAuth — defaults match the Flutter web client IDs; override in .env for prod.
    GOOGLE_CLIENT_ID = os.getenv(
        "GOOGLE_CLIENT_ID",
        "854339507790-tntdbhvs0onvvpms12frchr32mq4eud5.apps.googleusercontent.com",
    )
    GITHUB_CLIENT_ID = os.getenv("GITHUB_CLIENT_ID", "Ov23liRUeYFAPsv1xgtd")
    GITHUB_CLIENT_SECRET = os.getenv("GITHUB_CLIENT_SECRET", "")

    # Gate the admin panel behind TOTP. Off by default because the client has no
    # enrolment flow; the 2FA endpoints stay available for when it is added back.
    ADMIN_2FA_REQUIRED = os.getenv("ADMIN_2FA_REQUIRED", "false").lower() in (
        "1", "true", "yes",
    )

    # ── AI / ML Model Settings ────────────────────────────────────────────────
    # Base directory where all .pkl model artifacts live.
    # Defaults to the ml_models/ sub-folder inside the backend package.
    AI_MODELS_DIR = os.getenv(
        "AI_MODELS_DIR",
        os.path.join(os.path.dirname(__file__), "ml_models"),
    )

    # Set to "false" / "0" / "no" to bypass sklearn .pkl inference and use
    # only heuristic fallbacks. Useful for lightweight test environments.
    # This flag does not control DistilBERT (see AI_ENABLE_DISTILBERT).
    AI_ENABLE_LOCAL_MODELS = os.getenv("AI_ENABLE_LOCAL_MODELS", "true")

    # DistilBERT task classifier is optional and OFF by default.
    # Production (Render) uses the keyword fallback — do not set this true
    # on a 512 MB instance. See docs/AI_MODELS.md.
    AI_ENABLE_DISTILBERT = os.getenv("AI_ENABLE_DISTILBERT", "false")

    # Optional: Speech-to-Text microservice URL (FastAPI / Whisper).
    # Production must set a reachable URL; localhost is ignored when FLASK_ENV=production.
    STT_SERVICE_URL = resolved_stt_service_url() or os.getenv("STT_SERVICE_URL", "")

    # Optional: Anthropic Claude API key for mentor report generation
    ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY", "")

    # Redis (optional — falls back to in-memory when unset)
    REDIS_URL = os.getenv("REDIS_URL", "")
    CACHE_TYPE = "RedisCache" if REDIS_URL else "SimpleCache"
    CACHE_REDIS_URL = REDIS_URL or None
    CACHE_DEFAULT_TIMEOUT = int(os.getenv("CACHE_DEFAULT_TIMEOUT", 300))
