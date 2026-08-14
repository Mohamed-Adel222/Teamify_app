"""Professional Teamify HTML + plain-text email templates.

All templates share one sender identity. CTA URLs are omitted when the
app base URL is not configured so we never invent a production domain.
"""
from __future__ import annotations

import html
from typing import Any


BRAND_PRIMARY = "#2B70A4"
BRAND_DARK = "#1E527D"
BRAND_BG = "#F8FAFC"
BRAND_TEXT = "#0F172A"
BRAND_MUTED = "#64748B"
BRAND_BORDER = "#E2E8F0"
BRAND_WHITE = "#FFFFFF"


def _esc(value: Any) -> str:
    return html.escape("" if value is None else str(value), quote=True)


def _cta_block(label: str | None, url: str | None) -> str:
    if not label or not url:
        return ""
    return f"""
      <tr>
        <td align="center" style="padding: 8px 32px 28px 32px;">
          <a href="{_esc(url)}"
             style="display:inline-block;background:{BRAND_PRIMARY};color:{BRAND_WHITE};
                    font-family:Arial,Helvetica,sans-serif;font-size:15px;font-weight:bold;
                    text-decoration:none;padding:12px 24px;border-radius:8px;">
            {_esc(label)}
          </a>
        </td>
      </tr>"""


def _footer_html(*, preferences_url: str | None, include_unsubscribe: bool) -> str:
    prefs = ""
    if include_unsubscribe and preferences_url:
        prefs = (
            f'<br><a href="{_esc(preferences_url)}" '
            f'style="color:{BRAND_MUTED};text-decoration:underline;">'
            f"Manage email preferences</a>"
        )
    elif include_unsubscribe:
        prefs = (
            "<br>You can change email preferences in the Teamify app "
            "(Profile → Email Notifications)."
        )
    return f"""
      <tr>
        <td style="padding: 20px 32px 28px 32px;border-top:1px solid {BRAND_BORDER};
                   font-family:Arial,Helvetica,sans-serif;font-size:12px;color:{BRAND_MUTED};
                   line-height:18px;">
          This message was sent by Teamify.
          {prefs}
          <br>Please do not reply to this email.
        </td>
      </tr>"""


def render_email(
    *,
    preheader: str,
    title: str,
    intro: str,
    rows: list[tuple[str, str]] | None = None,
    extra_html: str = "",
    cta_label: str | None = None,
    cta_url: str | None = None,
    preferences_url: str | None = None,
    include_unsubscribe: bool = True,
) -> tuple[str, str]:
    """Return (html, text) for a Teamify branded email."""
    detail_rows = ""
    text_rows = []
    for label, value in rows or []:
        if value in (None, ""):
            continue
        detail_rows += f"""
          <tr>
            <td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:13px;color:{BRAND_MUTED};width:140px;vertical-align:top;">{_esc(label)}</td>
            <td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:13px;color:{BRAND_TEXT};font-weight:bold;">{_esc(value)}</td>
          </tr>"""
        text_rows.append(f"{label}: {value}")

    details_table = (
        f'<table role="presentation" width="100%" cellspacing="0" cellpadding="0">{detail_rows}</table>'
        if detail_rows
        else ""
    )

    html_body = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{_esc(title)}</title>
</head>
<body style="margin:0;padding:0;background:{BRAND_BG};">
  <span style="display:none !important;visibility:hidden;opacity:0;color:transparent;height:0;width:0;">
    {_esc(preheader)}
  </span>
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:{BRAND_BG};padding:24px 12px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:560px;background:{BRAND_WHITE};border-radius:12px;overflow:hidden;border:1px solid {BRAND_BORDER};">
          <tr>
            <td style="background:{BRAND_PRIMARY};padding:20px 32px;font-family:Arial,Helvetica,sans-serif;font-size:20px;font-weight:bold;color:{BRAND_WHITE};">
              Teamify
            </td>
          </tr>
          <tr>
            <td style="padding:28px 32px 8px 32px;font-family:Arial,Helvetica,sans-serif;font-size:22px;font-weight:bold;color:{BRAND_TEXT};">
              {_esc(title)}
            </td>
          </tr>
          <tr>
            <td style="padding:8px 32px 16px 32px;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:{BRAND_MUTED};line-height:22px;">
              {_esc(intro)}
            </td>
          </tr>
          <tr>
            <td style="padding:0 32px 16px 32px;">
              {details_table}
              {extra_html}
            </td>
          </tr>
          {_cta_block(cta_label, cta_url)}
          {_footer_html(preferences_url=preferences_url, include_unsubscribe=include_unsubscribe)}
        </table>
      </td>
    </tr>
  </table>
