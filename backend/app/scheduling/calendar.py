"""Google Calendar event creation, allowlist enforcement, deduplication, and template fallback."""

from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone
import hashlib
from pathlib import Path
from typing import Any
from urllib.parse import urlencode

from app.config import BACKEND_DIR, settings
from app.models import (
    BookingResult,
    CallOutcome,
    Contractor,
    MeetingInput,
    ResearchRequest,
)

CALENDAR_SCOPES = ["https://www.googleapis.com/auth/calendar.events"]

# In-memory deduplication registry keyed by deterministic event_id
BOOKED_EVENTS: dict[str, BookingResult] = {}


def compute_deterministic_event_id(
    project_id: str,
    contractor_id: str,
    agreed_slot: str,
) -> str:
    """Compute a deterministic base32hex-compatible Google Calendar event ID."""
    digest = hashlib.sha256(
        f"{project_id}:{contractor_id}:{agreed_slot}".encode("utf-8")
    ).hexdigest()
    return f"reno{digest}"


def _format_utc_calendar_timestamp(dt: datetime) -> str:
    utc_dt = dt.astimezone(timezone.utc)
    return utc_dt.strftime("%Y%m%dT%H%M%SZ")


def build_calendar_template_url(
    summary: str,
    start_dt: datetime,
    end_dt: datetime,
    location: str,
    description: str,
) -> str:
    """Build a Google Calendar web template link for 1-click user addition."""
    dates_param = (
        f"{_format_utc_calendar_timestamp(start_dt)}/"
        f"{_format_utc_calendar_timestamp(end_dt)}"
    )
    params = urlencode(
        {
            "action": "TEMPLATE",
            "text": summary,
            "dates": dates_param,
            "details": description,
            "location": location,
        }
    )
    return f"https://calendar.google.com/calendar/render?{params}"


def resolve_token_path() -> Path:
    """Resolve the path to token.json from settings."""
    configured = Path(settings.google_token_file)
    if configured.is_absolute():
        return configured
    return BACKEND_DIR / configured


def _insert_calendar_event_sync(
    token_path: Path,
    event_body: dict[str, Any],
    send_updates: str,
    calendar_service: Any | None = None,
) -> dict[str, Any]:
    """Insert or fetch the event on the primary Google Calendar."""
    service = calendar_service
    if service is None:
        from google.oauth2.credentials import Credentials
        from googleapiclient.discovery import build

        creds = Credentials.from_authorized_user_file(
            str(token_path), scopes=CALENDAR_SCOPES
        )
        service = build("calendar", "v3", credentials=creds, cache_discovery=False)

    try:
        created = (
            service.events()
            .insert(
                calendarId="primary",
                body=event_body,
                sendUpdates=send_updates,
            )
            .execute()
        )
        return dict(created) if isinstance(created, dict) else {"htmlLink": getattr(created, "htmlLink", None)}
    except Exception as exc:
        # Handle HTTP 409 conflict (duplicate event ID already on Google Calendar)
        status_code = getattr(getattr(exc, "resp", None), "status", None)
        if status_code == 409 or "409" in str(exc) or "duplicate" in str(exc).lower():
            existing = (
                service.events()
                .get(calendarId="primary", eventId=event_body["id"])
                .execute()
            )
            return dict(existing) if isinstance(existing, dict) else {"htmlLink": getattr(existing, "htmlLink", None)}
        raise


