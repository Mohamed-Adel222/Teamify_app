import pytest
from models.user import User
from models import db
from flask_jwt_extended import decode_token
from unittest.mock import patch, MagicMock

pytestmark = pytest.mark.integration

@pytest.fixture(autouse=True)
def clean_db(app, _db):
    """
    Ensure the database is clean before each integration test.
    We delete all users instead of recreating tables to be faster.
    """
    with app.app_context():
        db.session.query(User).delete()
        db.session.commit()
        yield
        db.session.query(User).delete()
        db.session.commit()

class TestAuthAPIIntegration:
    """Step 2 & 3: Integration and API Testing for Auth Routes hitting the real SQLite DB."""
    
    def test_full_registration_and_login_flow(self, client):
        """Test the end-to-end flow of registering a user and then logging in."""
        # 1. Register a new user
        reg_payload = {
            "display_name": "int_user",
            "email": "int@example.com",
            "password": "Password123",
            "role": "member",
            "user_type": "freelancer"
        }
        resp = client.post("/api/auth/register", json=reg_payload)
        
        assert resp.status_code == 201
        data = resp.get_json()
        assert data["message"] == "User registered successfully"
        assert "access_token" in data
        
        # Verify DB insertion
        user = User.query.filter_by(email="int@example.com").first()
        assert user is not None
        assert user.display_name == "int_user"
        
        # 2. Login with the new user (should fail because freelancer is pending)
        login_payload = {
            "email": "int@example.com",
            "password": "Password123"
        }
        resp = client.post("/api/auth/login", json=login_payload)
        assert resp.status_code == 403
        
        # 3. Approve the user manually in the DB
        with client.application.app_context():
            user = User.query.filter_by(email="int@example.com").first()
            user.account_status = "approved"
            db.session.commit()

        # 4. Login again (should succeed now)
        resp = client.post("/api/auth/login", json=login_payload)
        assert resp.status_code == 200
        data = resp.get_json()
        assert "access_token" in data
        assert data["user"]["email"] == "int@example.com"

    def test_registration_duplicate_email(self, client):
        """Test that registering with an existing email correctly returns 409 Conflict."""
        payload = {
            "display_name": "user1",
            "email": "dup@example.com",
            "password": "Password123"
        }
        # First registration succeeds
        resp1 = client.post("/api/auth/register", json=payload)
        assert resp1.status_code == 201
        
        # Second registration with same email fails
        payload["display_name"] = "user2"  # Change display name to isolate email conflict
        resp2 = client.post("/api/auth/register", json=payload)
        assert resp2.status_code == 409
        assert resp2.get_json()["message"] == "Email already exists"

    def test_login_invalid_credentials(self, client):
        """Test login fails properly with non-existent user or wrong password."""
        # Unregistered user
        resp = client.post("/api/auth/login", json={
            "email": "nobody@example.com",
            "password": "Password123"
        })
        assert resp.status_code == 401
        
        # Register a user
        client.post("/api/auth/register", json={
            "display_name": "wrongpass",
            "email": "wrongpass@example.com",
            "password": "Password123"
        })
        
        # Login with wrong password
        resp = client.post("/api/auth/login", json={
            "email": "wrongpass@example.com",
            "password": "WrongPassword1"
        })
        assert resp.status_code == 401

    def test_get_me_endpoint_with_real_token(self, client):
        """Test the /me endpoint using a freshly generated JWT token."""
        # Register to get token
        resp = client.post("/api/auth/register", json={
            "display_name": "me_user",
            "email": "me@example.com",
            "password": "Password123"
        })
        token = resp.get_json()["access_token"]
        
        # Access /me endpoint
        me_resp = client.get(
            "/api/auth/me",
            headers={"Authorization": f"Bearer {token}"}
        )
        assert me_resp.status_code == 200
        assert me_resp.get_json()["user"]["email"] == "me@example.com"
        
    def test_unauthorized_access(self, client):
        """Test that protected endpoints reject requests without a token."""
        resp = client.get("/api/auth/me")
        assert resp.status_code == 401

    @patch("requests.get")
    @patch("requests.post")
    def test_github_login(self, mock_post, mock_get, client, monkeypatch):
        """Test GitHub OAuth login flow."""
        monkeypatch.setenv("GITHUB_CLIENT_ID", "test-github-client")
        monkeypatch.setenv("GITHUB_CLIENT_SECRET", "test-github-secret")

        mock_token_resp = MagicMock()
        mock_token_resp.status_code = 200
        mock_token_resp.json.return_value = {"access_token": "gho_fake_token"}

        # Mock the profile response
        mock_profile_resp = MagicMock()
        mock_profile_resp.status_code = 200
        mock_profile_resp.json.return_value = {
            "id": 123456,
            "login": "testghuser",
            "name": "Test GitHub User",
            "email": "github@example.com"
        }

        mock_post.return_value = mock_token_resp
        mock_get.return_value = mock_profile_resp

        # Perform the request
        payload = {"code": "fake_oauth_code"}
        resp = client.post("/api/auth/github", json=payload)
        
        assert resp.status_code == 201
        data = resp.get_json()
        assert data["message"] == "GitHub login successful"
        assert data["is_new_user"] is True
        assert "access_token" in data
        assert data["user"]["github_id"] == "123456"
        assert data["user"]["email"] == "github@example.com"
        assert data["user"]["account_status"] == "approved"
        
        # Verify user was created in DB
        with client.application.app_context():
            user = User.query.filter_by(github_id="123456").first()
            assert user is not None
            assert user.email == "github@example.com"
            assert user.role == "member"

    @patch("services.oauth_user_service.verify_google_id_token")
    def test_google_login_creates_user_with_profile(self, mock_verify, client):
        """OAuth sign-up can persist the same profile fields as email register."""
        mock_verify.return_value = {
            "email": "google-profile@example.com",
            "name": "Google Profile User",
            "sub": "google-sub-profile",
        }

        resp = client.post(
            "/api/auth/google",
            json={
                "id_token": "fake-token",
                "user_type": "freelancer",
                "professional_field": "Developer",
                "experience_level": "Senior",
                "availability": "Full Time",
                "skills": "Flutter,Backend Development",
            },
        )

        assert resp.status_code == 201
        data = resp.get_json()
        assert data["is_new_user"] is True
        assert data["user"]["professional_field"] == "Developer"
        assert "Flutter" in data["user"]["skills"]
        assert data["user"]["profile_complete"] is True
        assert data["user"]["needs_profile_setup"] is False

        with client.application.app_context():
            user = User.query.filter_by(email="google-profile@example.com").first()
            assert user is not None
            assert user.professional_field == "Developer"
            assert user.experience_level == "Senior"
            assert user.availability == "Full Time"
            assert user.skills == ["Flutter", "Backend Development"]

    @patch("services.oauth_user_service.verify_google_id_token")
    def test_google_login_creates_user(self, mock_verify, client):
        """Test Google OAuth login persists a new user."""
        mock_verify.return_value = {
            "email": "google@example.com",
            "name": "Google User",
            "sub": "google-sub-123",
        }

        resp = client.post(
            "/api/auth/google",
            json={"id_token": "fake-token", "user_type": "freelancer"},
        )

        assert resp.status_code == 201
        data = resp.get_json()
        assert data["is_new_user"] is True
        assert data["user"]["email"] == "google@example.com"
        assert data["user"]["full_name"] == "Google User"
        assert data["user"]["needs_profile_setup"] is True
        assert data["user"]["profile_complete"] is False
        assert "access_token" in data

        with client.application.app_context():
            user = User.query.filter_by(email="google@example.com").first()
            assert user is not None
            assert user.user_type == "freelancer"
            assert user.display_name.startswith("user_")

    @patch("services.oauth_user_service.verify_google_id_token")
    def test_google_login_reuses_existing_incomplete_account(self, mock_verify, client):
        """A second Google sign-in must not create another user."""
        mock_verify.return_value = {
            "email": "google-repeat@example.com",
            "name": "Repeat User",
            "sub": "google-sub-repeat",
        }
        first = client.post(
            "/api/auth/google",
            json={"id_token": "fake-token", "user_type": "freelancer"},
        )
        assert first.status_code == 201
        second = client.post(
            "/api/auth/google",
            json={"id_token": "fake-token", "user_type": "freelancer"},
        )
        assert second.status_code == 200
        data = second.get_json()
        assert data["is_new_user"] is False
        assert data["user"]["email"] == "google-repeat@example.com"
        assert data["user"]["needs_profile_setup"] is True

        with client.application.app_context():
            matches = User.query.filter_by(email="google-repeat@example.com").all()
            assert len(matches) == 1

    def test_google_login_invalid_token_is_401_not_500(self, client):
        """Broken/fake Google tokens must not surface as Internal Server Error."""
        resp = client.post("/api/auth/google", json={"id_token": "fake"})
        assert resp.status_code == 401
        body = resp.get_json()
        assert body["error"] == "Unauthorized"
        assert "Google" in (body.get("message") or "")

    def test_github_login_provider_error_is_400(self, client, monkeypatch):
        monkeypatch.setenv("GITHUB_CLIENT_ID", "test-github-client")
        monkeypatch.setenv("GITHUB_CLIENT_SECRET", "test-github-secret")

        mock_token_resp = MagicMock()
        mock_token_resp.status_code = 200
        mock_token_resp.json.return_value = {
            "error": "bad_verification_code",
            "error_description": "The code passed is incorrect or expired.",
        }

        with patch("requests.post", return_value=mock_token_resp):
            resp = client.post("/api/auth/github", json={"code": "used-or-fake"})

        assert resp.status_code == 400
        assert "GitHub OAuth error" in resp.get_json()["error"]

    def test_github_login_https_failure_is_502(self, client, monkeypatch):
        monkeypatch.setenv("GITHUB_CLIENT_ID", "test-github-client")
        monkeypatch.setenv("GITHUB_CLIENT_SECRET", "test-github-secret")

        with patch(
            "requests.post",
            side_effect=TypeError(
                "_wrap_socket() argument 'sock' must be _socket.socket, not SSLSocket"
            ),
        ):
            resp = client.post("/api/auth/github", json={"code": "any"})

        assert resp.status_code == 502
        body = resp.get_json()
        assert body["error"] == "Bad Gateway"
        assert "GitHub" in (body.get("message") or "")
