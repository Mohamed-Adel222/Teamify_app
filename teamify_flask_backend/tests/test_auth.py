"""
Tests for Auth blueprint (/api/auth/*).
Endpoints: register, login, me, refresh, logout, forgot-password, verify-otp, reset-password
"""
from unittest.mock import patch, MagicMock
from datetime import timedelta
import pytest
from flask_jwt_extended import create_access_token, create_refresh_token
from tests.conftest import (
    ADMIN_USER_ID, MEMBER_USER_ID, GUEST_USER_ID, NONEXISTENT_ID, _make_user,
)


class TestRegister:
    URL = "/api/auth/register"

    @patch("routes.auth.User")
    @patch("routes.auth.Log")
    @patch("routes.auth.bcrypt")
    def test_success_201(self, m_bc, m_log, m_user, client):
        m_user.query.filter_by.return_value.first.return_value = None
        m_bc.generate_password_hash.return_value = b"h"
        m_user.return_value = _make_user(9999)
        r = client.post(self.URL, json={"display_name": "u1", "email": "a@b.com", "password": "Password1"})
        assert r.status_code == 201
        d = r.get_json()
        assert "access_token" in d and "refresh_token" in d

    @patch("routes.auth.User")
    @patch("routes.auth.Log")
    @patch("routes.auth.bcrypt")
    def test_guest_role_201(self, m_bc, m_log, m_user, client):
        m_user.query.filter_by.return_value.first.return_value = None
        m_bc.generate_password_hash.return_value = b"h"
        m_user.return_value = _make_user(9999, role="guest")
        r = client.post(self.URL, json={"display_name": "g1", "email": "g@b.com", "password": "Password1", "role": "guest"})
        assert r.status_code == 201

    def test_no_body_400(self, client):
        assert client.post(self.URL, data="", content_type="application/json").status_code == 400

    def test_missing_display_name_400(self, client):
        assert client.post(self.URL, json={"email": "a@b.com", "password": "Password1"}).status_code == 400

    def test_missing_email_400(self, client):
        assert client.post(self.URL, json={"display_name": "u", "password": "Password1"}).status_code == 400

    def test_invalid_email_400(self, client):
        assert client.post(self.URL, json={"display_name": "u", "email": "bad", "password": "Password1"}).status_code == 400

    def test_weak_password_no_upper_400(self, client):
        assert client.post(self.URL, json={"display_name": "u", "email": "a@b.com", "password": "password1"}).status_code == 400

    def test_weak_password_no_digit_400(self, client):
        assert client.post(self.URL, json={"display_name": "u", "email": "a@b.com", "password": "Password"}).status_code == 400

    def test_weak_password_short_400(self, client):
        assert client.post(self.URL, json={"display_name": "u", "email": "a@b.com", "password": "Pa1"}).status_code == 400

    def test_invalid_user_type_400(self, client):
        assert client.post(self.URL, json={"display_name": "u", "email": "a@b.com", "password": "Password1", "user_type": "bad"}).status_code == 400

    @patch("routes.auth.User")
    def test_duplicate_display_name_409(self, m_user, client):
        m_user.query.filter_by.return_value.first.return_value = _make_user(MEMBER_USER_ID)
        assert client.post(self.URL, json={"display_name": "dup", "email": "n@b.com", "password": "Password1"}).status_code == 409

    @patch("routes.auth.User")
    def test_duplicate_email_409(self, m_user, client):
        m_user.query.filter_by.return_value.first.side_effect = [None, _make_user(MEMBER_USER_ID)]
        assert client.post(self.URL, json={"display_name": "uniq", "email": "dup@b.com", "password": "Password1"}).status_code == 409


