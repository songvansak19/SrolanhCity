# SrolanhCity · ស្រឡាញ់ទីក្រុង

A **Khmer-first, bilingual (Khmer / English) civic infrastructure reporting app** for all **25 Capital & Provinces of Cambodia** — helping citizens report potholes, broken streetlights, clogged drains, illegal waste dumping, and other street hazards in seconds, track repairs transparently, and prioritize urgent road hazards automatically.

🌐 **Live Web Demo:** [https://songvansak19.github.io/SrolanhCity/](https://songvansak19.github.io/SrolanhCity/)

---

## Key Features

### 1. Fast 3-Step Civic Reporting
- **Step 1 — Mandatory Photo Evidence (≥ 1 Required) with 2-Layer AI Guard & Auto-Saved GPS Anchor Drafts**: Requires at least 1 real photo (Camera or Gallery, up to 3 angles) with pure-Dart pre-strip EXIF GPS/timestamp extraction, instant fail-fast Step 1 photo-GPS status feedback, a **2-layer AI civic-issue guard** (strict public-space verification rejecting private backyards/indoors + `≥ 75%` confidence threshold, hard-blocking Step 2 → 3 on non-civic photos), automatic draft persistence when a Camera or EXIF GPS anchor locks ("snap now, finish later"), and complete JPEG **EXIF / GPS metadata stripping** (`APP1`, `APP2`, `APP13`, `COM` markers removed before storage or upload). Direct Web `FileReader` + `<canvas>` decoding ensures reliable gallery uploads on Android/iOS mobile browsers.
- **Step 2 — Details & Transcript-Only Khmer/English Voice Input**: Supports Hold-to-Speak and Tap-to-Toggle voice-to-text transcription with a 1-tap `ខ្មែរ / EN` switcher, live sound-level waveform, quick hazard tags, and backend-ready AI transcription (ephemeral temp clips deleted immediately after transcribing, zero saved audio file bloat).
- **Step 3 — Strict Universal 150 m Zone, Multi-Incident Picker & Out-of-Range Return**: Strictly anchors every submission to verified **Fresh Photo EXIF GPS (≤ 30 days) → Live Camera GPS → Live Device GPS** inside Cambodia (zero unverified remote bypasses; blocks Mock GPS & impossible travel). Displays **one clean 150 m detection ring**, lists **all** open same-category Master Incidents within 150 m with in-place quick preview, tappable map markers, collapsible map drawer, and a 1-tap **`+ Submit as a new separate report here`** option (`> 50 m` from own ticket), plus a floating & card **"Return to 150 m zone"** button whenever the pin is dragged out of range.
- **Phone OTP & Guest-First Sign-In (`AuthPage`)**: Supports Phone OTP sign-in or 1-tap **Continue as Guest (`ភ្ញៀវ`)** with optional phone and home area, and supports custom **Other Issue (`បញ្ហាផ្សេងៗ`)** reports when switching categories at the same spot.

### 2. Nationwide 25-Province Interactive Map
- **Cambodia-Bounded Live Map**: Constrained smoothly over Cambodia (`minZoom: 7.0`, `maxZoom: 19.0`) with zero world wrapping or grey polar voids.
- **3-Tier Pure-Dart Zoom Clustering**:
  - **Country / Province view (`zoom < 10.2`)**: Province cluster bubbles (e.g., `ភ្នំពេញ · 13`, `សៀមរាប · 2`, `បាត់ដំបង · 1`) colored by highest open priority (`P1–P5`).
  - **District / City view (`10.2 – 13.4`)**: Adaptive spatial-grid cluster circles.
  - **Street view (`zoom ≥ 13.4`)**: Individual `P1–P5` and `✓` resolved pins.
- **Viewport-Scoped Carousel, Priority Sort & Province Quick-Jump**: Bottom incident cards dynamically reflect only the active map viewport with **Newest / Priority score / Most affected** sorting, paired with a searchable 25-province switcher and 1-tap **All Cambodia** overview.

### 3. 150 m Multi-Incident Detection, Multi-Citizen Comments & Priority Thresholds (`P1–P5`)
- **150 m Multi-Candidate Clustering & 50 m Self-Duplicate Guard**: Detects all open same-category reports within **150 m**, allowing citizens to preview and join a specific **Master Incident** or submit a separate new ticket (`> 50 m` from their own open report). Re-reporting an issue already owned within `50 m` directs you to **View your existing report** or switch category.
- **Multi-Citizen Comment Threads, Inline Translation & Live Sync**: Joining or remotely supporting a Master Incident preserves every reporter's written comment, transparent remote area tag, and extra photos. Citizens can add, delete, or **translate comments and report descriptions inline (`Khmer ↔ English`)** directly on the **Tracking** screen with **newest-first pagination (`+10` step)**, **pull-to-refresh**, and **real-time WebSocket sync** (clearing synced local cache when the backend has no reports). Notes use privacy-first labels (`Original reporter`, `Citizen #N`, `You`, `Anonymous`), reconcile silent confirmations honestly (`N other citizen(s) confirmed without commenting`), fall back to `No comment` when empty, and surface compact `+N more` pills across the Map sheet, My Reports, and Area News.
- **Priority Score Breakdown & P5 → P1 Threshold Table**: Combines Road Traffic (`40%`), Danger Level (`30%`), and Affected Citizens (`30%`) into an interactive donut chart, factor bars, and a highlighted **P5 (`4.5 – 5.0`) → P1 (`1.0 – 1.4`)** target-fix threshold table.

### 4. Strict GPS `"Affects me"` Support & Transparent Remote Area Tagging
- **Live Cambodia GPS Strictly Required**: GPS must be enabled (zero unverified bypasses; Mock/Fake GPS and outside-Cambodia GPS are always blocked).
- **`≤ 150 m`** → Instant 1-tap **`✓ Verified on-site (`ផ្ទៀងផ្ទាត់នៅទីតាំង`)`**.
- **`> 150 m` (Different Location)** → Strictly opens a **"Why does this affect you?"** reason sheet and transparently tags the support by the highest differing Cambodia administrative level without exposing exact supporter GPS:
  - Different **Province** → **`Remote support · <Province>`** (`គាំទ្រពីចម្ងាយ · ខេត្ត...`, requires written note, capped at `3/24h`)
  - Different **District / Khan** → **`Remote support · <District/Khan>`** (`គាំទ្រពីចម្ងាយ · ខណ្ឌ/ស្រុក...`)
  - Different **Village / Sangkat** → **`Remote support · <Village/Sangkat>`** (`គាំទ្រពីចម្ងាយ · ភូមិ/សង្កាត់...`)
- **Hard Guardrails**: Rate-limited to **10 supports per 24 hours** (max `3` cross-province per 24h), automatically refunded on **Undo Support** along with removing the citizen's remote-support comment.

### 5. 4-Stage Accountability Tracking & Nationwide Area News
- **Live Timeline**: `Submitted` → `Scheduled` → `Crew On-Site` → `Resolved` with a **Before / After draggable comparison slider**, pinch-to-zoom lightbox, 5-emoji satisfaction rating, and a **15-minute Quick Edit / Withdraw** grace period for newly submitted reports.
- **3-Level Nationwide Area News & GIS Routing**: Browse reports across **25 Capital & Provinces → Khan / Krong / Srok → Sangkat / Khum** (or **All Cambodia**), with automatic routing to **MPWT**, **Phnom Penh Capital Hall**, **Provincial DPWT**, **EDC Branches**, and **Municipal / District Administrations**.
- **Offline-First Reopen Auto-Sync & Installable Mobile PWA**: Queues reports, photos, and GPS pins created offline with a global sync status banner and automatically syncs queued items both on live reconnect and on cold reopen when back online; persists locally as JSON on mobile and `window.localStorage` on Web; ships with a custom offline-first Service Worker ([sw.js](web/sw.js)) caching the app shell, local CanvasKit, bundled assets, Khmer/English fonts, and visited map tiles for full offline cold-launch, plus full **SrolanhCity** PWA branding (`manifest.json`, Mekong Teal theme color, adaptive maskable icons, and iOS Apple Touch icon).
- **Help Center, Floating AI Civic Assistant Bubble & WCAG 2.1 AA Accessibility**: App-wide draggable, edge-snapping AI Assistant bubble (bottom-sheet chat on mobile, corner window on web/desktop, auto-hidden on onboarding/camera/lightbox/dialogs/keyboard, hide via long-press or menu with Undo + Profile/Help Center toggle) sharing one conversation with the Help Center (`មជ្ឈមណ្ឌលជំនួយ`), Cambodia hotlines (`1190`, `1298`, `117`), expandable bilingual FAQs, live `#SC-XXXXX` ticket lookup, backend LLM hook (`POST /api/v1/ai/help-chat`), reduced-motion-safe page transitions, and audited WCAG 2.1 AA contrast, semantics, and tap targets.

---

## Architecture

SrolanhCity follows a clean layered architecture with strict **Client → Backend → AI** separation (no third-party AI API keys live inside the mobile/web client):

```text
lib/
├── domain/
│   ├── models/        # CivicReport, CitizenComment, UserProfile, AppSettings, 25-Province Catalog
│   └── services/      # PriorityCalculator, GisRoutingService, SpatialClusteringService,
│                      # MapClusterService, SupportEligibilityService, AiClassifierService
├── data/
│   ├── repositories/  # ReportRepository (state, offline-first queue, backend & WebSocket sync)
│   └── services/      # CivicBackendApiService, BackendCivicAiService, LocationService,
│                      # ReverseGeocodingService, CommentTranslationService, ExifStripper,
│                      # LocalStorageService & ws_helper (IO + Web conditional imports)
└── ui/
    ├── core/          # Theme (Mekong Teal + Angkor Saffron), Bilingual L10n, Widgets
    └── features/      # Welcome, Home, Map, Report Wizard, Tracking, Area News, Alerts, Profile

backend/
└── app/
    ├── api/v1/        # Auth, Reports, Comments, Support, Alerts, AI Proxy, WebSocket (/ws/reports)
    ├── core/          # JWT auth, EXIF stripping, anti-spoof integrity, PriorityCalculator
    ├── db/            # Async SQLAlchemy + GeoAlchemy2 models (PostgreSQL/PostGIS & SQLite)
    └── services/      # GIS routing, spatial clustering, AI proxy, analytics & notifications
```

### APIs & External Services

#### Third-party network APIs used by the app

| Service | Endpoint(s) | Purpose |
| --- | --- | --- |
| OpenStreetMap tile service | `GET https://tile.openstreetmap.org/{z}/{x}/{y}.png` | Displays map tiles; visited tiles can be cached by the Web service worker. |
| OpenStreetMap Nominatim | `GET https://nominatim.openstreetmap.org/reverse` and `GET https://nominatim.openstreetmap.org/search` | Reverse-geocodes report locations and searches for places in Cambodia. |
| Google Translate (unofficial endpoint) | `GET https://translate.googleapis.com/translate_a/single` | Primary Khmer ↔ English comment translation provider. |
| MyMemory Translation | `GET https://api.mymemory.translated.net/get` | Fallback Khmer ↔ English comment translation provider. |
| ipwho.is | `GET https://ipwho.is/` | Optional, coarse IP-country check for anti-spoofing; it does not block users when unavailable. |

These services are called directly by the client and do not require API keys in the app. Geocoding sends coordinates or place-search text to Nominatim; translation sends the comment text to its provider; IP geolocation necessarily exposes the request's IP address to ipwho.is.

#### SrolanhCity FastAPI Backend (Connected via `API_BASE_URL`)

When `API_BASE_URL` is configured (for example `https://srolanhcity-api.onrender.com` or `http://localhost:8000`), `CivicBackendApiService`, `BackendCivicAiService`, `HttpCommentTranslationService`, and `ReportRepository` connect end-to-end with offline-first fallback and real-time WebSocket updates:

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/v1/auth/guest` | Issue guest JWT session and persistent citizen user ID. |
| `GET` | `/api/v1/reports` | Load clustered or single reports for the map viewport (`min_lat`, `min_lng`, `max_lat`, `max_lng`, `zoom`). |
| `POST` / `PATCH` / `DELETE` | `/api/v1/reports` | Create, quick-edit, or withdraw civic reports with EXIF-stripped photos. |
| `POST` | `/api/v1/reports/{id}/rating` | Submit citizen satisfaction rating (1–5) on resolved repairs. |
| `POST` / `DELETE` | `/api/v1/reports/{id}/comments` | Post or remove multi-citizen tracking comments. |
| `POST` / `DELETE` | `/api/v1/reports/{id}/support` | Add or undo GPS-verified `"Affects me"` community support. |
| `GET` / `POST` / `DELETE` | `/api/v1/alerts` | Fetch, mark read, clear, and restore notification alerts. |
| `WS` | `/api/v1/ws/reports` | Push real-time `reports_updated` events across connected mobile & web clients. |
| `POST` | `/api/v1/ai/classify-issue` | Analyze a report photo with the 2-layer public-space + `≥ 75%` confidence guard and suggest category/severity. |
| `POST` | `/api/v1/ai/transcribe-voice` | Transcribe a temporary voice recording. |
| `POST` | `/api/v1/ai/translate` | Translate citizen comments (`km ↔ en`) before Google/MyMemory fallback. |
| `POST` | `/api/v1/ai/help-chat` | Answer Help Center questions using the backend assistant. |

Configure the backend base URL when running or building the app (omit `API_BASE_URL` to run in 100% offline/demo mode):

```bash
flutter run --dart-define=API_BASE_URL=https://srolanhcity-api.onrender.com
```

---

## Getting Started

### Prerequisites
- **Flutter SDK**: `3.50+` (Dart `^3.14.0`)
- Android Studio / Xcode (for mobile) or Chrome (for Web)

### Install & Run
```bash
flutter pub get

# Run on Android emulator / device
flutter run

# Run in Chrome (Web)
flutter run -d chrome
```

### Run Verification & Tests
```bash
# Flutter
dart format lib test
dart analyze --fatal-infos
flutter test

# FastAPI Backend
cd backend && .venv/bin/ruff check app tests && .venv/bin/pytest -v
```
The test suite includes **126 Flutter unit, widget, and WCAG 2.1 AA accessibility tests** and **20 backend FastAPI tests** covering Priority Score tiers, Map priority sorting, multi-citizen Master Incident comments & inline Khmer/English translation, self-duplicate & `"Submit as a new separate report here"` flows, Guest profile & resilient data-URI photo uploads, UTC timestamp normalization, backend `CivicBackendApiService` & WebSocket sync, transcript-only Khmer/English voice input, 5-layer anti-spoof, Step 1 mandatory photo & auto-saved GPS anchor drafts, Step 3 strict universal 150 m zone, multi-incident picker & out-of-range return navigation, ODC/25-province GIS routing, stable zoom clustering & overview carousel visibility, strict GPS `"Affects me"` & hierarchical Village/District/Province transparent remote-reason support, offline reopen auto-sync, floating AI Assistant bubble & Help Center ticket lookup, PWA manifest & cache-first map tile service worker, and automated Flutter accessibility guidelines.

---

## Building & Deploying

### GitHub Pages (Automated)
Pushing to `main` automatically runs [deploy-pages.yml](.github/workflows/deploy-pages.yml), building Flutter Web with `--base-href "/SrolanhCity/"` (and `--dart-define=API_BASE_URL=...` when the `API_BASE_URL` repository variable is set) and deploying to [https://songvansak19.github.io/SrolanhCity/](https://songvansak19.github.io/SrolanhCity/).

### FastAPI Backend & Cloud Deployment (Render + Supabase)
- **Backend (`backend/`)**: FastAPI + SQLAlchemy (async) supporting **PostgreSQL + PostGIS** (e.g., Supabase) in production and **SQLite** (`sqlite+aiosqlite:///./srolanhcity_dev.db`) for zero-Docker local development, with guest/phone JWT auth, EXIF stripping, GIS routing, priority scoring, AI proxy endpoints (`/api/v1/ai/*`), and **real-time WebSocket live push** (`/api/v1/ws/reports`).
- **Render Blueprint**: [render.yaml](render.yaml) deploys `backend/` via Docker in the Singapore region with `/api/v1/health` checks.
- **Local Backend + Flutter**:
  ```bash
  # Terminal 1: Start local FastAPI backend (SQLite)
  cd backend && DATABASE_URL=sqlite+aiosqlite:///./srolanhcity_dev.db .venv/bin/uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

  # Terminal 2: Run Flutter connected to local backend (or omit API_BASE_URL for offline/demo mode)
  flutter run --dart-define=API_BASE_URL=http://localhost:8000
  ```

### Manual Web Build
```bash
# For root domains (Vercel, Netlify, VPS / Caddy / Nginx)
flutter build web --release --no-web-resources-cdn

# For GitHub Pages subpath (bundles CanvasKit locally for full offline PWA launch)
flutter build web --release --base-href "/SrolanhCity/" --no-web-resources-cdn --dart-define=API_BASE_URL=https://srolanhcity-api.onrender.com
```

### Android APK Build
```bash
flutter build apk --release --dart-define=API_BASE_URL=https://srolanhcity-api.onrender.com
```

---

## Roadmap & Venture Vision

- **MVP (Current Build)**: Bilingual Flutter mobile & web app, fast cache-first 25-province OpenStreetMap interactive map with priority sort, pure-Dart EXIF stripping, 150 m multi-incident detection & clustering, `P1–P5` priority scoring, strict universal 150 m reporting zone, strict GPS `"Affects me"` with hierarchical Village/District/Province transparent remote support, 5-layer anti-spoof, floating AI Assistant bubble, FastAPI + Supabase/SQLite backend with real-time WebSocket live push, and 146 automated Flutter & backend tests.
- **Phase 1 — Live AI Backend & Pilot**: Connect live `/api/v1/ai/` classification and Khmer speech-to-text endpoints, deploy the 2–3 staff verification dashboard, and pilot in a target Phnom Penh district with local Village Chiefs (`Me Phum`) and drivers.
- **Phase 2 — Elderly Accessibility & Local Fixer Monetization**: Launch a **Telegram Bot** intake channel for zero-install reporting, alongside a **Fixed-Price Local Fixer** directory connecting residents with verified neighborhood plumbers, electricians, and handymen for private household repairs—creating a sustainable revenue stream while keeping public civic reporting 100% free.
- **Phase 3 — City-Wide & Ministry Scale**: Expand across all 14 Khans of Phnom Penh and major provinces with direct municipal dispatch integration and anonymized Open Data infrastructure heatmaps.

---

## Team

Built by **TechnoTeam** for the **Open Data × AI Venture Hackathon 1.0**:

- **Bou Socheat**
- **Song Vansak**
- **Heng Sovannarith**
- **Seng Pich**
- **Chheng Sopongreasey**

---

## License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.
