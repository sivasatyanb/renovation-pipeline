# RenovAI — Unified Design Studio, Deep Research & Voice Bargaining Pipeline

A single end-to-end Flutter + FastAPI home-renovation pipeline that combines:
1. **Design Studio (Nano Banana before/after rendering)**: Upload or select a room photo, dictate (`en-US`) or type a renovation brief, generate a photorealistic before/after renovation render with interactive slider comparison and spoken voice confirmation, and automatically extract the structured renovation `Project` (`room`, `style`, `work_items`, `render_urls`).
2. **5-Question MCQ Quiz & Autonomous Deep Research**: Guides the homeowner through 5 renovation preference questions and runs multi-phase **Gemini Deep Research** to discover, structure, verify, and rank local contractors with pre-built negotiation call briefs.
3. **AI Voice Bargaining & Automatic Google Calendar Booking**: Runs an audible two-agent negotiation call (**Customer Agent** vs. **Renovator Agent**), verifies the agreed price and slot against the transcript, and automatically schedules a 45-minute in-person site visit on Google Calendar.

---

## Repository Structure

| Directory | Description |
| :--- | :--- |
| `/shared` | Canonical JSON Schemas (`render_request`, `render_status`, `research_request`, `research_response`, `job_status`, `call_request`, `call_status`), 5 MCQ config (`quiz_questions.json`), and fixtures (`demo_project.json`, `demo_result.json`, `demo_call.json`, `demo_call_replay/`, `demo_render/`). |
| `/backend` | Python + FastAPI backend implementing the Design Studio rendering pipeline (`/renders`), 3-phase contractor research pipeline (`/research`), two-agent voice negotiation (`/calls`), Google Calendar scheduling, and stage-safe replay modes (`DEMO_MODE`, `CALL_REPLAY`, `RENDER_REPLAY`). |
| `/mobile` | Unified Flutter app (Android + Web) implementing: `Start (city) -> Design Studio -> Quiz -> Research -> Results -> Profile Details -> Call & Booking`. |
| `AGENTS.md` | Standing rules, directory ownership, safety guardrails, and architecture contract. |

---

## 1. Backend Setup & Run Commands (`/backend`)

### Prerequisites
- Python 3.11+ (configured with Python `3.11.9` on Windows ARM64)
- A valid Gemini API key (`GEMINI_API_KEY` in `backend/.env`)

### Setup
From the repository root:
```powershell
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

### Verify Gemini Models (`spike_gemini.py`)
```powershell
# Verify STRUCTURING_MODEL and FALLBACK_MODEL:
.\backend\.venv\Scripts\python.exe backend/scripts/spike_gemini.py --skip-deep-research

# Verify TALK_MODEL (gemini-3.8-flash) and TTS_MODEL (gemini-3.8-flash-tts):
.\backend\.venv\Scripts\python.exe backend/scripts/spike_gemini.py --calls-only

# Verify IMAGE_MODEL (gemini-2.5-flash-image):
.\backend\.venv\Scripts\python.exe backend/scripts/spike_gemini.py --render-only
```

### Run Backend Automated Tests
```powershell
.\backend\.venv\Scripts\pytest.exe backend/tests -v
```

### Start the FastAPI Server

> **Important Note on In-Memory State (`RENDERS`, `JOBS` & `CALLS`)**: Run the backend **without `--reload`** during live demos or end-to-end tests so in-memory renders, research jobs, and synthesized WAV audio are not cleared on file changes.

#### Stage-Safe Demo Preset (Recommended for Stage Demos — Zero Live Gemini Calls)
Set the following in `backend/.env`:
```ini
DEMO_MODE=true
CALL_REPLAY=true
RENDER_REPLAY=true
```
Then start the backend from the repository root:
```powershell
.\backend\.venv\Scripts\uvicorn.exe app.main:app --app-dir backend --port 8000
```
In this preset:
- `POST /renders` serves the curated Paris Japandi bedroom before/after render and spoken confirmation from `shared/fixtures/demo_render/` with a visible **Replay** badge.
- `POST /research` simulates phases in ~10s and returns `shared/fixtures/demo_result.json`.
- `POST /calls` replays the recorded 7-turn `Atelier Kanso` negotiation (`9200 EUR -> 8200 EUR`, `Match`) from `shared/fixtures/demo_call_replay/` with a visible **Replay** badge and generates the Google Calendar booking link.

#### Live Studio Render + Live Voice Call Mode
Set `RENDER_REPLAY=false` and/or `CALL_REPLAY=false` in `backend/.env` (keep `DEMO_MODE=true` to avoid long Deep Research runs):
```powershell
.\backend\.venv\Scripts\uvicorn.exe app.main:app --app-dir backend --port 8000
```

#### Google Calendar OAuth Setup (Automatic In-Person Meeting Booking)
When a call ends in a verified **Match**, the backend books a **45-minute in-person renovation meeting** at the agreed slot:
- **Without OAuth (`token.json` absent)**: Returns `status="link_only"` with a clickable **Google Calendar Template URL**.
- **With Google Calendar OAuth (`token.json` present)**: Calls Google Calendar API `events.insert` with a deterministic event ID:
  1. Save your OAuth 2.0 Desktop Client JSON as `backend/credentials.json` (never committed).
  2. Run the one-time interactive sign-in script to generate `backend/token.json`:
     ```powershell
     .\backend\.venv\Scripts\python.exe backend/scripts/google_calendar_auth.py
     ```
  3. Set `INVITE_ALLOWLIST=your.email@example.com` in `backend/.env` if you want calendar email invites sent to an allowlisted test address. Contractors are never invited.

#### Expose Backend on LAN for a Physical Android Phone (`--host 0.0.0.0`)
1. Find your laptop's LAN IPv4 address (e.g., `192.168.1.42`) via `ipconfig`.
2. Start Uvicorn bound to `0.0.0.0`:
   ```powershell
   .\backend\.venv\Scripts\uvicorn.exe app.main:app --app-dir backend --host 0.0.0.0 --port 8000
   ```
3. Verify from your phone's browser that `http://<LAPTOP_LAN_IP>:8000/health` returns `{"status":"ok",...}`.

---

## 2. Mobile Setup & Run Commands (`/mobile`)

### Prerequisites
- Flutter SDK (`3.47.5` stable)

### Setup & Tests
From the repository root:
```powershell
cd mobile
flutter pub get
flutter analyze
flutter test
```

### Run in Chrome Web (Mobile Viewport — Local Dev / QA)
```powershell
cd mobile
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

### Building & Running on a Machine with the Android SDK
1. **Run on an Android Emulator** (uses default `http://10.0.2.2:8000` host loopback):
   ```bash
   cd mobile
   flutter run
   ```
2. **Run or Build Debug APK for a Physical Android Phone over LAN**:
   > `mobile/android/app/src/debug/AndroidManifest.xml` enables `android:usesCleartextTraffic="true"` **in debug builds only**. Release builds (`src/main/AndroidManifest.xml`) enforce HTTPS by default.

   ```bash
   cd mobile
   flutter run --debug --dart-define=API_BASE_URL=http://192.168.1.42:8000
   # Or build an installable debug APK:
   flutter build apk --debug --dart-define=API_BASE_URL=http://192.168.1.42:8000
   ```