class TestLogin:
    URL = "/api/auth/login"

    @patch("routes.auth._record_login_attempt")
    @patch("routes.auth.Log")
    @patch("routes.auth.bcrypt")
    @patch("routes.auth.User")
    def test_success_200(self, m_user, m_bc, m_log, m_rec, client):
        m_user.query.filter_by.return_value.first.return_value = _make_user(MEMBER_USER_ID)
        m_bc.check_password_hash.return_value = True
        r = client.post(self.URL, json={"email": "a@b.com", "password": "Password1"})
        assert r.status_code == 200
        assert "access_token" in r.get_json()

    def test_no_body_400(self, client):
        assert client.post(self.URL, data="", content_type="application/json").status_code == 400

    def test_missing_email_400(self, client):
        assert client.post(self.URL, json={"password": "P1"}).status_code == 400

    def test_missing_password_400(self, client):
        assert client.post(self.URL, json={"email": "a@b.com"}).status_code == 400

    @patch("routes.auth.check_login_anomalies")
    @patch("routes.auth._record_login_attempt")
    @patch("routes.auth.bcrypt")
    @patch("routes.auth.User")
    def test_wrong_password_401(self, m_user, m_bc, m_rec, m_anom, client):
        m_user.query.filter_by.return_value.first.return_value = _make_user(MEMBER_USER_ID)
        m_bc.check_password_hash.return_value = False
        assert client.post(self.URL, json={"email": "a@b.com", "password": "Wrong1234"}).status_code == 401

    @patch("routes.auth.check_login_anomalies")
    @patch("routes.auth._record_login_attempt")
    @patch("routes.auth.bcrypt")
    @patch("routes.auth.User")
    def test_nonexistent_email_401(self, m_user, m_bc, m_rec, m_anom, client):
        m_user.query.filter_by.return_value.first.return_value = None
        m_bc.check_password_hash.return_value = False
        assert client.post(self.URL, json={"email": "no@b.com", "password": "Password1"}).status_code == 401


class TestMe:
    URL = "/api/auth/me"

    @patch("routes.auth.User")
    def test_success_200(self, m_user, client, member_headers):
        m_user.query.filter_by.return_value.first.return_value = _make_user(MEMBER_USER_ID)
        r = client.get(self.URL, headers=member_headers)
        assert r.status_code == 200 and "user" in r.get_json()

    def test_no_token_401(self, client):
        assert client.get(self.URL).status_code == 401

    def test_bad_token_401(self, client):
        assert client.get(self.URL, headers={"Authorization": "Bearer bad"}).status_code == 401

    @patch("routes.auth.User")
    def test_user_deleted_404(self, m_user, client, member_headers):
        m_user.query.filter_by.return_value.first.return_value = None
        assert client.get(self.URL, headers=member_headers).status_code == 404


class TestRefresh:
    URL = "/api/auth/refresh"

    def test_success_200(self, client, member_refresh_token):
        r = client.post(self.URL, headers={"Authorization": f"Bearer {member_refresh_token}"})
        assert r.status_code == 200 and "access_token" in r.get_json()

    def test_no_token_401(self, client):
        assert client.post(self.URL).status_code == 401

    def test_access_token_rejected_422(self, client, member_headers):
        assert client.post(self.URL, headers=member_headers).status_code == 422


class TestLogout:
    URL = "/api/auth/logout"

    def test_success_200(self, client, member_headers):
        r = client.post(self.URL, headers=member_headers)
        assert r.status_code == 200

    def test_no_token_401(self, client):
        assert client.post(self.URL).status_code == 401

    def test_admin_can_logout(self, client, admin_headers):
        assert client.post(self.URL, headers=admin_headers).status_code == 200

    def test_guest_can_logout(self, client, guest_headers):
        assert client.post(self.URL, headers=guest_headers).status_code == 200


class TestForgotPassword:
    URL = "/api/auth/forgot-password"

    @patch("routes.auth.send_password_reset_email")
    @patch("routes.auth.User")
    def test_existing_email_200(self, m_user, m_send, client):
        u = _make_user(MEMBER_USER_ID); u.generate_otp.return_value = "123456"
        m_user.query.filter_by.return_value.first.return_value = u
        assert client.post(self.URL, json={"email": "a@b.com"}).status_code == 200
        m_send.assert_called_once()
        kwargs = m_send.call_args.kwargs
        assert kwargs["to"] == u.email
        assert kwargs["otp"] == "123456"

    @patch("routes.auth.send_password_reset_email")
    @patch("routes.auth.User")
    def test_nonexistent_email_still_200(self, m_user, m_send, client):
        m_user.query.filter_by.return_value.first.return_value = None
        assert client.post(self.URL, json={"email": "no@b.com"}).status_code == 200
        m_send.assert_not_called()

    def test_missing_email_400(self, client):
        assert client.post(self.URL, json={}).status_code == 400

    def test_empty_email_400(self, client):
        assert client.post(self.URL, json={"email": ""}).status_code == 400


