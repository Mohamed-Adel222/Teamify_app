"""
Tests for Teamify transactional email notifications.

The Resend provider is always mocked. These tests never send real email.
"""
from datetime import date, datetime, timezone, timedelta
from unittest.mock import MagicMock, patch

import pytest

from tests.conftest import MEMBER_USER_ID, _make_user


def _user(uid=MEMBER_USER_ID, email="member@example.com", prefs=None):
    user = _make_user(uid)
    user.email = email
    user.notification_prefs = prefs or {}
    user.full_name = "Ada Lovelace"
    user.display_name = "ada"
    return user


class TestEmailValidation:
    def test_valid_address(self):
        from services.email_service import is_valid_email

        assert is_valid_email("ada@example.com") is True

    def test_invalid_recipient(self):
        from services.email_service import is_valid_email, send_email

        assert is_valid_email("not-an-email") is False
        assert is_valid_email("") is False
        assert is_valid_email(None) is False
        result = send_email(to="not-an-email", subject="Hi", html="<p>Hi</p>")
        assert result.success is False
        assert result.status == "skipped"
        assert result.error == "invalid recipient email"


class TestEmailServiceProvider:
    def test_success(self, app):
        from services.email_service import send_email

        with app.app_context():
            app.config["TESTING"] = True
            app.config["MAIL_SEND_IN_TESTS"] = True
            app.config["RESEND_API_KEY"] = "re_test_key"
            app.config["MAIL_FROM_ADDRESS"] = "no-reply@example.com"
            app.config["MAIL_FROM_NAME"] = "Teamify"
            with patch(
                "services.email_service._send_via_resend",
                return_value=__import__(
                    "services.email_service", fromlist=["EmailResult"]
                ).EmailResult(True, "sent", provider_message_id="msg_123"),
            ) as mocked:
                result = send_email(
                    to="ada@example.com",
                    subject="Hello",
                    html="<p>Hello</p>",
                    text="Hello",
                )
        assert result.success is True
        assert result.status == "sent"
        assert result.provider_message_id == "msg_123"
        mocked.assert_called_once()

    def test_provider_failure(self, app):
        from services.email_service import EmailResult, send_email

        with app.app_context():
            app.config["MAIL_SEND_IN_TESTS"] = True
            app.config["RESEND_API_KEY"] = "re_test_key"
            app.config["MAIL_FROM_ADDRESS"] = "no-reply@example.com"
            with patch(
                "services.email_service._send_via_resend",
                return_value=EmailResult(False, "failed", error="email provider rejected the request"),
            ):
                result = send_email(
                    to="ada@example.com",
                    subject="Hello",
                    html="<p>Hello</p>",
                )
        assert result.success is False
        assert result.status == "failed"
        assert result.provider_message_id is None

    def test_unconfigured_provider_skips(self, app):
        from services.email_service import send_email

        with app.app_context():
            app.config["MAIL_SEND_IN_TESTS"] = True
            app.config["RESEND_API_KEY"] = ""
            app.config["MAIL_FROM_ADDRESS"] = ""
            result = send_email(to="ada@example.com", subject="Hello", html="<p>x</p>")
        assert result.success is False
        assert result.status == "skipped"

    def test_resend_exception_is_failure(self, app):
        from services.email_service import send_email

        with app.app_context():
            app.config["MAIL_SEND_IN_TESTS"] = True
            app.config["RESEND_API_KEY"] = "re_test_key"
            app.config["MAIL_FROM_ADDRESS"] = "no-reply@example.com"

            class _Emails:
                @staticmethod
                def send(payload):
                    raise RuntimeError("boom Bearer re_secretvalue")

            fake_resend = MagicMock()
            fake_resend.Emails = _Emails
            with patch.dict("sys.modules", {"resend": fake_resend}):
                result = send_email(to="ada@example.com", subject="Hello", html="<p>x</p>")
        assert result.success is False
        assert result.status == "failed"
        assert result.error == "email provider rejected the request"

    def test_missing_message_id_is_not_sent(self, app):
        from services.email_service import send_email

        with app.app_context():
            app.config["MAIL_SEND_IN_TESTS"] = True
            app.config["RESEND_API_KEY"] = "re_test_key"
            app.config["MAIL_FROM_ADDRESS"] = "no-reply@example.com"

            class _Emails:
                @staticmethod
                def send(payload):
                    return {}

            fake_resend = MagicMock()
            fake_resend.Emails = _Emails
            with patch.dict("sys.modules", {"resend": fake_resend}):
                result = send_email(to="ada@example.com", subject="Hello", html="<p>x</p>")
        assert result.success is False
        assert result.status == "failed"


