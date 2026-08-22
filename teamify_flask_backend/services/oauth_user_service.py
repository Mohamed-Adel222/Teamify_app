"""Persist OAuth sign-ins: find existing users or create new rows safely."""
from __future__ import annotations

import secrets
from typing import Any

from flask_bcrypt import Bcrypt
from sqlalchemy.exc import IntegrityError, SQLAlchemyError

from models import db
from models.log import Log
from models.user import User
from utils.user_names import generate_unique_display_name

VALID_USER_TYPES = frozenset({"freelancer", "student", "admin"})

OAUTH_PROFILE_KEYS = (
    "professional_field",
    "experience_level",
    "availability",
    "current_level",
    "major",
    "looking_for_team",
    "skills",
)

# Web client ID used by the Flutter app (implicit OAuth flow).
DEFAULT_GOOGLE_CLIENT_ID = (
    "854339507790-tntdbhvs0onvvpms12frchr32mq4eud5.apps.googleusercontent.com"
)
DEFAULT_GITHUB_CLIENT_ID = "Ov23liRUeYFAPsv1xgtd"


def normalize_user_type(raw: str | None) -> str | None:
    value = (raw or "").strip().lower()
    return value if value in VALID_USER_TYPES else None


def extract_oauth_profile(data: dict[str, Any] | None) -> dict[str, Any]:
    """Optional profile fields sent with OAuth sign-up (same as email register)."""
    from utils.skills import normalize_skills_list

    if not data:
        return {}
    profile: dict[str, Any] = {}
    for key in OAUTH_PROFILE_KEYS:
        if key not in data:
            continue
        val = data[key]
        if key == "skills":
            normalized = normalize_skills_list(val)
            if normalized:
                profile["skills"] = normalized
        elif key == "looking_for_team":
            if val is not None:
                profile["looking_for_team"] = bool(val)
        elif isinstance(val, str):
            stripped = val.strip()
            if stripped:
                profile[key] = stripped
    return profile


def apply_profile_fields(user: User, profile: dict[str, Any]) -> None:
    for key, val in profile.items():
        setattr(user, key, val)


def google_client_ids() -> list[str]:
    import os

    ids: list[str] = []
    for candidate in (os.getenv("GOOGLE_CLIENT_ID"), DEFAULT_GOOGLE_CLIENT_ID):
        if candidate and candidate not in ids:
            ids.append(candidate)
    return ids


def verify_google_id_token(raw_token: str) -> dict[str, Any]:
    """Verify a Google ID token; tries configured client IDs then dev fallback.

    Network / TLS failures are raised as ValueError so the auth route can
    return 401 instead of an uncaught 500.
    """
    try:
        from google.auth.transport import requests as google_requests  # type: ignore[import-untyped]
        from google.oauth2 import id_token as google_id_token  # type: ignore[import-untyped]
    except ImportError as exc:
        raise RuntimeError(
            "Google sign-in is not available: google-auth is not installed"
        ) from exc

    last_error: Exception | None = None
    request = google_requests.Request()
    for audience in google_client_ids():
        try:
            return google_id_token.verify_oauth2_token(
                raw_token,
                request,
                audience=audience,
            )
        except ValueError as exc:
            last_error = exc
        except Exception as exc:
            last_error = exc
            break

    if last_error is not None and not isinstance(last_error, ValueError):
        raise ValueError(f"Could not verify Google token: {last_error}") from last_error

    try:
        return google_id_token.verify_oauth2_token(
            raw_token,
            request,
            audience=None,
        )
    except ValueError as exc:
        raise ValueError(str(last_error or exc)) from exc
    except Exception as exc:
        raise ValueError(f"Could not verify Google token: {last_error or exc}") from exc


def _commit_oauth_user(user: User, *, action: str, details: str) -> User:
    """Insert user + audit log atomically; recover from duplicate-key races."""
    try:
        db.session.add(user)
        db.session.flush()
        db.session.add(
            Log(
                action=action,
                entity="User",
                entity_id=user.id,
                details=details,
                user_id=user.id,
            )
        )
        db.session.commit()
        db.session.refresh(user)
        return user
    except IntegrityError:
        db.session.rollback()
        existing = User.query.filter_by(email=user.email).first()
        if existing:
            return existing
        if user.github_id:
            existing = User.query.filter_by(github_id=user.github_id).first()
            if existing:
                return existing
        raise
    except SQLAlchemyError:
        db.session.rollback()
        raise


def find_or_create_google_user(
    *,
    email: str,
    full_name: str,
    google_sub: str,
    user_type: str | None,
    bcrypt: Bcrypt,
    profile: dict[str, Any] | None = None,
) -> tuple[User, bool]:
    normalized_email = email.strip().lower()
    existing = User.query.filter_by(email=normalized_email).first()
    if existing:
        return existing, False

    display_name = generate_unique_display_name()
    user = User(
        display_name=display_name,
        full_name=(full_name or "").strip() or None,
        email=normalized_email,
        password=bcrypt.generate_password_hash(google_sub).decode("utf-8"),
        role="member",
        user_type=user_type,
    )
    if profile:
        apply_profile_fields(user, profile)
    user = _commit_oauth_user(
        user,
        action="REGISTER_GOOGLE",
        details=f"User '{display_name}' registered via Google OAuth",
    )
    return user, True


def find_or_create_github_user(
    *,
    github_id: str,
    email: str,
    full_name: str,
    gh_login: str,
    user_type: str | None,
    bcrypt: Bcrypt,
    profile: dict[str, Any] | None = None,
) -> tuple[User, bool]:
    user = User.query.filter_by(github_id=github_id).first()
    if user:
        return user, False

    normalized_email = email.strip().lower()
    if normalized_email:
        user = User.query.filter_by(email=normalized_email).first()
        if user:
            if not user.github_id:
                user.github_id = github_id
                db.session.commit()
            return user, False

    display_name = generate_unique_display_name()
    dummy_pw = bcrypt.generate_password_hash(secrets.token_hex(32)).decode("utf-8")
    user = User(
        display_name=display_name,
        full_name=(full_name or "").strip()[:150] or None,
        email=normalized_email or f"{github_id}@github.noemail",
        password=dummy_pw,
        role="member",
        github_id=github_id,
        user_type=user_type,
    )
    if profile:
        apply_profile_fields(user, profile)
    user = _commit_oauth_user(
        user,
        action="GITHUB_REGISTER",
        details=f"GitHub OAuth registration for login '{gh_login}'",
    )
    return user, True
