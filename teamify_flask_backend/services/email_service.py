"""Centralized transactional email service.

All provider communication goes through this module. Routes and other
services must not call Resend (or any other mail API) directly.

Email is never considered sent unless the provider confirms submission.
Missing configuration, invalid recipients, and provider errors return a
failure/skip result and never raise into the request path.
"""
from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from typing import Any

from flask import current_app, has_app_context

logger = logging.getLogger(__name__)

# Practical address check — not a full RFC parser. Rejects empty / obviously bad values.
_EMAIL_RE = re.compile(r"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$")

# Keys that must never appear in logs even if a caller passes extra context.
_REDACT_KEYS = frozenset(
    {"api_key", "resend_api_key", "authorization", "otp", "otp_code", "password", "secret"}
)


@dataclass
class EmailResult:
    success: bool
    status: str  # sent | failed | skipped
    provider_message_id: str | None = None
    error: str | None = None
    extra: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "success": self.success,
            "status": self.status,
            "provider_message_id": self.provider_message_id,
            "error": self.error,
        }


def is_valid_email(address: str | None) -> bool:
    if not address or not isinstance(address, str):
        return False
    value = address.strip()
    if not value or len(value) > 254:
        return False
    return bool(_EMAIL_RE.match(value))


def _safe_error(exc: Exception) -> str:
    """Provider error text with secrets stripped."""
    text = str(exc) or exc.__class__.__name__
    for token in ("Bearer ", "re_"):
        if token in text:
            text = re.sub(r"(Bearer\s+)\S+", r"\1[redacted]", text)
            text = re.sub(r"re_[A-Za-z0-9]+", "re_[redacted]", text)
    return text[:500]


PLACEHOLDER_API_KEY = "re_xxxxxxxxx"


def _bare_from_address(raw: str | None) -> str:
    value = (raw or "").strip()
    if "<" in value and ">" in value:
        return value[value.find("<") + 1:value.find(">")].strip()
    return value


def _clean_setting(value: Any) -> str:
    text = str(value or "").strip()
    if len(text) >= 2 and text[0] == text[-1] and text[0] in {'"', "'"}:
        text = text[1:-1].strip()
    return text


def _read_mail_setting(*names: str) -> str:
    """Prefer live process env, then Flask config. Re-reads on every send."""
    import os

    for name in names:
        value = _clean_setting(os.getenv(name, ""))
        if value:
            return value
    if has_app_context():
        cfg = current_app.config
        for name in names:
            value = _clean_setting(cfg.get(name, ""))
            if value:
                return value
    return ""


def _mail_config() -> dict[str, str]:
    from_raw = _read_mail_setting("MAIL_FROM_ADDRESS", "RESEND_FROM_EMAIL")
    return {
        "provider": (_read_mail_setting("MAIL_PROVIDER") or "resend").lower(),
        "api_key": _read_mail_setting("RESEND_API_KEY"),
        "from_name": _read_mail_setting("MAIL_FROM_NAME") or "Teamify",
        "from_address": _bare_from_address(from_raw),
        "app_base_url": _read_mail_setting("MAIL_APP_BASE_URL").rstrip("/"),
    }


def mail_status() -> dict[str, Any]:
    """Public, secret-free snapshot of whether transactional email can send."""
    cfg = _mail_config()
    key_ok = bool(cfg["api_key"] and cfg["api_key"] != PLACEHOLDER_API_KEY)
    from_ok = bool(cfg["from_address"] and is_valid_email(cfg["from_address"]))
    provider_ok = cfg["provider"] in ("", "resend")
    return {
        "configured": bool(key_ok and from_ok and provider_ok),
        "provider": cfg["provider"] or "resend",
        "api_key_configured": key_ok,
        "from_configured": from_ok,
    }


def get_app_base_url() -> str:
    return _mail_config()["app_base_url"]


def preferences_url() -> str | None:
    base = get_app_base_url()
    if not base:
        return None
    return f"{base}/settings/email-notifications"


def app_cta_url(path: str = "/") -> str | None:
    base = get_app_base_url()
    if not base:
        return None
    if not path.startswith("/"):
        path = "/" + path
    return f"{base}{path}"


def is_mail_configured() -> bool:
    cfg = _mail_config()
    key = cfg["api_key"]
    return bool(
        key
        and key != PLACEHOLDER_API_KEY
        and cfg["from_address"]
        and is_valid_email(cfg["from_address"])
    )