class TestPreferenceGating:
    def test_admin_email_setting_disabled(self):
        from services.notification_email_service import evaluate_email_permission

        with patch(
            "services.notification_email_service.is_email_notifications_enabled",
            return_value=False,
        ):
            allowed, reason = evaluate_email_permission(_user(), "task_assigned")
        assert allowed is False
        assert reason == "admin_disabled"

    def test_master_email_disabled(self):
        from services.notification_email_service import evaluate_email_permission

        with patch(
            "services.notification_email_service.is_email_notifications_enabled",
            return_value=True,
        ):
            allowed, reason = evaluate_email_permission(
                _user(prefs={"masterEmailEnabled": False}),
                "task_assigned",
            )
        assert allowed is False
        assert reason == "master_email_disabled"

    def test_category_preference_disabled(self):
        from services.notification_email_service import evaluate_email_permission

        with patch(
            "services.notification_email_service.is_email_notifications_enabled",
            return_value=True,
        ):
            allowed, reason = evaluate_email_permission(
                _user(prefs={"emailTaskAssignments": False}),
                "task_assigned",
            )
        assert allowed is False
        assert reason == "category_disabled"

    def test_defaults_allow_invitation(self):
        from services.notification_email_service import evaluate_email_permission

        with patch(
            "services.notification_email_service.is_email_notifications_enabled",
            return_value=True,
        ):
            allowed, reason = evaluate_email_permission(_user(), "project_invitation")
        assert allowed is True
        assert reason is None

    def test_task_updates_default_off(self):
        from services.notification_email_service import evaluate_email_permission

        with patch(
            "services.notification_email_service.is_email_notifications_enabled",
            return_value=True,
        ):
            allowed, reason = evaluate_email_permission(_user(), "task_updated")
        assert allowed is False
        assert reason == "category_disabled"

    def test_invalid_recipient(self):
        from services.notification_email_service import evaluate_email_permission

        with patch(
            "services.notification_email_service.is_email_notifications_enabled",
            return_value=True,
        ):
            allowed, reason = evaluate_email_permission(_user(email="bad"), "task_assigned")
        assert allowed is False
        assert reason == "invalid_recipient"


