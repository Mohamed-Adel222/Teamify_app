"""Transactional email via the Resend API.

Set RESEND_API_KEY in your environment (replace ``re_xxxxxxxxx`` with your
real key). The live key must never be committed to source control.
"""
from __future__ import annotations

import html
import logging
import os
from typing import Any

logger = logging.getLogger(__name__)

PLACEHOLDER_API_KEY = "re_xxxxxxxxx"
DEFAULT_FROM = "Teamify <onboarding@resend.dev>"


def _from_flask_config(name: str) -> str | None:
    """Return the Flask config value when an app context is active.

    Distinguishes "not in an app" (None) from an explicit empty override (""),
    so tests can disable sending even when a key is present in the process env.
    """
    try:
        from flask import current_app, has_app_context

        if has_app_context() and name in current_app.config:
            value = current_app.config.get(name)
            return "" if value is None else str(value).strip()
    except Exception:
        pass
    return None


def _api_key() -> str:
    from_app = _from_flask_config("RESEND_API_KEY")
    if from_app is not None:
        return from_app
    return (os.getenv("RESEND_API_KEY") or "").strip()


def _from_address() -> str:
    from_app = _from_flask_config("RESEND_FROM_EMAIL")
    if from_app:
        return from_app
    return (os.getenv("RESEND_FROM_EMAIL") or "").strip() or DEFAULT_FROM


def is_configured() -> bool:
    """True when a real Resend API key is present (not the docs placeholder)."""
    key = _api_key()
    return bool(key) and key != PLACEHOLDER_API_KEY


def send_email(
    *,
    to: str | list[str],
    subject: str,
    html_body: str,
) -> dict[str, Any] | None:
    """Send an HTML email through Resend.

    Returns the Resend response dict on success, or None when the provider
    is not configured or the send fails. Never raises.
    """
    if not is_configured():
        logger.info("RESEND_API_KEY is not set; skipping email %r", subject)
        return None

    try:
        import resend
    except ImportError:
        logger.warning("The resend package is not installed; skipping email")
        return None

    recipients = [to] if isinstance(to, str) else [addr for addr in to if addr]
    recipients = [addr.strip() for addr in recipients if addr and addr.strip()]
    if not recipients:
        logger.warning("No recipients for email %r", subject)
        return None

    resend.api_key = _api_key()
    params = {
        "from": _from_address(),
        "to": recipients,
        "subject": subject,
        "html": html_body,
    }
    try:
        result = resend.Emails.send(params)
    except Exception:
        logger.exception("Resend failed to send email %r", subject)
        return None

    if isinstance(result, dict):
        return result
    return {"id": getattr(result, "id", None)}


def send_password_reset_otp(
    *,
    to_email: str,
    otp: str,
    display_name: str | None = None,
) -> dict[str, Any] | None:
    """Send the 6-digit password-reset code. Always attempted (transactional)."""
    name = html.escape((display_name or "there").strip() or "there")
    code = html.escape(str(otp))
    return send_email(
        to=to_email,
        subject="Your Teamify password reset code",
        html_body=(
            f"<p>Hi {name},</p>"
            "<p>Use this code to reset your Teamify password. It expires in 10 minutes:</p>"
            f"<p style=\"font-size:24px;letter-spacing:4px;font-weight:bold\">{code}</p>"
            "<p>If you did not request this, you can ignore this email.</p>"
        ),
    )


def send_project_invitation_email(
    *,
    to_email: str,
    invitee_name: str | None,
    inviter_name: str,
    project_name: str,
) -> dict[str, Any] | None:
    """Notify someone they were invited to a project."""
    greeting = html.escape((invitee_name or "there").strip() or "there")
    inviter = html.escape(inviter_name)
    project = html.escape(project_name)
    return send_email(
        to=to_email,
        subject=f"You're invited to join {project_name} on Teamify",
        html_body=(
            f"<p>Hi {greeting},</p>"
            f"<p>{inviter} invited you to join <strong>{project}</strong> on Teamify.</p>"
            "<p>Open the app to accept or decline the invitation.</p>"
        ),
    )
