"""Compute freelancer/student profile-completion from persisted user fields.

Google/email authentication only creates the account. A freelancer is complete
after full name, username, and the professional fields are saved in the DB.
"""
from __future__ import annotations

from typing import Any


def _text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value.strip()
    return str(value).strip()


def _skills(value: Any) -> list[Any]:
    if not value:
        return []
    if isinstance(value, list):
        return [item for item in value if item]
    if isinstance(value, str):
        return [part.strip() for part in value.split(",") if part.strip()]
    return []


def is_freelancer_profile_complete(user: Any) -> bool:
    return bool(
        _text(getattr(user, "full_name", None))
        and _text(getattr(user, "display_name", None))
        and _text(getattr(user, "professional_field", None))
        and _text(getattr(user, "experience_level", None))
        and _text(getattr(user, "availability", None))
        and _skills(getattr(user, "skills", None))
    )


def is_student_profile_complete(user: Any) -> bool:
    return bool(
        _text(getattr(user, "major", None))
        and _text(getattr(user, "current_level", None))
        and _skills(getattr(user, "skills", None))
    )


def needs_profile_setup(user: Any) -> bool:
    role = _text(getattr(user, "role", None)).lower()
    user_type = _text(getattr(user, "user_type", None)).lower()
    if role == "admin" or user_type == "admin":
        return False
    if user_type == "student":
        return not is_student_profile_complete(user)
    if user_type in ("freelancer", ""):
        return not is_freelancer_profile_complete(user)
    return False