class TestTypedEmailHelpers:
    def test_invitation_email(self, app):
        from services.email_service import EmailResult, send_team_invitation_email

        with app.app_context():
            app.config["MAIL_SEND_IN_TESTS"] = True
            with patch(
                "services.email_service.send_email",
                return_value=EmailResult(True, "sent", provider_message_id="inv_1"),
            ) as mocked:
                result = send_team_invitation_email(
                    to="ada@example.com",
                    recipient_name="Ada",
                    inviter_name="Grace Hopper",
                    project_name="Apollo",
                )
        assert result.success is True
        kwargs = mocked.call_args.kwargs
        assert "Apollo" in kwargs["subject"]
        assert "Grace Hopper" in kwargs["html"]
        assert "Ada" in kwargs["html"]

    def test_task_assignment_email(self, app):
        from services.email_service import EmailResult, send_task_assignment_email

        with app.app_context():
            app.config["MAIL_SEND_IN_TESTS"] = True
            with patch(
                "services.email_service.send_email",
                return_value=EmailResult(True, "sent", provider_message_id="task_1"),
            ) as mocked:
                result = send_task_assignment_email(
                    to="ada@example.com",
                    recipient_name="Ada",
                    task_title="Write tests",
                    project_name="Teamify",
                    due_date="2026-08-20",
                )
        assert result.success is True
        assert "Write tests" in mocked.call_args.kwargs["subject"]

    def test_deadline_email(self, app):
        from services.email_service import EmailResult, send_deadline_email

        with app.app_context():
            app.config["MAIL_SEND_IN_TESTS"] = True
            with patch(
                "services.email_service.send_email",
                return_value=EmailResult(True, "sent", provider_message_id="dl_1"),
            ) as mocked:
                send_deadline_email(
                    to="ada@example.com",
                    recipient_name="Ada",
                    task_title="Ship it",
                    due_label="due tomorrow",
                    project_name="Teamify",
                    overdue=False,
                )
                send_deadline_email(
                    to="ada@example.com",
                    recipient_name="Ada",
                    task_title="Ship it",
                    due_label="overdue by 2 day(s)",
                    overdue=True,
                )
        subjects = [c.kwargs["subject"] for c in mocked.call_args_list]
        assert any("Deadline reminder" in s for s in subjects)
        assert any("Overdue" in s for s in subjects)

    def test_announcement_email(self, app):
        from services.email_service import EmailResult, send_announcement_email

        with app.app_context():
            app.config["MAIL_SEND_IN_TESTS"] = True
            with patch(
                "services.email_service.send_email",
                return_value=EmailResult(True, "sent", provider_message_id="an_1"),
            ) as mocked:
                send_announcement_email(
                    to="ada@example.com",
                    recipient_name="Ada",
                    title="Maintenance",
                    body="The platform will be unavailable tonight.",
                )
        assert "Maintenance" in mocked.call_args.kwargs["subject"]

    def test_password_reset_otp_email(self, app):
        from services.email_service import EmailResult, send_password_reset_email

        with app.app_context():
            app.config["MAIL_SEND_IN_TESTS"] = True
            with patch(
                "services.email_service.send_email",
                return_value=EmailResult(True, "sent", provider_message_id="otp_1"),
            ) as mocked:
                result = send_password_reset_email(
                    to="ada@example.com",
                    recipient_name="Ada",
                    otp="654321",
                    expires_minutes=10,
                )
        assert result.success is True
        html = mocked.call_args.kwargs["html"]
        text = mocked.call_args.kwargs["text"]
        assert "654321" in html
        assert "654321" in text
        assert "did not request" in text.lower() or "did not request" in html.lower()


class TestForgotPasswordOtp:
    def test_otp_not_in_response(self, client):
        u = _user()
        u.generate_otp.return_value = "654321"
        with patch("routes.auth.User") as m_user, patch(
            "routes.auth.send_password_reset_email",
            create=True,
        ):
            m_user.query.filter_by.return_value.first.return_value = u
            with patch("services.email_service.send_password_reset_email") as send_otp:
                send_otp.return_value = MagicMock(success=True, status="sent", provider_message_id="x")
                with patch("services.notification_email_service.record_standalone_email"):
                    r = client.post("/api/auth/forgot-password", json={"email": "member@example.com"})
        assert r.status_code == 200
        body = r.get_json()
        assert "654321" not in r.get_data(as_text=True)
        assert "otp" not in {k.lower() for k in body.keys()}
        assert body.get("otp") is None

    def test_sends_otp_email(self, client):
        u = _user()
        u.generate_otp.return_value = "654321"
        with patch("routes.auth.User") as m_user:
            m_user.query.filter_by.return_value.first.return_value = u
            with patch("services.email_service.send_password_reset_email") as send_otp:
                send_otp.return_value = MagicMock(
                    success=True, status="sent", provider_message_id="otp_1", error=None
                )
                with patch("services.notification_email_service.record_standalone_email") as record:
                    r = client.post("/api/auth/forgot-password", json={"email": "member@example.com"})
        assert r.status_code == 200
        send_otp.assert_called_once()
        assert send_otp.call_args.kwargs["otp"] == "654321"
        assert send_otp.call_args.kwargs["to"] == "member@example.com"
        record.assert_called_once()