</body>
</html>"""

    text_parts = [
        "Teamify",
        "",
        title,
        "",
        intro,
    ]
    if text_rows:
        text_parts.append("")
        text_parts.extend(text_rows)
    if cta_label and cta_url:
        text_parts.extend(["", f"{cta_label}: {cta_url}"])
    text_parts.extend(["", "This message was sent by Teamify. Please do not reply."])
    if include_unsubscribe:
        if preferences_url:
            text_parts.append(f"Manage email preferences: {preferences_url}")
        else:
            text_parts.append("You can change email preferences in the Teamify app.")
    return html_body, "\n".join(text_parts)


def team_invitation_email(
    *,
    recipient_name: str,
    inviter_name: str,
    project_name: str,
    cta_url: str | None,
    preferences_url: str | None,
) -> tuple[str, str, str]:
    greeting = recipient_name or "there"
    subject = f"You're invited to join {project_name} on Teamify"
    html_body, text = render_email(
        preheader=f"{inviter_name} invited you to {project_name}",
        title="Project invitation",
        intro=f"Hi {greeting}, {inviter_name} invited you to join a project on Teamify.",
        rows=[
            ("Project", project_name),
            ("Invited by", inviter_name),
        ],
        cta_label="View invitation",
        cta_url=cta_url,
        preferences_url=preferences_url,
    )
    return subject, html_body, text


def invitation_accepted_email(
    *,
    owner_name: str,
    invitee_name: str,
    project_name: str,
    cta_url: str | None,
    preferences_url: str | None,
) -> tuple[str, str, str]:
    greeting = owner_name or "there"
    subject = f"{invitee_name} joined {project_name}"
    html_body, text = render_email(
        preheader=f"{invitee_name} accepted your invitation",
        title="Invitation accepted",
        intro=f"Hi {greeting}, {invitee_name} accepted your invitation and joined the project.",
        rows=[
            ("Project", project_name),
            ("New member", invitee_name),
        ],
        cta_label="Open project",
        cta_url=cta_url,
        preferences_url=preferences_url,
    )
    return subject, html_body, text


def task_assigned_email(
    *,
    recipient_name: str,
    task_title: str,
    project_name: str | None,
    due_date: str | None,
    cta_url: str | None,
    preferences_url: str | None,
) -> tuple[str, str, str]:
    greeting = recipient_name or "there"
    subject = f"New task assigned: {task_title}"
    html_body, text = render_email(
        preheader="You have a new task on Teamify",
        title="Task assigned",
        intro=f"Hi {greeting}, a task has been assigned to you.",
        rows=[
            ("Task", task_title),
            ("Project", project_name or ""),
            ("Due", due_date or ""),
        ],
        cta_label="View task",
        cta_url=cta_url,
        preferences_url=preferences_url,
    )
    return subject, html_body, text


def task_updated_email(
    *,
    recipient_name: str,
    task_title: str,
    change_summary: str,
    project_name: str | None,
    cta_url: str | None,
    preferences_url: str | None,
) -> tuple[str, str, str]:
    greeting = recipient_name or "there"
    subject = f"Task updated: {task_title}"
    html_body, text = render_email(
        preheader="A task assigned to you was updated",
        title="Task updated",
        intro=f"Hi {greeting}, a task assigned to you was updated.",
        rows=[
            ("Task", task_title),
            ("Project", project_name or ""),
            ("Update", change_summary),
        ],
        cta_label="View task",
        cta_url=cta_url,
        preferences_url=preferences_url,
    )
    return subject, html_body, text


def deadline_reminder_email(
    *,
    recipient_name: str,
    task_title: str,
    due_label: str,
    project_name: str | None,
    cta_url: str | None,
    preferences_url: str | None,
) -> tuple[str, str, str]:
    greeting = recipient_name or "there"
    subject = f"Deadline reminder: {task_title}"
    html_body, text = render_email(
        preheader=f"{task_title} {due_label}",
        title="Deadline reminder",
        intro=f"Hi {greeting}, a task assigned to you is approaching its deadline.",
        rows=[
            ("Task", task_title),
            ("Project", project_name or ""),
            ("Deadline", due_label),
        ],
        cta_label="View task",
        cta_url=cta_url,
        preferences_url=preferences_url,
    )
    return subject, html_body, text


def overdue_task_email(
    *,
    recipient_name: str,
    task_title: str,
    overdue_label: str,
    project_name: str | None,
    cta_url: str | None,
    preferences_url: str | None,
) -> tuple[str, str, str]:
    greeting = recipient_name or "there"
    subject = f"Overdue task: {task_title}"
    html_body, text = render_email(
        preheader=f"{task_title} is overdue",
        title="Task overdue",
        intro=f"Hi {greeting}, a task assigned to you is overdue.",
        rows=[
            ("Task", task_title),
            ("Project", project_name or ""),
            ("Status", overdue_label),
        ],
        cta_label="View task",
        cta_url=cta_url,
        preferences_url=preferences_url,
    )
    return subject, html_body, text


def chat_message_email(
    *,
    recipient_name: str,
    sender_name: str,
    room_name: str,
    preview: str,
    is_mention: bool,
    cta_url: str | None,
    preferences_url: str | None,
) -> tuple[str, str, str]:
    greeting = recipient_name or "there"
    if is_mention:
        subject = f"{sender_name} mentioned you in {room_name}"
        title = "You were mentioned"
        intro = f"Hi {greeting}, {sender_name} mentioned you in a Teamify conversation."
    else:
        subject = f"New message from {sender_name}"
        title = "New message"
        intro = f"Hi {greeting}, you have a new message on Teamify."
    html_body, text = render_email(
        preheader=preview[:80] if preview else "New Teamify message",
        title=title,
        intro=intro,
        rows=[
            ("From", sender_name),
            ("Conversation", room_name),
            ("Message", preview),
        ],
        cta_label="Open conversation",
        cta_url=cta_url,
        preferences_url=preferences_url,
    )
    return subject, html_body, text


def announcement_email(
    *,
    recipient_name: str,
    title: str,
    body: str,
    cta_url: str | None,
    preferences_url: str | None,
) -> tuple[str, str, str]:
    greeting = recipient_name or "there"
    subject = f"Teamify announcement: {title}"
    html_body, text_body = render_email(
        preheader=title,
        title="Announcement",
        intro=f"Hi {greeting}, there is a new announcement from Teamify.",
        rows=[
            ("Title", title),
            ("Message", body),
        ],
        cta_label="Open Teamify",
        cta_url=cta_url,
        preferences_url=preferences_url,
    )
    return subject, html_body, text_body


def role_changed_email(
    *,
    recipient_name: str,
    new_role: str,
    context_label: str | None,
    cta_url: str | None,
    preferences_url: str | None,
) -> tuple[str, str, str]:
    greeting = recipient_name or "there"
    subject = "Your Teamify role was updated"
    html_body, text = render_email(
        preheader="Your role was updated",
        title="Role updated",
        intro=f"Hi {greeting}, your role on Teamify was changed.",
        rows=[
            ("New role", new_role),
            ("Details", context_label or ""),
        ],
        cta_label="Open Teamify",
        cta_url=cta_url,
        preferences_url=preferences_url,
    )
    return subject, html_body, text


def membership_changed_email(
    *,
    recipient_name: str,
    project_name: str,
    cta_url: str | None,
    preferences_url: str | None,
) -> tuple[str, str, str]:
    greeting = recipient_name or "there"
    subject = f"You were removed from {project_name}"
    html_body, text = render_email(
        preheader=f"Membership update for {project_name}",
        title="Project membership update",
        intro=f"Hi {greeting}, you are no longer a member of this project.",
        rows=[("Project", project_name)],
        cta_label="Open Teamify",
        cta_url=cta_url,
        preferences_url=preferences_url,
    )
    return subject, html_body, text


def password_reset_otp_email(
    *,
    recipient_name: str,
    otp: str,
    expires_minutes: int,
) -> tuple[str, str, str]:
    greeting = recipient_name or "there"
    subject = "Your Teamify password reset code"
    otp_html = f"""
      <div style="margin:12px 0 8px 0;padding:16px;background:{BRAND_BG};border:1px dashed {BRAND_PRIMARY};
                  border-radius:8px;text-align:center;font-family:Arial,Helvetica,sans-serif;
                  font-size:28px;letter-spacing:8px;font-weight:bold;color:{BRAND_DARK};">
        {_esc(otp)}
      </div>
      <p style="font-family:Arial,Helvetica,sans-serif;font-size:13px;color:{BRAND_MUTED};margin:0;">
        This code expires in {_esc(expires_minutes)} minutes.
      </p>"""
    html_body, text = render_email(
        preheader="Use this code to reset your Teamify password",
        title="Password reset",
        intro=(
            f"Hi {greeting}, use the one-time code below to reset your Teamify password. "
            "If you did not request this, you can ignore this email and your password will stay the same."
        ),
        extra_html=otp_html,
        include_unsubscribe=False,
    )
    text = (
        f"Teamify password reset\n\n"
        f"Hi {greeting},\n\n"
        f"Your one-time password reset code is: {otp}\n"
        f"This code expires in {expires_minutes} minutes.\n\n"
        "If you did not request this, ignore this email and your password will stay the same.\n"
    )
    return subject, html_body, text
