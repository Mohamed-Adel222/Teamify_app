"""Google/GitHub login must keep working after gevent.patch_all(ssl=False)."""
from unittest.mock import patch

import app  # noqa: F401  # applies gevent ssl=False + PyOpenSSL inject
import requests

from services.oauth_user_service import verify_google_id_token


def test_requests_https_works_after_gevent_ssl_false():
    response = requests.get("https://www.googleapis.com/oauth2/v1/certs", timeout=15)
    assert response.status_code == 200
    assert response.json()


def test_verify_google_id_token_wraps_tls_typeerror():
    class BoomRequest:
        def __call__(self, *args, **kwargs):
            raise TypeError(
                "_wrap_socket() argument 'sock' must be _socket.socket, not SSLSocket"
            )

    with patch(
        "google.auth.transport.requests.Request",
        return_value=BoomRequest(),
    ):
        try:
            verify_google_id_token("not-a-real-jwt")
        except ValueError as exc:
            assert "Could not verify Google token" in str(exc)
        else:
            raise AssertionError("expected ValueError")