class TestOtpHashing:
    def test_stores_hash_not_plaintext(self, app):
        from models.user import User

        with app.app_context():
            user = User(display_name="otp_user", email="otp@example.com", password="x")
            otp = user.generate_otp()
            assert otp.isdigit() and len(otp) == 6
            assert user.otp_code != otp
            assert len(user.otp_code) == 64
            assert user.verify_otp(otp) is True
            assert user.verify_otp("000000") is False

    def test_legacy_plaintext_otp_still_verifies(self, app):
        from models.user import User

        with app.app_context():
            user = User(display_name="legacy", email="legacy@example.com", password="x")
            user.otp_code = "111222"
            user.otp_expires_at = datetime.now(timezone.utc) + timedelta(minutes=5)
            assert user.verify_otp("111222") is True


class TestDeadlineDedup:
    def test_should_email_respects_timing(self):
        from services.scheduler import _should_email_deadline

        assert _should_email_deadline("DUE_TODAY", "3_hours") is True
        assert _should_email_deadline("DUE_TODAY", "24_hours") is False
        assert _should_email_deadline("DUE_TOMORROW", "24_hours") is True
        assert _should_email_deadline("DUE_IN_2_DAYS", "48_hours") is True
        assert _should_email_deadline("OVERDUE", "24_hours") is True

    def test_duplicate_deadline_prevented(self, app):
        from services.notification_email_service import already_sent
        from models.email_delivery import EMAIL_STATUS_SENT, EmailDelivery

        existing = MagicMock()
        existing.status = EMAIL_STATUS_SENT
        with app.app_context():
            with patch.object(EmailDelivery, "query") as q:
                q.filter_by.return_value.first.return_value = existing
                assert already_sent("deadline:2:201:DUE_TODAY:2026-08-13") is True
                q.filter_by.return_value.first.return_value = None
                assert already_sent("deadline:2:201:DUE_TODAY:2026-08-13") is False


class TestDeliveryPersistence:
    def test_status_persistence_sent(self, app):
        from datetime import datetime, timezone
        from models.email_delivery import EMAIL_STATUS_SENT, EmailDelivery

        with app.app_context():
            row = EmailDelivery(
                notification_id=401,
                user_id=MEMBER_USER_ID,
                recipient_email="ada@example.com",
                email_type="task_assigned",
                status=EMAIL_STATUS_SENT,
                provider_message_id="msg_abc",
                sent_at=datetime.now(timezone.utc),
            )
            public = row.to_public_dict()
            assert public["email_delivered"] is True
            assert public["status"] == "sent"
            assert "error" not in public
            assert "provider_message_id" not in public

    def test_failed_status_not_shown_as_sent(self):
        from models.email_delivery import EMAIL_STATUS_FAILED, EmailDelivery

        row = EmailDelivery(
            notification_id=401,
            user_id=MEMBER_USER_ID,
            recipient_email="ada@example.com",
            email_type="task_assigned",
            status=EMAIL_STATUS_FAILED,
            error_message="email provider rejected the request",
        )
        assert row.is_sent is False
        assert row.to_public_dict()["email_delivered"] is False
        assert row.to_public_dict()["status"] == "failed"

    def test_notification_dict_uses_delivery(self, app):
        from models.email_delivery import EMAIL_STATUS_SENT, EmailDelivery
        from models.notification import Notification

        with app.app_context():
            notif = Notification(
                user_id=MEMBER_USER_ID,
                type="task_assigned",
                title="New task assigned",
                body="You have a task",
            )
            notif.id = 401
            notif.created_at = datetime(2026, 8, 13, tzinfo=timezone.utc)
            delivery = EmailDelivery(
                notification_id=401,
                user_id=MEMBER_USER_ID,
                recipient_email="ada@example.com",
                email_type="task_assigned",
                status=EMAIL_STATUS_SENT,
            )
            payload = notif.to_dict(email_delivery=delivery)
            assert payload["email_delivered"] is True
            assert payload["emailDelivered"] is True
            payload_none = notif.to_dict()
            assert payload_none["email_delivered"] is False