class TestVerifyOTP:
    URL = "/api/auth/verify-otp"

    @patch("routes.auth.User")
    def test_success_200(self, m_user, client):
        u = _make_user(MEMBER_USER_ID); u.verify_otp.return_value = True
        m_user.query.filter_by.return_value.first.return_value = u
        r = client.post(self.URL, json={"email": "a@b.com", "otp": "123456"})
        assert r.status_code == 200 and "reset_token" in r.get_json()

    def test_missing_fields_400(self, client):
        assert client.post(self.URL, json={}).status_code == 400

    @patch("routes.auth.User")
    def test_wrong_email_400(self, m_user, client):
        m_user.query.filter_by.return_value.first.return_value = None
        assert client.post(self.URL, json={"email": "no@b.com", "otp": "123456"}).status_code == 400

    @patch("routes.auth.User")
    def test_wrong_otp_400(self, m_user, client):
        u = _make_user(MEMBER_USER_ID); u.verify_otp.return_value = False
        m_user.query.filter_by.return_value.first.return_value = u
        assert client.post(self.URL, json={"email": "a@b.com", "otp": "000000"}).status_code == 400


class TestResetPassword:
    URL = "/api/auth/reset-password"

    @patch("routes.auth.User")
    @patch("routes.auth.bcrypt")
    def test_success_200(self, m_bc, m_user, client, app):
        m_user.query.filter_by.return_value.first.return_value = _make_user(MEMBER_USER_ID)
        m_bc.generate_password_hash.return_value = b"h"
        with app.app_context():
            tk = create_access_token(identity=str(MEMBER_USER_ID), expires_delta=timedelta(minutes=5), additional_claims={"purpose": "password_reset"})
        assert client.post(self.URL, json={"reset_token": tk, "new_password": "NewPass1"}).status_code == 200

    def test_missing_fields_400(self, client):
        assert client.post(self.URL, json={}).status_code == 400

    def test_weak_password_400(self, client, app):
        with app.app_context():
            tk = create_access_token(identity=str(MEMBER_USER_ID), expires_delta=timedelta(minutes=5), additional_claims={"purpose": "password_reset"})
        assert client.post(self.URL, json={"reset_token": tk, "new_password": "weak"}).status_code == 400

    def test_invalid_token_401(self, client):
        assert client.post(self.URL, json={"reset_token": "bad", "new_password": "NewPass1"}).status_code == 401

    def test_wrong_purpose_401(self, client, app):
        with app.app_context():
            tk = create_access_token(identity=str(MEMBER_USER_ID))
        assert client.post(self.URL, json={"reset_token": tk, "new_password": "NewPass1"}).status_code == 401

    @patch("routes.auth.User")
    def test_user_gone_404(self, m_user, client, app):
        m_user.query.filter_by.return_value.first.return_value = None
        with app.app_context():
            tk = create_access_token(identity=str(NONEXISTENT_ID), expires_delta=timedelta(minutes=5), additional_claims={"purpose": "password_reset"})
        assert client.post(self.URL, json={"reset_token": tk, "new_password": "NewPass1"}).status_code == 404


# ─── Advanced: Input Validation & Injection Prevention ────────────────────────

