"""One-time CLI script to authorize Google Calendar API and generate backend/token.json.

Usage:
    python backend/scripts/google_calendar_auth.py
"""

from __future__ import annotations

from pathlib import Path
import sys

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from app.config import settings  # noqa: E402
from app.scheduling.calendar import CALENDAR_SCOPES  # noqa: E402


def main() -> int:
    from google.auth.transport.requests import Request
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow

    cred_path = Path(settings.google_credentials_file)
    if not cred_path.is_absolute():
        cred_path = BACKEND_DIR / cred_path

    token_path = Path(settings.google_token_file)
    if not token_path.is_absolute():
        token_path = BACKEND_DIR / token_path

    creds: Credentials | None = None
    if token_path.exists():
        creds = Credentials.from_authorized_user_file(
            str(token_path), CALENDAR_SCOPES
        )

    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            if not cred_path.exists():
                print(
                    f"Missing OAuth client credentials file at {cred_path.name}. "
                    "Download credentials.json from Google Cloud Console and place it in /backend."
                )
                return 1
            flow = InstalledAppFlow.from_client_secrets_file(
                str(cred_path), CALENDAR_SCOPES
            )
            creds = flow.run_local_server(port=0)

        token_path.write_text(creds.to_json(), encoding="utf-8")

    print(f"Google Calendar authorization succeeded. Saved token file: {token_path.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