class TestDeliverNotificationEmail:
    def test_skips_when_admin_disabled(self, app):
        from models.notification import Notification
        from services.email_service import EmailResult

        notif = Notification(
            user_id=MEMBER_USER_ID,
            type="task_assigned",
            title="New task assigned",
            body="Assigned",
        )
        notif.id = 77
        user = _user()
        with app.app_context():
            with patch("services.notification_email_service.db") as mdb, patch(
                "services.notification_email_service.evaluate_email_permission",
                return_value=(False, "admin_disabled"),
            ), patch(
                "services.notification_email_service._record_delivery",
                return_value=MagicMock(),
            ) as record, patch(
                "services.notification_email_service.send_email",
            ) as send:
                mdb.session.get.side_effect = lambda model, pk: notif if model is Notification else user
                from services.notification_email_service import deliver_notification_email

                result = deliver_notification_email(77)
        assert result.status == "skipped"
        send.assert_not_called()
        assert record.call_args.kwargs["status"] == "skipped"

    def test_records_failed_provider(self, app):
        from models.notification import Notification
        from models.user import User
        from services.email_service import EmailResult

        notif = Notification(
            user_id=MEMBER_USER_ID,
            type="task_assigned",
            title="New task assigned",
            body="Assigned",
        )
        notif.id = 88
        user = _user()
        with app.app_context():
            with patch("services.notification_email_service.db") as mdb, patch(
                "services.notification_email_service.evaluate_email_permission",
                return_value=(True, None),
            ), patch(
                "services.notification_email_service.build_notification_email_content",
                return_value=("Subject", "<p>Hi</p>", "Hi"),
            ), patch(
                "services.notification_email_service.send_email",
                return_value=EmailResult(False, "failed", error="email provider rejected the request"),
            ), patch(
                "services.notification_email_service._record_delivery",
                return_value=MagicMock(),
            ) as record:
                def _get(model, pk):
                    if model is Notification:
                        return notif
                    if model is User:
                        return user
                    return None

                mdb.session.get.side_effect = _get
                from services.notification_email_service import deliver_notification_email

                result = deliver_notification_email(88)
        assert result.status == "failed"
        assert record.call_args.kwargs["status"] == "failed"


class TestChatMentions:
    def test_parses_display_name_mentions(self):
        from services.chat_notification_service import _mentioned_user_ids

        ada = _user(2, email="ada@example.com")
        ada.display_name = "ada"
        bob = _user(3, email="bob@example.com")
        bob.display_name = "bob"
        ids = _mentioned_user_ids("hey @ada please review", [ada, bob])
        assert ids == {2}

    def test_no_mention_returns_empty(self):
        from services.chat_notification_service import _mentioned_user_ids

        ada = _user(2)
        ada.display_name = "ada"
        assert _mentioned_user_ids("hello team", [ada]) == set()
    def test_helper_reads_setting(self):
        with patch(
            "services.system_settings_service.get_system_settings",
            return_value={"email_notifications": False},
        ):
            from services.system_settings_service import is_email_notifications_enabled

            assert is_email_notifications_enabled() is False
        with patch(
            "services.system_settings_service.get_system_settings",
            return_value={"email_notifications": True},
        ):
            from services.system_settings_service import is_email_notifications_enabled

            assert is_email_notifications_enabled() is True
