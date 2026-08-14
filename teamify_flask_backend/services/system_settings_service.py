"""Load, update, and enforce platform-wide admin settings."""
from __future__ import annotations

import re
from typing import Any

from models.system_setting import SystemSetting

_PASSWORD_PATTERNS = {
    "low": (
        re.compile(r"^.{6,}$"),
        "Password must be at least 6 characters",
    ),
    "medium": (
        re.compile(r"^(?=.*[A-Z])(?=.*\d).{8,}$"),
        "Password must be at least 8 characters with 1 uppercase letter and 1 digit",
    ),
    "high": (
        re.compile(r"^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).{10,}$"),
        "Password must be at least 10 characters with upper, lower, digit, and special character",
    ),
}

_LEGACY_DEFAULT_FILE_TYPES = frozenset({"pdf", "doc", "docx", "png", "jpg", "jpeg"})
_DEFAULT_ALLOWED_FILE_TYPES = [
    "pdf",
    "doc",
    "docx",
    "xls",
    "xlsx",
    "ppt",
    "pptx",
    "txt",
    "csv",
    "zip",
    "png",
    "jpg",
    "jpeg",
    "gif",
    "webp",
    "heic",
    "mp3",
    "wav",
    "m4a",
    "ogg",
    "webm",
    "mp4",
    "mov",
]

_SYSTEM_SETTING_DEFAULTS: dict[str, Any] = {
    "registrations_enabled": True,
    "maintenance_mode": False,
    "ai_mentorship_enabled": True,
    "ai_daily_limit_per_user": 100,
    "max_upload_size_mb": 10,
    "allowed_file_types": list(_DEFAULT_ALLOWED_FILE_TYPES),
    "session_timeout_minutes": 60,
    "password_policy": "medium",
    "email_notifications": True,
    "push_notifications": True,
    "mfa_required": False,
    "max_login_attempts": 5,
    "rate_limiting_enabled": True,
    "api_requests_per_minute": 100,
    "login_attempts_per_hour": 5,
    "encryption_at_rest": True,
    "encryption_in_transit": True,
}

_SETTING_ALIASES = {
    "registration_enabled": "registrations_enabled",
    "ai_enabled": "ai_mentorship_enabled",
    "ai_limits": "ai_daily_limit_per_user",
    "session_timeout_min": "session_timeout_minutes",
}

_settings_cache: dict[str, Any] | None = None


def invalidate_settings_cache() -> None:
    global _settings_cache
    _settings_cache = None


def _coerce_bool(val) -> bool:
    if val is None:
        return False
    if isinstance(val, bool):
        return val
    if isinstance(val, (int, float)):
        return val != 0
    return str(val).strip().lower() in ("true", "1", "yes", "on")


def _coerce_int(val, default: int = 0) -> int:
    if isinstance(val, int):
        return val
    if isinstance(val, float):
        return int(val)
    try:
        return int(str(val).strip())
    except (TypeError, ValueError):
        return default


def _parse_file_types(val) -> list[str]:
    if isinstance(val, list):
        return [str(x).strip().lower().lstrip(".") for x in val if str(x).strip()]
    if not val:
        return []
    return [t.strip().lower().lstrip(".") for t in str(val).split(",") if t.strip()]


def _load_system_settings_raw() -> dict:
    settings: dict = {}
    for key, def_val in _SYSTEM_SETTING_DEFAULTS.items():
        val = SystemSetting.get(key)
        if val is None:
            SystemSetting.set(key, def_val)
            settings[key] = def_val
        else:
            settings[key] = val
    return settings


