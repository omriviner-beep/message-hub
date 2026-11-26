"""OAuth2 authentication against the Gmail API."""
from __future__ import annotations

from pathlib import Path

# gmail.modify allows reading, labeling, archiving and moving to Trash.
# It does NOT allow permanent deletion - everything this tool does is recoverable.
SCOPES = ["https://www.googleapis.com/auth/gmail.modify"]


def get_service(credentials_path: Path, token_path: Path):
    from google.auth.transport.requests import Request
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow
    from googleapiclient.discovery import build

    creds = None
    if token_path.exists():
        creds = Credentials.from_authorized_user_file(str(token_path), SCOPES)
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            if not credentials_path.exists():
                raise SystemExit(
                    f"לא נמצא קובץ {credentials_path}. ראה README - שלב 'הגדרת גישה ל-Gmail'."
                )
            flow = InstalledAppFlow.from_client_secrets_file(str(credentials_path), SCOPES)
            creds = flow.run_local_server(port=0)
        token_path.write_text(creds.to_json())
        token_path.chmod(0o600)
    return build("gmail", "v1", credentials=creds, cache_discovery=False)