def _formatted_from(cfg: dict[str, str]) -> str:
    name = cfg["from_name"].replace("<", "").replace(">", "").replace("\n", " ").strip()
    return f"{name} <{cfg['from_address']}>"


def _send_via_resend(
    *,
    to_address: str,
    subject: str,
    html: str,
    text: str | None,
    from_header: str,
    api_key: str,
) -> EmailResult:
    try:
        import resend
    except ImportError:
        logger.error("Resend package is not installed")
        return EmailResult(False, "failed", error="email provider library is not installed")

    payload: dict[str, Any] = {
        "from": from_header,
        "to": [to_address],
        "subject": subject,
        "html": html,
    }
    if text:
        payload["text"] = text

    try:
        resend.api_key = api_key
        response = resend.Emails.send(payload)
    except Exception as exc:
        logger.warning("Resend send failed: %s", _safe_error(exc))
        return EmailResult(False, "failed", error="email provider rejected the request")

    message_id = None
    if isinstance(response, dict):
        message_id = response.get("id") or response.get("message_id")
    elif response is not None:
        message_id = getattr(response, "id", None)

    if not message_id:
        # Treat missing id as failure so the UI never shows "Email Sent" without confirmation.
        logger.warning("Resend returned no message id")
        return EmailResult(False, "failed", error="email provider did not confirm submission")

    logger.info("Email submitted to provider message_id=%s", message_id)
    return EmailResult(True, "sent", provider_message_id=str(message_id))


def send_email(
    *,
    to: str,
    subject: str,
    html: str | None = None,
    html_body: str | None = None,
    text: str | None = None,
) -> EmailResult:
    """Send one HTML email with optional plain-text fallback.

    Never raises. Never logs API keys, OTPs, or full HTML bodies.
    ``html_body`` is accepted as an alias of ``html``.
    """
    html = html if html is not None else html_body
    recipient = (to or "").strip()
    if not is_valid_email(recipient):
        logger.info("Email skipped: invalid recipient")
        return EmailResult(False, "skipped", error="invalid recipient email")

    if not subject or not str(subject).strip():
        return EmailResult(False, "failed", error="missing email subject")
    if not html or not str(html).strip():
        return EmailResult(False, "failed", error="missing email html")

    cfg = _mail_config()
    if cfg["provider"] and cfg["provider"] not in ("resend",):
        logger.warning("Unsupported MAIL_PROVIDER=%s", cfg["provider"])
        return EmailResult(False, "skipped", error="unsupported mail provider")

    if not cfg["api_key"] or cfg["api_key"] == PLACEHOLDER_API_KEY:
        logger.warning("Email skipped: RESEND_API_KEY is missing or still the placeholder")
        return EmailResult(False, "skipped", error="email provider is not configured")
    if not cfg["from_address"]:
        logger.warning("Email skipped: MAIL_FROM_ADDRESS is not set")
        return EmailResult(False, "skipped", error="sender address is not configured")

    if not is_valid_email(cfg["from_address"]):
        logger.warning("Email skipped: MAIL_FROM_ADDRESS is invalid")
        return EmailResult(False, "skipped", error="sender address is not configured")

    try:
        if has_app_context() and current_app.config.get("TESTING") and not current_app.config.get("MAIL_SEND_IN_TESTS"):
            # Automated tests must never hit the real provider.
            logger.info("Email skipped: TESTING without MAIL_SEND_IN_TESTS")
            return EmailResult(False, "skipped", error="email sending disabled in tests")
    except Exception:
        pass

    return _send_via_resend(
        to_address=recipient,
        subject=str(subject).strip(),
        html=html,
        text=text,
        from_header=_formatted_from(cfg),
        api_key=cfg["api_key"],
    )


def send_notification_email(
    *,
    to: str,
    subject: str,
    html: str,
    text: str | None = None,
) -> EmailResult:
    """Alias used by notification delivery."""
    return send_email(to=to, subject=subject, html=html, text=text)


def send_password_reset_email(
    *,
    to: str,
    recipient_name: str,
    otp: str,
    expires_minutes: int = 10,
) -> EmailResult:
    from services.email_templates import password_reset_otp_email

    subject, html, text = password_reset_otp_email(
        recipient_name=recipient_name,
        otp=otp,
        expires_minutes=expires_minutes,
    )
    return send_email(to=to, subject=subject, html=html, text=text)