def get_system_settings() -> dict[str, Any]:
    global _settings_cache
    if _settings_cache is not None:
        return dict(_settings_cache)

    settings = _load_system_settings_raw()
    file_types = _parse_file_types(settings.get("allowed_file_types"))
    registrations = _coerce_bool(settings["registrations_enabled"])
    ai_enabled = _coerce_bool(settings["ai_mentorship_enabled"])
    session_timeout = _coerce_int(settings["session_timeout_minutes"], 60)

    payload = {
        "registration_enabled": registrations,
        "registrations_enabled": registrations,
        "ai_enabled": ai_enabled,
        "ai_mentorship_enabled": ai_enabled,
        "ai_limits": _coerce_int(settings.get("ai_daily_limit_per_user"), 100),
        "max_upload_size_mb": _coerce_int(settings.get("max_upload_size_mb"), 10),
        "allowed_file_types": file_types,
        "session_timeout_min": session_timeout,
        "session_timeout_minutes": session_timeout,
        "password_policy": str(settings.get("password_policy") or "medium"),
        "email_notifications": _coerce_bool(settings.get("email_notifications", True)),
        "push_notifications": _coerce_bool(settings.get("push_notifications", True)),
        "maintenance_mode": _coerce_bool(settings["maintenance_mode"]),
        "mfa_required": _coerce_bool(settings["mfa_required"]),
        "max_login_attempts": _coerce_int(settings["max_login_attempts"], 5),
        "rate_limiting_enabled": _coerce_bool(settings["rate_limiting_enabled"]),
        "api_requests_per_minute": _coerce_int(settings["api_requests_per_minute"], 100),
        "login_attempts_per_hour": _coerce_int(settings["login_attempts_per_hour"], 5),
        "encryption_at_rest": _coerce_bool(settings["encryption_at_rest"]),
        "encryption_in_transit": _coerce_bool(settings["encryption_in_transit"]),
    }
    _settings_cache = payload
    return dict(payload)


def _normalize_setting_value(key: str, val):
    if key == "allowed_file_types":
        return _parse_file_types(val)
    if key == "password_policy":
        policy = str(val or "medium").lower()
        return policy if policy in _PASSWORD_PATTERNS else "medium"
    if key in {
        "registrations_enabled",
        "maintenance_mode",
        "ai_mentorship_enabled",
        "email_notifications",
        "push_notifications",
        "mfa_required",
        "rate_limiting_enabled",
        "encryption_at_rest",
        "encryption_in_transit",
    }:
        return _coerce_bool(val)
    if key in {
        "ai_daily_limit_per_user",
        "max_upload_size_mb",
        "session_timeout_minutes",
        "max_login_attempts",
        "api_requests_per_minute",
        "login_attempts_per_hour",
    }:
        return _coerce_int(val)
    return val


def update_system_settings(data: dict) -> dict[str, Any]:
    for key, val in data.items():
        canonical = _SETTING_ALIASES.get(key, key)
        if canonical not in _SYSTEM_SETTING_DEFAULTS:
            continue
        SystemSetting.set(canonical, _normalize_setting_value(canonical, val))
    invalidate_settings_cache()
    return get_system_settings()


def validate_password(password: str) -> tuple[bool, str]:
    settings = get_system_settings()
    policy = str(settings.get("password_policy") or "medium").lower()
    pattern, message = _PASSWORD_PATTERNS.get(policy, _PASSWORD_PATTERNS["medium"])
    if pattern.match(password or ""):
        return True, ""
    return False, message


def is_registration_enabled() -> bool:
    return _coerce_bool(get_system_settings().get("registration_enabled", True))


def is_ai_enabled() -> bool:
    return _coerce_bool(get_system_settings().get("ai_enabled", True))


def is_push_notifications_enabled() -> bool:
    return _coerce_bool(get_system_settings().get("push_notifications", True))


def is_email_notifications_enabled() -> bool:
    """Platform-wide switch. When false, no notification emails are sent."""
    return _coerce_bool(get_system_settings().get("email_notifications", True))


def is_maintenance_mode() -> bool:
    return _coerce_bool(get_system_settings().get("maintenance_mode", False))


def get_session_timeout_minutes() -> int:
    return max(5, _coerce_int(get_system_settings().get("session_timeout_minutes"), 60))


def get_upload_max_bytes() -> int:
    mb = max(1, _coerce_int(get_system_settings().get("max_upload_size_mb"), 10))
    return mb * 1024 * 1024


def get_allowed_file_extensions() -> set[str]:
    stored = {
        ext
        for ext in _parse_file_types(get_system_settings().get("allowed_file_types"))
        if ext.replace("+", "").replace("-", "").isalnum() and 1 <= len(ext) <= 8
    }
    # Existing installs were seeded with a list that blocked chat attachments
    # (camera photos as webp/heic, documents, audio, video). Expand only when
    # the stored value is still that original default.
    if not stored or stored == _LEGACY_DEFAULT_FILE_TYPES:
        return set(_DEFAULT_ALLOWED_FILE_TYPES)
    return stored


def get_public_settings() -> dict[str, Any]:
    settings = get_system_settings()
    return {
        "registration_enabled": settings["registration_enabled"],
        "maintenance_mode": settings["maintenance_mode"],
        "ai_enabled": settings["ai_enabled"],
        "max_upload_size_mb": settings["max_upload_size_mb"],
        "allowed_file_types": settings["allowed_file_types"],
    }
