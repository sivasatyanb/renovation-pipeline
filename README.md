# Automated Home-Renovation Pipeline — Deep Research & Contractor Vetting

A mobile + backend pipeline that guides a homeowner through a 5-question renovation quiz, runs autonomous multi-phase **Gemini Deep Research** to discover and vet local contractors, normalises and verifies contractor phone numbers against live source web pages, ranks the top renovators with pre-built negotiation call briefs, runs an **audible two-agent AI voice bargaining call** (Customer Agent vs. Renovator Agent), and **automatically schedules an in-person meeting** on Google Calendar when a deal matches the customer's requirements.

---

## Repository Structure

| Directory | Description |
| :--- | :--- |
| `/shared` | Canonical JSON Schemas (`research_request`, `research_response`, `job_status`, `call_request`, `call_status`), 5 MCQ config (`quiz_questions.json`), and JSON fixtures (`demo_project.json`, `demo_result.json`, `demo_call.json`, `demo_call_replay/`). |
| `/backend` | Python + FastAPI backend implementing the 3-phase research pipeline, two-agent voice negotiation (`TALK_MODEL` + `TTS_MODEL`), deterministic outcome/match verification, Google Calendar scheduling, and `DEMO_MODE` / `CALL_REPLAY`. |
| `/mobile` | Flutter app (Android + Web) implementing the full flow: Start -> Quiz -> Research Progress -> Ranked Results -> Contractor Profile Details -> Live Voice Bargaining & Meeting Booking (`CallScreen`). |
| `AGENTS.md` | Standing rules, directory ownership, safety guardrails, and architecture contract. |

---

## 1. Backend Setup & Run Commands (`/backend`)

### Prerequisites
- Python 3.11+ (configured with Python `3.11.9` on Windows ARM64)
- A valid Gemini API key (`GEMINI_API_KEY`)

### Setup
```powershell
cd C:\Users\sivas\.gemini\antigravity\scratch\renovation-pipeline

# 1. Create and activate the virtual environment
py -3.11 -m venv backend/.venv
.\backend\.venv\Scripts\Activate.ps1

# 2. Upgrade pip and install prebuilt binary wheels
python -m pip install --upgrade pip
python -m pip install --only-binary=:all: -r backend/requirements.txt

# 3. Configure environment variables
Copy-Item backend\.env.example backend\.env
# Edit backend\.env and set GEMINI_API_KEY=...
```

### Verify Gemini Models, Deep Research, TALK_MODEL & TTS_MODEL
```powershell
# Verify STRUCTURING_MODEL and FALLBACK_MODEL:
.\backend\.venv\Scripts\python.exe backend/scripts/spike_gemini.py --skip-deep-research

# Verify TALK_MODEL (gemini-3.8-flash) and TTS_MODEL (gemini-3.8-flash-tts):
.\backend\.venv\Scripts\python.exe backend/scripts/spike_gemini.py --calls-only
```

### Run Backend Tests
```powershell
.\backend\.venv\Scripts\pytest.exe backend/tests -v
```

### Start the FastAPI Server

> **Important Note on In-Memory State (`JOBS` & `CALLS`)**: Run the backend **without `--reload`** during live voice calls or end-to-end tests so in-memory research jobs and synthesized WAV call audio are not cleared on file changes.

#### Local Development (Demo Research Mode + Live Voice Call)
Ensure `DEMO_MODE=true` and `CALL_REPLAY=false` in `backend/.env`:
```powershell
.\backend\.venv\Scripts\uvicorn.exe app.main:app --app-dir backend --port 8000
```

#### Stage Replay Mode (`CALL_REPLAY=true` — Zero Gemini Calls)
After a successful live call, the backend automatically saves the turns, outcome, and WAV audio files to `shared/fixtures/demo_call_replay/` (falling back to transcript-only `shared/fixtures/demo_call.json` if no recording exists).
To replay a call on stage with zero Gemini API calls:
1. Set `CALL_REPLAY=true` in `backend/.env`.
2. Start the backend:
   ```powershell
   .\backend\.venv\Scripts\uvicorn.exe app.main:app --app-dir backend --port 8000
   ```