def send_team_invitation_email(
    *,
    to: str,
    recipient_name: str,
    inviter_name: str,
    project_name: str,
) -> EmailResult:
    from services.email_templates import team_invitation_email

    subject, html, text = team_invitation_email(
        recipient_name=recipient_name,
        inviter_name=inviter_name,
        project_name=project_name,
        cta_url=app_cta_url("/"),
        preferences_url=preferences_url(),
    )
    return send_email(to=to, subject=subject, html=html, text=text)


def send_task_assignment_email(
    *,
    to: str,
    recipient_name: str,
    task_title: str,
    project_name: str | None = None,
    due_date: str | None = None,
) -> EmailResult:
    from services.email_templates import task_assigned_email

    subject, html, text = task_assigned_email(
        recipient_name=recipient_name,
        task_title=task_title,
        project_name=project_name,
        due_date=due_date,
        cta_url=app_cta_url("/"),
        preferences_url=preferences_url(),
    )
    return send_email(to=to, subject=subject, html=html, text=text)


def send_deadline_email(
    *,
    to: str,
    recipient_name: str,
    task_title: str,
    due_label: str,
    project_name: str | None = None,
    overdue: bool = False,
) -> EmailResult:
    from services.email_templates import deadline_reminder_email, overdue_task_email

    if overdue:
        subject, html, text = overdue_task_email(
            recipient_name=recipient_name,
            task_title=task_title,
            overdue_label=due_label,
            project_name=project_name,
            cta_url=app_cta_url("/"),
            preferences_url=preferences_url(),
        )
    else:
        subject, html, text = deadline_reminder_email(
            recipient_name=recipient_name,
            task_title=task_title,
            due_label=due_label,
            project_name=project_name,
            cta_url=app_cta_url("/"),
            preferences_url=preferences_url(),
        )
    return send_email(to=to, subject=subject, html=html, text=text)


def send_announcement_email(
    *,
    to: str,
    recipient_name: str,
    title: str,
    body: str,
) -> EmailResult:
    from services.email_templates import announcement_email

    subject, html, text = announcement_email(
        recipient_name=recipient_name,
        title=title,
        body=body,
        cta_url=app_cta_url("/"),
        preferences_url=preferences_url(),
    )
    return send_email(to=to, subject=subject, html=html, text=text)


def is_configured() -> bool:
    """True when a real Resend API key is present (not the docs placeholder)."""
    key = _mail_config()["api_key"]
    return bool(key) and key != PLACEHOLDER_API_KEY


def is_email_configured() -> bool:
    return is_configured()


def user_email_pref_enabled(user, pref_key: str | None = None) -> bool:
    """Respect the per-user master switch and one optional specific switch."""
    prefs = getattr(user, "notification_prefs", None) or {}
    if not prefs.get("masterEmailEnabled", True):
        return False
    if pref_key is not None and not prefs.get(pref_key, True):
        return False
    return True


def send_password_reset_otp(
    *,
    to_email: str,
    otp: str,
    display_name: str | None = None,
) -> dict[str, Any] | None:
    """Compatibility wrapper used by older call sites and tests."""
    result = send_password_reset_email(
        to=to_email,
        recipient_name=display_name or "there",
        otp=otp,
    )
    if result.success:
        return {"id": result.provider_message_id}
    return None


def send_project_invitation_email(
    *,
    to_email: str,
    invitee_name: str | None,
    inviter_name: str,
    project_name: str,
) -> dict[str, Any] | None:
    """Compatibility wrapper; new code should use notification emails."""
    result = send_team_invitation_email(
        to=to_email,
        recipient_name=invitee_name or "there",
        inviter_name=inviter_name,
        project_name=project_name,
    )
    if result.success:
        return {"id": result.provider_message_id}
    return None


def send_connection_request_email(addressee, requester_name: str) -> EmailResult | None:
    """Connection request email (respects user preferences)."""
    to_email = getattr(addressee, "email", None)
    if not to_email or not user_email_pref_enabled(addressee):
        return None
    name = addressee.full_name or addressee.display_name or "there"
    return send_announcement_email(
        to=to_email,
        recipient_name=name,
        title="New connection request",
        body=f"{requester_name} sent you a connection request on Teamify.",
    )
