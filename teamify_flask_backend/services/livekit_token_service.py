"""Mint short-lived LiveKit access tokens. Secrets never leave the server."""
from __future__ import annotations

import json
import logging
import os
import time
import urllib.error
import urllib.request
from typing import Any

import jwt

logger = logging.getLogger(__name__)


def livekit_configured() -> bool:
    return bool(
        os.getenv("LIVEKIT_URL", "").strip()
        and os.getenv("LIVEKIT_API_KEY", "").strip()
        and os.getenv("LIVEKIT_API_SECRET", "").strip()
    )


def livekit_url() -> str:
    return os.getenv("LIVEKIT_URL", "").strip()


def livekit_http_url() -> str:
    """Convert a LiveKit websocket URL to the HTTPS Room Service base."""
    url = livekit_url().rstrip("/")
    if url.startswith("wss://"):
        return "https://" + url[6:]
    if url.startswith("ws://"):
        return "http://" + url[5:]
    return url


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


def create_livekit_server_token(ttl_seconds: int = 60) -> tuple[str | None, str | None]:
    """Mint a short-lived server JWT for LiveKit RoomService (never sent to Flutter)."""
    api_key = os.getenv("LIVEKIT_API_KEY", "").strip()
    api_secret = os.getenv("LIVEKIT_API_SECRET", "").strip()
    if not api_key or not api_secret or not livekit_url():
        return None, "LiveKit is not configured on this server"
    now = int(time.time())
    payload = {
        "iss": api_key,
        "sub": api_key,
        "nbf": now - 10,
        "exp": now + max(30, int(ttl_seconds)),
        "video": {
            "roomCreate": True,
            "roomList": True,
            "roomAdmin": True,
        },
    }
    token = jwt.encode(payload, api_secret, algorithm="HS256")
    if isinstance(token, bytes):
        token = token.decode("utf-8")
    return token, None


def delete_livekit_room(room_name: str) -> bool:
    """
    Best-effort LiveKit RoomService DeleteRoom so remotes disconnect when the
    host ends the meeting. Never raises; never logs secrets or participant JWTs.
    """
    if not room_name or not livekit_configured():
        return False
    token, err = create_livekit_server_token()
    if err or not token:
        logger.warning("LiveKit DeleteRoom skipped: %s", err or "no server token")
        return False
    endpoint = f"{livekit_http_url()}/twirp/livekit.RoomService/DeleteRoom"
    request = urllib.request.Request(
        endpoint,
        data=json.dumps({"room": room_name}).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=8) as resp:
            resp.read()
        logger.info("LiveKit DeleteRoom ok room=%s", room_name)
        return True
    except urllib.error.HTTPError as exc:
        # 404: room already gone — treat as success for host-end.
        if exc.code == 404:
            logger.info("LiveKit DeleteRoom room already gone room=%s", room_name)
            return True
        logger.warning("LiveKit DeleteRoom HTTP %s room=%s", exc.code, room_name)
        return False
    except Exception as exc:
        logger.warning("LiveKit DeleteRoom failed room=%s: %s", room_name, exc)
        return False