async def schedule_in_person_meeting(
    research_request: ResearchRequest,
    contractor: Contractor,
    meeting: MeetingInput,
    outcome: CallOutcome,
    is_demo: bool = True,
    stop_requested: bool = False,
    calendar_service: Any | None = None,
) -> BookingResult:
    """Schedule a 45-minute in-person meeting or fall back to a Google Calendar template link."""
    if stop_requested:
        return BookingResult(
            status="failed",
            starts_at=None,
            location=meeting.address,
            event_url=None,
            warnings=["Call was stopped; scheduling aborted."],
        )

    agreed_slot = outcome.agreed_slot
    if not agreed_slot:
        return BookingResult(
            status="failed",
            starts_at=None,
            location=meeting.address,
            event_url=None,
            warnings=["Cannot schedule meeting without an agreed_slot."],
        )

    project_id = research_request.project.project_id
    event_id = compute_deterministic_event_id(
        project_id=project_id,
        contractor_id=contractor.id,
        agreed_slot=agreed_slot,
    )

    if event_id in BOOKED_EVENTS:
        cached = BOOKED_EVENTS[event_id]
        dedup_warnings = list(cached.warnings)
        dedup_msg = "Duplicate booking prevented: returned existing calendar booking for this project, contractor, and slot."
        if dedup_msg not in dedup_warnings:
            dedup_warnings.append(dedup_msg)
        return BookingResult(
            status=cached.status,
            starts_at=cached.starts_at,
            location=cached.location,
            event_url=cached.event_url,
            warnings=dedup_warnings,
        )

    start_dt = datetime.fromisoformat(agreed_slot.replace("Z", "+00:00"))
    end_dt = start_dt + timedelta(minutes=45)

    contractor_display_name = (
        contractor.name
        if is_demo
        else f"{contractor.name} (Simulated Stand-In Call)"
    )
    summary = f"In-person renovation meeting: {contractor_display_name}"

    work_items_summary = ", ".join(
        f"{int(w.quantity) if w.quantity.is_integer() else w.quantity} {w.unit} {w.trade}"
        for w in research_request.project.work_items
    )
    price_str = (
        f"{int(round(outcome.final_price))} {outcome.currency or contractor.expected_price.currency}"
        if outcome.final_price is not None
        else "TBD"
    )
    description = (
        f"Scope: {research_request.answers.scope} renovation ({work_items_summary}) in {research_request.project.client.city}.\n"
        f"Agreed price: {price_str} (Non-binding estimate).\n"
        f"Note: Simulated call via AI Voice Bargaining Assistant."
    )

    template_url = build_calendar_template_url(
        summary=summary,
        start_dt=start_dt,
        end_dt=end_dt,
        location=meeting.address,
        description=description,
    )

    warnings: list[str] = []
    customer_email = meeting.customer_email.strip()
    allowlist_lower = {
        e.strip().lower() for e in settings.invite_allowlist if e and e.strip()
    }
    email_allowed = bool(customer_email and customer_email.lower() in allowlist_lower)

    event_body: dict[str, Any] = {
        "id": event_id,
        "summary": summary,
        "location": meeting.address,
        "description": description,
        "start": {
            "dateTime": start_dt.isoformat(),
            "timeZone": settings.calendar_timezone,
        },
        "end": {
            "dateTime": end_dt.isoformat(),
            "timeZone": settings.calendar_timezone,
        },
    }

    if email_allowed:
        # Only invite the allowlisted customer email; NEVER invite the contractor
        event_body["attendees"] = [{"email": customer_email}]
        send_updates = "all"
    else:
        send_updates = "none"
        if customer_email:
            warnings.append(
                "customer_email is not in INVITE_ALLOWLIST; created event without sending email invite."
            )

    token_path = resolve_token_path()
    if calendar_service is None and not token_path.exists():
        warnings.append(
            "Google Calendar token.json not found; generated fallback Google Calendar template link."
        )
        result = BookingResult(
            status="link_only",
            starts_at=agreed_slot,
            location=meeting.address,
            event_url=template_url,
            warnings=warnings,
        )
        BOOKED_EVENTS[event_id] = result
        return result

    try:
        api_resp = await asyncio.to_thread(
            _insert_calendar_event_sync,
            token_path,
            event_body,
            send_updates,
            calendar_service,
        )
        html_link = api_resp.get("htmlLink") or template_url
        result = BookingResult(
            status="created",
            starts_at=agreed_slot,
            location=meeting.address,
            event_url=html_link,
            warnings=warnings,
        )
        BOOKED_EVENTS[event_id] = result
        return result
    except Exception as exc:
        warnings.append(
            f"Google Calendar API call failed ({exc}); fell back to Google Calendar template link."
        )
        result = BookingResult(
            status="link_only",
            starts_at=agreed_slot,
            location=meeting.address,
            event_url=template_url,
            warnings=warnings,
        )
        BOOKED_EVENTS[event_id] = result
        return result
