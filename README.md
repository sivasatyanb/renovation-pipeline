# Automated Home-Renovation Pipeline — Deep Research & Contractor Vetting

A mobile + backend pipeline that guides a homeowner through a 5-question renovation quiz, runs autonomous multi-phase **Gemini Deep Research** to discover and vet local contractors, normalises and verifies contractor phone numbers against live source web pages, and ranks the top 5 renovators with pre-built negotiation call briefs.

---

## Repository Structure

| Directory | Description |
| :--- | :--- |
| `/shared` | Canonical JSON Schemas (`research_request`, `research_response`, `job_status`), 5 MCQ config (`quiz_questions.json`), and JSON fixtures (`demo_project.json`, `demo_result.json`). |
| `/backend` | Python + FastAPI backend implementing the 3-phase pipeline (`researching` -> `structuring` -> `verifying`) and `DEMO_MODE`. |
| `/mobile` | Flutter app (Android + Web) implementing the 5-screen flow: Start -> Quiz -> Research Progress -> Ranked Results -> Contractor Profile Details. |
| `AGENTS.md` | Standing rules, directory ownership, and architecture contract. |

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

### Verify Gemini Models & Deep Research Agent
```powershell
.\backend\.venv\Scripts\python.exe backend/scripts/spike_gemini.py --skip-deep-research
```

### Run Backend Tests
```powershell
.\backend\.venv\Scripts\pytest.exe backend/tests -v
```

### Start the FastAPI Server

#### Local Development (Demo Mode — ~10s simulated phases)
Ensure `DEMO_MODE=true` in `backend/.env`:
```powershell
.\backend\.venv\Scripts\uvicorn.exe backend.app.main:app --reload --port 8000
```

#### Live Deep Research Mode
Set `DEMO_MODE=false` in `backend/.env`:
```powershell
.\backend\.venv\Scripts\uvicorn.exe backend.app.main:app --port 8000
```

#### Expose Backend on LAN for a Physical Android Phone (`--host 0.0.0.0`)
To allow a physical Android phone on the same Wi-Fi/LAN network to reach the backend:
1. Find your laptop's LAN IPv4 address (e.g., `192.168.1.42`):
   ```powershell
   ipconfig
   ```
2. Add your LAN origin or subnet to `CORS_ALLOWED_ORIGINS` in `backend/.env` if needed, and bind Uvicorn to `0.0.0.0`:
   ```powershell
   .\backend\.venv\Scripts\uvicorn.exe backend.app.main:app --host 0.0.0.0 --port 8000
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
