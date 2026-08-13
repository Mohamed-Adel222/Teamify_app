"""Mint short-lived LiveKit access tokens. Secrets never leave the server."""
from __future__ import annotations

import os
import time
from typing import Any

import jwt


def livekit_configured() -> bool:
    return bool(
        os.getenv("LIVEKIT_URL", "").strip()
        and os.getenv("LIVEKIT_API_KEY", "").strip()
        and os.getenv("LIVEKIT_API_SECRET", "").strip()
    )


def livekit_url() -> str:
    return os.getenv("LIVEKIT_URL", "").strip()


def create_meeting_access_token(
    *,
    identity: str,
    name: str,
    room: str,
    is_host: bool,
    ttl_seconds: int = 7200,
) -> tuple[str | None, str | None]:
    """
    Return (token, error). error is set when LiveKit is not configured.
    """
    api_key = os.getenv("LIVEKIT_API_KEY", "").strip()
    api_secret = os.getenv("LIVEKIT_API_SECRET", "").strip()
    if not api_key or not api_secret or not livekit_url():
        return None, "LiveKit is not configured on this server"

    now = int(time.time())
    video: dict[str, Any] = {
        "roomJoin": True,
        "room": room,
        "canPublish": True,
        "canSubscribe": True,
        "canPublishData": True,
        "canUpdateOwnMetadata": True,
    }
    if is_host:
        video["roomAdmin"] = True
        video["roomCreate"] = True

    payload = {
        "iss": api_key,
        "sub": identity,
        "name": name,
        "nbf": now - 10,
        "exp": now + max(60, int(ttl_seconds)),
        "video": video,
    }
    token = jwt.encode(payload, api_secret, algorithm="HS256")
    if isinstance(token, bytes):
        token = token.decode("utf-8")
    return token, None
