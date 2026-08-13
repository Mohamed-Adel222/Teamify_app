"""Send a one-off test email through Resend.

Replace ``re_xxxxxxxxx`` in RESEND_API_KEY with your real API key.
With the default ``onboarding@resend.dev`` sender, Resend only delivers
to the email on your Resend account.

Usage (from teamify_flask_backend/):

    python scripts/send_test_email.py
"""
from __future__ import annotations

import os
import sys

from dotenv import load_dotenv

load_dotenv()

# Ask the user to replace re_xxxxxxxxx with their real API key.
resend_api_key = os.getenv("RESEND_API_KEY", "re_xxxxxxxxx")
to_address = os.getenv("RESEND_TEST_TO", "delivered@resend.dev")
from_address = os.getenv("RESEND_FROM_EMAIL", "onboarding@resend.dev")


def main() -> int:
    if not resend_api_key or resend_api_key == "re_xxxxxxxxx":
        print(
            "Set RESEND_API_KEY in .env to your real Resend key "
            "(replace re_xxxxxxxxx).",
            file=sys.stderr,
        )
        return 1

    import resend

    resend.api_key = resend_api_key
    result = resend.Emails.send({
        "from": from_address,
        "to": to_address,
        "subject": "Hello World",
        "html": "<p>Congrats on sending your <strong>first email</strong>!</p>",
    })
    print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
