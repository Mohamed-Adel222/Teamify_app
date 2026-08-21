from unittest.mock import patch
import types

from services.email_service import (
    EmailResult,
    PLACEHOLDER_API_KEY,
    is_configured,
    send_email,
    send_password_reset_otp,
    send_project_invitation_email,
)


class TestIsConfigured:
    def test_missing_key(self, monkeypatch):
        monkeypatch.delenv("RESEND_API_KEY", raising=False)
        monkeypatch.delenv("MAIL_FROM_ADDRESS", raising=False)
        monkeypatch.delenv("RESEND_FROM_EMAIL", raising=False)
        assert is_configured() is False

    def test_placeholder_key(self, monkeypatch):
        monkeypatch.setenv("RESEND_API_KEY", PLACEHOLDER_API_KEY)
        assert is_configured() is False

    def test_real_looking_key(self, monkeypatch):
        monkeypatch.setenv("RESEND_API_KEY", "re_test_not_a_real_key")
        assert is_configured() is True

    def test_live_env_is_used_when_flask_config_empty(self, monkeypatch):
        monkeypatch.setenv("RESEND_API_KEY", "re_from_env")
        monkeypatch.setenv("MAIL_FROM_ADDRESS", "no-reply@example.com")
        monkeypatch.setattr(
            "services.email_service.has_app_context", lambda: True
        )
        monkeypatch.setattr(
            "services.email_service.current_app",
            types.SimpleNamespace(config={"RESEND_API_KEY": "", "MAIL_FROM_ADDRESS": ""}),
        )
        from services.email_service import is_mail_configured, mail_status

        assert is_configured() is True
        assert is_mail_configured() is True
        assert mail_status()["configured"] is True


class TestSendEmail:
    def test_skips_when_unconfigured(self, monkeypatch):
        monkeypatch.delenv("RESEND_API_KEY", raising=False)
        result = send_email(to="a@b.com", subject="Hi", html_body="<p>x</p>")
        assert result.success is False
        assert result.status == "skipped"

    @patch("resend.Emails.send")
    def test_sends_via_resend(self, m_send, monkeypatch):
        monkeypatch.setenv("RESEND_API_KEY", "re_test_not_a_real_key")
        monkeypatch.setenv("RESEND_FROM_EMAIL", "Teamify <onboarding@resend.dev>")
        m_send.return_value = {"id": "email_123"}

        result = send_email(
            to="member@example.com",
            subject="Hello World",
            html_body="<p>Congrats on sending your <strong>first email</strong>!</p>",
        )

        assert result.success is True
        assert result.provider_message_id == "email_123"
        m_send.assert_called_once()
        params = m_send.call_args[0][0]
        assert params["from"] == "Teamify <onboarding@resend.dev>"
        assert params["to"] == ["member@example.com"]
        assert params["subject"] == "Hello World"
        assert "first email" in params["html"]

    @patch("resend.Emails.send", side_effect=RuntimeError("network"))
    def test_send_failure_returns_failed(self, _m_send, monkeypatch):
        monkeypatch.setenv("RESEND_API_KEY", "re_test_not_a_real_key")
        monkeypatch.setenv("MAIL_FROM_ADDRESS", "teamify@example.com")
        result = send_email(to="a@b.com", subject="Hi", html_body="<p>x</p>")
        assert result.success is False
        assert result.status == "failed"

    def test_empty_recipient_is_skipped(self, monkeypatch):
        monkeypatch.setenv("RESEND_API_KEY", "re_test_not_a_real_key")
        result = send_email(to="  ", subject="Hi", html_body="<p>x</p>")
        assert result.success is False
        assert result.status == "skipped"


class TestTransactionalHelpers:
    @patch(
        "services.email_service.send_email",
        return_value=EmailResult(True, "sent", provider_message_id="otp"),
    )
    def test_password_reset_otp_escapes_html(self, m_send):
        send_password_reset_otp(
            to_email="a@b.com",
            otp="123456",
            display_name="<script>alert(1)</script>",
        )
        html_body = m_send.call_args.kwargs["html"]
        assert "&lt;script&gt;" in html_body
        assert "123456" in html_body
        assert m_send.call_args.kwargs["to"] == "a@b.com"

    @patch(
        "services.email_service.send_email",
        return_value=EmailResult(True, "sent", provider_message_id="invite"),
    )
    def test_project_invitation_escapes_html(self, m_send):
        send_project_invitation_email(
            to_email="invitee@example.com",
            invitee_name="Alex",
            inviter_name="Sam <admin>",
            project_name="Q2 & Launch",
        )
        html_body = m_send.call_args.kwargs["html"]
        assert "Sam &lt;admin&gt;" in html_body
        assert "Q2 &amp; Launch" in html_body
        assert "<admin>" not in html_body
