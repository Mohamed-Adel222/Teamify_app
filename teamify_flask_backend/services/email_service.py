"""Outbound email via SMTP.

Configuration (environment variables):
    SMTP_HOST       e.g. smtp.gmail.com
    SMTP_PORT       default 587
    SMTP_USERNAME   SMTP login (usually the sender address)
    SMTP_PASSWORD   SMTP password / app password
    SMTP_USE_TLS    default true (STARTTLS)
    MAIL_FROM       sender address (defaults to SMTP_USERNAME)
    MAIL_FROM_NAME  display name, default "Teamify"

When SMTP is not configured, sending is a logged no-op so the API keeps
working — but nothing is delivered.
"""
from __future__ import annotations

import logging
import os
import smtplib
import threading
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.utils import formataddr

logger = logging.getLogger(__name__)


def _smtp_settings() -> dict:
    return {
        "host": os.getenv("SMTP_HOST", "").strip(),
        "port": int(os.getenv("SMTP_PORT", "587") or 587),
        "username": os.getenv("SMTP_USERNAME", "").strip(),
        "password": os.getenv("SMTP_PASSWORD", ""),
        "use_tls": os.getenv("SMTP_USE_TLS", "true").lower() in ("1", "true", "yes"),
        "from_addr": os.getenv("MAIL_FROM", "").strip()
                     or os.getenv("SMTP_USERNAME", "").strip(),
        "from_name": os.getenv("MAIL_FROM_NAME", "Teamify").strip() or "Teamify",
    }


def is_email_configured() -> bool:
    s = _smtp_settings()
    return bool(s["host"] and s["from_addr"])


def _admin_email_enabled() -> bool:
    """Global admin toggle (system settings) — defaults to enabled."""
    try:
        from services.system_settings_service import get_system_settings
        return bool(get_system_settings().get("email_notifications", True))
    except Exception:
        return True


def user_email_pref_enabled(user, pref_key: str | None = None) -> bool:
    """Respect the per-user master switch and one optional specific switch."""
    prefs = getattr(user, "notification_prefs", None) or {}
    if not prefs.get("masterEmailEnabled", True):
        return False
    if pref_key is not None and not prefs.get(pref_key, True):
        return False
    return True


def _deliver(to_addr: str, subject: str, text_body: str, html_body: str | None) -> None:
    s = _smtp_settings()
    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = formataddr((s["from_name"], s["from_addr"]))
    msg["To"] = to_addr
    msg.attach(MIMEText(text_body, "plain", "utf-8"))
    if html_body:
        msg.attach(MIMEText(html_body, "html", "utf-8"))

    try:
        if s["use_tls"]:
            server = smtplib.SMTP(s["host"], s["port"], timeout=20)
            server.ehlo()
            server.starttls()
        else:
            server = smtplib.SMTP_SSL(s["host"], s["port"], timeout=20)
        try:
            if s["username"]:
                server.login(s["username"], s["password"])
            server.sendmail(s["from_addr"], [to_addr], msg.as_string())
            logger.info("Email sent to %s: %s", to_addr, subject)
        finally:
            server.quit()
    except Exception as exc:
        logger.error("Email delivery to %s failed: %s", to_addr, exc)


def send_email(
    to_addr: str,
    subject: str,
    text_body: str,
    html_body: str | None = None,
    *,
    blocking: bool = False,
) -> bool:
    """Queue an email for delivery. Returns False when not configured/disabled."""
    if not to_addr:
        return False
    if not is_email_configured():
        logger.warning(
            "SMTP not configured (set SMTP_HOST/SMTP_USERNAME/SMTP_PASSWORD) — "
            "email to %s NOT sent: %s", to_addr, subject,
        )
        return False
    if not _admin_email_enabled():
        logger.info("Email notifications disabled by admin — skipping %s", subject)
        return False

    if blocking:
        _deliver(to_addr, subject, text_body, html_body)
    else:
        threading.Thread(
            target=_deliver,
            args=(to_addr, subject, text_body, html_body),
            daemon=True,
        ).start()
    return True


# ─── Message templates ────────────────────────────────────────────────────────

def _html_wrapper(title: str, body_html: str) -> str:
    return f"""\
<div style="font-family:Arial,Helvetica,sans-serif;max-width:520px;margin:0 auto;
            border:1px solid #e3e8ef;border-radius:12px;overflow:hidden">
  <div style="background:#1d6fa5;color:#ffffff;padding:18px 24px;
              font-size:18px;font-weight:bold">Teamify</div>
  <div style="padding:24px">
    <h2 style="margin:0 0 12px;font-size:17px;color:#16324f">{title}</h2>
    {body_html}
  </div>
  <div style="padding:14px 24px;background:#f5f8fb;color:#7b8794;font-size:12px">
    You are receiving this email because you have a Teamify account.
  </div>
</div>"""


def send_otp_email(user, otp: str) -> bool:
    """Password-reset OTP. Always sent (account security, ignores prefs)."""
    subject = "Your Teamify password reset code"
    text = (
        f"Hello {user.full_name or user.display_name},\n\n"
        f"Your password reset code is: {otp}\n"
        "It expires in 10 minutes. If you did not request this, "
        "you can ignore this email.\n"
    )
    html = _html_wrapper(
        "Password reset code",
        f"<p>Use this code to reset your password:</p>"
        f"<p style='font-size:28px;font-weight:bold;letter-spacing:6px;"
        f"color:#1d6fa5'>{otp}</p>"
        f"<p>The code expires in <b>10 minutes</b>. If you did not request "
        f"this, you can safely ignore this email.</p>",
    )
    return send_email(user.email, subject, text, html)


def send_project_invitation_email(invitee, inviter_name: str, project_name: str) -> bool:
    """Project invitation notification email (respects user preferences)."""
    if not user_email_pref_enabled(invitee, "emailTeamInvitations"):
        return False
    subject = f"You're invited to join \"{project_name}\" on Teamify"
    text = (
        f"Hello {invitee.full_name or invitee.display_name},\n\n"
        f"{inviter_name} invited you to join the project \"{project_name}\" "
        "on Teamify.\nOpen the app and check your notifications to accept "
        "or decline.\n"
    )
    html = _html_wrapper(
        f"Invitation to {project_name}",
        f"<p><b>{inviter_name}</b> invited you to join the project "
        f"<b>{project_name}</b>.</p>"
        f"<p>Open Teamify and check your notifications to accept or decline "
        f"the invitation.</p>",
    )
    return send_email(invitee.email, subject, text, html)


def send_connection_request_email(addressee, requester_name: str) -> bool:
    """Connection request email (respects user preferences)."""
    if not user_email_pref_enabled(addressee):
        return False
    subject = f"{requester_name} wants to connect on Teamify"
    text = (
        f"Hello {addressee.full_name or addressee.display_name},\n\n"
        f"{requester_name} sent you a connection request on Teamify.\n"
        "Open their profile from the Search screen to accept.\n"
    )
    html = _html_wrapper(
        "New connection request",
        f"<p><b>{requester_name}</b> wants to connect with you on Teamify.</p>"
        f"<p>Open their profile from the Search screen to accept the "
        f"request.</p>",
    )
    return send_email(addressee.email, subject, text, html)