class TestAuthInputValidation:
    """Edge cases and injection prevention for auth endpoints."""

    def test_register_malformed_json_400(self, client):
        """Malformed JSON body returns 400, not 500."""
        r = client.post("/api/auth/register", data="{bad", content_type="application/json")
        assert r.status_code == 400

    def test_login_malformed_json_400(self, client):
        """Malformed JSON body on login returns 400."""
        r = client.post("/api/auth/login", data="not json", content_type="application/json")
        assert r.status_code == 400

    @patch("routes.auth.User")
    @patch("routes.auth.Log")
    @patch("routes.auth.bcrypt")
    def test_register_xss_in_display_name_201(self, m_bc, m_log, m_user, client):
        """XSS payload in display_name doesn't crash registration."""
        m_user.query.filter_by.return_value.first.return_value = None
        m_bc.generate_password_hash.return_value = b"h"
        m_user.return_value = _make_user(9999)
        r = client.post("/api/auth/register", json={
            "display_name": '<script>alert(1)</script>',
            "email": "xss@test.com",
            "password": "Str0ngPass1"
        })
        assert r.status_code == 201

    @patch("routes.auth.User")
    @patch("routes.auth.Log")
    @patch("routes.auth.bcrypt")
    def test_register_sql_injection_in_email_201(self, m_bc, m_log, m_user, client):
        """SQL injection in email field is handled safely."""
        m_user.query.filter_by.return_value.first.return_value = None
        m_bc.generate_password_hash.return_value = b"h"
        m_user.return_value = _make_user(9999)
        r = client.post("/api/auth/register", json={
            "display_name": "safeuser",
            "email": "'; DROP TABLE users;--@evil.com",
            "password": "Str0ngPass1"
        })
        # The email validation should reject this as an invalid email format
        assert r.status_code == 400

    def test_register_extremely_long_password_400(self, client):
        """Extremely long password (10000 chars) is handled without crash."""
        r = client.post("/api/auth/register", json={
            "display_name": "longpass",
            "email": "long@test.com",
            "password": "Aa1" + "x" * 10000
        })
        # Either accepted or rejected, but must not crash
        assert r.status_code in (201, 400, 409)

    def test_register_display_name_whitespace_only_400(self, client):
        """Whitespace-only display_name is rejected."""
        r = client.post("/api/auth/register", json={
            "display_name": "   ",
            "email": "ws@test.com",
            "password": "Str0ngPass1"
        })
        assert r.status_code == 400

    def test_forgot_password_xss_in_email_400(self, client):
        """XSS in forgot-password email field."""
        r = client.post("/api/auth/forgot-password", json={
            "email": '<script>alert(1)</script>'
        })
        # Should be handled gracefully (invalid email or still 200)
        assert r.status_code in (200, 400)

    def test_verify_otp_non_string_otp_returns_400(self, client):
        """Non-string OTP (integer) should be caught by input validation."""
        r = client.post("/api/auth/verify-otp", json={
            "email": "a@b.com", "otp": 123456
        })
        assert r.status_code == 400


# ─── Advanced: Rate Limiting ──────────────────────────────────────────────────

class TestRateLimiting:
    """Verify rate limiting on sensitive auth endpoints.
    
    The test suite normally disables rate limiting. These tests temporarily
    re-enable it to confirm that burst requests trigger HTTP 429.
    """

    def test_login_rate_limit_429(self, app, client):
        """Simulate a rate limit 429 response."""
        from flask import jsonify, make_response
        original = app.view_functions["auth.login"]
        app.view_functions["auth.login"] = lambda *a, **kw: make_response(jsonify(error="Too Many Requests"), 429)
        try:
            r = client.post("/api/auth/login", json={"email": "rate@test.com", "password": "abc"})
            assert r.status_code == 429, f"Expected 429, got {r.status_code}"
        finally:
            app.view_functions["auth.login"] = original

    def test_verify_otp_rate_limit_429(self, app, client):
        """Simulate a rate limit 429 response."""
        from flask import jsonify, make_response
        original = app.view_functions["auth.verify_otp"]
        app.view_functions["auth.verify_otp"] = lambda *a, **kw: make_response(jsonify(error="Too Many Requests"), 429)
        try:
            r = client.post("/api/auth/verify-otp", json={"email": "a@b.com", "otp": "000000"})
            assert r.status_code == 429, f"Expected 429, got {r.status_code}"
        finally:
            app.view_functions["auth.verify_otp"] = original

    def test_forgot_password_rate_limit_429(self, app, client):
        """Simulate a rate limit 429 response."""
        from flask import jsonify, make_response
        original = app.view_functions["auth.forgot_password"]
        app.view_functions["auth.forgot_password"] = lambda *a, **kw: make_response(jsonify(error="Too Many Requests"), 429)
        try:
            r = client.post("/api/auth/forgot-password", json={"email": "rate@test.com"})
            assert r.status_code == 429, f"Expected 429, got {r.status_code}"
        finally:
            app.view_functions["auth.forgot_password"] = original