3. The mobile app will play the recorded conversation and display a **Replay** badge while running the exact same match and calendar scheduling logic.

#### Google Calendar OAuth Setup (Automatic In-Person Meeting Booking)
When a call ends in a verified **Match**, the backend automatically books a **45-minute in-person renovation meeting** at the agreed slot:
- **Without OAuth (`token.json` absent)**: The call still succeeds and returns `status="link_only"` with a clickable **Google Calendar Template URL** (`https://calendar.google.com/calendar/render?action=TEMPLATE&...`).
- **With Google Calendar OAuth (`token.json` present)**: The backend calls Google Calendar API `events.insert` with a deterministic event ID (preventing duplicate events on reruns).
  1. Download an OAuth 2.0 Desktop Client JSON from Google Cloud Console (with Google Calendar API enabled) and save it as `backend/credentials.json` (never committed to git).
  2. Run the one-time interactive sign-in script in your browser to generate `backend/token.json`:
     ```powershell
     .\backend\.venv\Scripts\python.exe backend/scripts/google_calendar_auth.py
     ```
  3. **Attendee Safety Allowlist (`INVITE_ALLOWLIST`)**: By default, `INVITE_ALLOWLIST=` is empty so no external email invitations are sent. To allow inviting specific test email addresses, set `INVITE_ALLOWLIST=your.email@example.com` in `backend/.env`. Contractors are never invited.

#### Live Deep Research Mode
Set `DEMO_MODE=false` in `backend/.env`:
```powershell
.\backend\.venv\Scripts\uvicorn.exe app.main:app --app-dir backend --port 8000
```

#### Expose Backend on LAN for a Physical Android Phone (`--host 0.0.0.0`)
To allow a physical Android phone on the same Wi-Fi/LAN network to reach the backend:
1. Find your laptop's LAN IPv4 address (e.g., `192.168.1.42`):
   ```powershell
   ipconfig
   ```
2. Add your LAN origin or subnet to `CORS_ALLOWED_ORIGINS` in `backend/.env` if needed, and bind Uvicorn to `0.0.0.0`:
   ```powershell
   .\backend\.venv\Scripts\uvicorn.exe app.main:app --app-dir backend --host 0.0.0.0 --port 8000
   ```
3. Verify from your phone's browser that `http://<LAPTOP_LAN_IP>:8000/health` returns `{"status":"ok",...}`.

---

## 2. Mobile Setup & Run Commands (`/mobile`)

### Prerequisites
- Flutter SDK (`3.47.5` stable)

### Setup & Tests
```powershell
cd C:\Users\sivas\.gemini\antigravity\scratch\renovation-pipeline\mobile
flutter pub get
flutter analyze
flutter test
```

### Run in Chrome Web (Mobile Viewport — Local Dev / QA)
```powershell
cd C:\Users\sivas\.gemini\antigravity\scratch\renovation-pipeline\mobile
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

### Building & Running on an x64 Machine with the Android SDK

On an x64 (or ARM64) machine with **Android Studio / Android SDK** installed:

1. **Verify Android Toolchain**:
   ```bash
   flutter doctor -v
   ```
2. **Run on an Android Emulator** (uses the default `http://10.0.2.2:8000` host loopback):
   ```bash
   cd mobile
   flutter run
   ```
3. **Run or Build Debug APK for a Physical Android Phone over LAN**:
   > **Note on Cleartext HTTP**: `mobile/android/app/src/debug/AndroidManifest.xml` enables `android:usesCleartextTraffic="true"` **in debug builds only**, allowing HTTP traffic to your laptop's LAN IP (`http://<LAPTOP_LAN_IP>:8000`). Release builds (`src/main/AndroidManifest.xml`) enforce HTTPS by default.

   ```bash
   cd mobile

   # Run directly on a USB/Wi-Fi connected physical Android device:
   flutter run --debug --dart-define=API_BASE_URL=http://192.168.1.42:8000

   # Or build an installable debug APK configured with your laptop's LAN IP:
   flutter build apk --debug --dart-define=API_BASE_URL=http://192.168.1.42:8000
   ```
   The generated APK will be at `mobile/build/app/outputs/flutter-apk/app-debug.apk`.
