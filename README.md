# SrolanhCity · ស្រឡាញ់ទីក្រុង

A **Khmer-first, bilingual (Khmer / English) civic infrastructure reporting app** for all **25 Capital & Provinces of Cambodia** — helping citizens report potholes, broken streetlights, clogged drains, illegal waste dumping, and other street hazards in seconds, track repairs transparently, and prioritize urgent road hazards automatically.

🌐 **Live Web Demo:** [https://songvansak19.github.io/SrolanhCity/](https://songvansak19.github.io/SrolanhCity/)

---

## Key Features

### 1. Fast 3-Step Civic Reporting
- **Photo-First with Automatic Privacy**: Attach up to 3 photos with pure-Dart JPEG **EXIF / GPS metadata stripping** (`APP1`, `APP2`, `APP13`, `COM` markers removed before storage or upload).
- **Telegram-Style Khmer & English Voice Reporting**: Supports both Hold-to-Speak and Tap-to-Toggle voice reporting with a 1-tap `ខ្មែរ / EN` switcher, live sound-level waveform, and backend-ready 16 kHz mono WAV recording.
- **Verified GPS Pinning & Fake-GPS Guard**: Acquires live Cambodia GPS with reverse geocoding and blocks spoofed/mock GPS locations cleanly.
- **Guest-First Privacy & Flexible Issue Reporting**: Starts cleanly as **Guest (`ភ្ញៀវ`)** with optional phone and home area, and supports custom **Other Issue (`បញ្ហាផ្សេងៗ`)** reports with optional custom titles when tapping **"It's a different problem"** near an existing pin.

### 2. Nationwide 25-Province Interactive Map
- **Cambodia-Bounded Live Map**: Constrained smoothly over Cambodia (`minZoom: 7.0`, `maxZoom: 19.0`) with zero world wrapping or grey polar voids.
- **3-Tier Pure-Dart Zoom Clustering**:
  - **Country / Province view (`zoom < 10.2`)**: Province cluster bubbles (e.g., `ភ្នំពេញ · 13`, `សៀមរាប · 2`, `បាត់ដំបង · 1`) colored by highest open priority (`P1–P5`).
  - **District / City view (`10.2 – 13.4`)**: Adaptive spatial-grid cluster circles.
  - **Street view (`zoom ≥ 13.4`)**: Individual `P1–P5` and `✓` resolved pins.
- **Viewport-Scoped Carousel & Province Quick-Jump**: Bottom incident cards dynamically reflect only the active map viewport, paired with a searchable 25-province switcher and 1-tap **All Cambodia** overview.

### 3. Duplicate Clustering, Multi-Citizen Comments & Priority Thresholds (`P1–P5`)
- **Spatial Deduplication & Self-Duplicate Guard**: Detects open same-category reports nearby (`≤ 50 m`, or `≤ 120 m` along the same road) and merges community reports into a single **Master Incident**. Re-reporting an issue already in **My Reports** directs you to **View your existing report** instead of duplicating or self-upvoting, while **"It's a different problem"** lets you switch category or file a separate **Other Issue** ticket.
- **Multi-Citizen Comment Threads**: Joining a Master Incident preserves every reporter's written comment and extra photos, and citizens can add or delete follow-up field notes directly on the **Tracking** screen. Notes use privacy-first labels (`Original reporter`, `Citizen #N`, `You`, `Anonymous`), reconcile silent confirmations honestly (`N other citizen(s) confirmed without commenting`), fall back to `No comment` when empty, and surface compact `+N more` pills across the Map sheet, My Reports, and Area News.
- **Priority Score Breakdown & P5 → P1 Threshold Table**: Combines Road Traffic (`40%`), Danger Level (`30%`), and Affected Citizens (`30%`) into an interactive donut chart, factor bars, and a highlighted **P5 (`4.5 – 5.0`) → P1 (`1.0 – 1.4`)** target-fix threshold table.

### 4. Distance-Aware `"Affects me"` Voting & Anti-Abuse Guardrails
- **`≤ 500 m`** → **Verified nearby (`ផ្ទៀងផ្ទាត់ជិតទីតាំង`)**
- **`500 m – 15 km`** → **City commuter (`អ្នកដំណើរក្នុងតំបន់`)**
- **`> 15 km` or GPS off** → Allowed only inside the citizen's saved **Home District (`អ្នករស់នៅក្នុងតំបន់`)** across all 25 provinces; otherwise blocked with exact distance feedback.
- **Hard Guardrails**: Mock/Fake GPS is always blocked (never bypassed by Home District), and voting is rate-limited to **10 votes per 24 hours** (automatically refunded on **Undo Support**).

### 5. 4-Stage Accountability Tracking & Nationwide Area News
- **Live Timeline**: `Submitted` → `Scheduled` → `Crew On-Site` → `Resolved` with a **Before / After draggable comparison slider**, pinch-to-zoom lightbox, 5-emoji satisfaction rating, and a **15-minute Quick Edit / Withdraw** grace period for newly submitted reports.
- **3-Level Nationwide Area News & GIS Routing**: Browse reports across **25 Capital & Provinces → Khan / Krong / Srok → Sangkat / Khum** (or **All Cambodia**), with automatic routing to **MPWT**, **Phnom Penh Capital Hall**, **Provincial DPWT**, **EDC Branches**, and **Municipal / District Administrations**.
- **Offline-First & Installable Mobile PWA**: Queues reports created offline with a global sync status banner and auto-syncs upon reconnect; persists locally as JSON on mobile and `window.localStorage` on Web; ships with a custom offline-first Service Worker ([sw.js](web/sw.js)) caching the app shell, local CanvasKit, bundled assets, Khmer/English fonts, and visited map tiles for full offline cold-launch, plus full **SrolanhCity** PWA branding (`manifest.json`, Mekong Teal theme color, adaptive maskable icons, and iOS Apple Touch icon).

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
│   ├── repositories/  # ReportRepository (state, persistence, deduplication, daily vote cap)
│   └── services/      # LocationService, ReverseGeocodingService, BackendCivicAiService,
│                      # ExifStripper, AudioRecorderService, VoiceInputService,
│                      # LocalStorageService (IO + Web conditional imports)
└── ui/
    ├── core/          # Theme (Mekong Teal + Angkor Saffron), Bilingual L10n, Widgets
    └── features/      # Welcome, Home, Map, Report Wizard, Tracking, Area News, Alerts, Profile
```

### Connecting the Backend API (Optional)
AI photo classification (`/api/v1/ai/classify-issue`) and voice transcription (`/api/v1/ai/transcribe-voice`) stay cleanly in client draft mode until you point the build at your SrolanhCity backend server:

```bash
flutter run --dart-define=API_BASE_URL=https://api.yourdomain.com
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
dart format lib test
dart analyze --fatal-infos
flutter test
```
The test suite includes **66 unit and widget tests** covering Priority Score tiers, multi-citizen Master Incident comments, self-duplicate & `"It's a different problem"` flows, Guest profile defaults, ODC/25-province GIS routing, stable zoom clustering & carousel scrolling, EXIF stripping, distance-aware `"Affects me"` anti-abuse rules, offline sync, PWA manifest branding, and full UI flows.

---

## Building & Deploying

### GitHub Pages (Automated)
Pushing to `main` automatically runs [deploy-pages.yml](.github/workflows/deploy-pages.yml), building Flutter Web with `--base-href "/SrolanhCity/"` and deploying to [https://songvansak19.github.io/SrolanhCity/](https://songvansak19.github.io/SrolanhCity/).

### Manual Web Build
```bash
# For root domains (Vercel, Netlify, VPS / Caddy / Nginx)
flutter build web --release --no-web-resources-cdn

# For GitHub Pages subpath (bundles CanvasKit locally for full offline PWA launch)
flutter build web --release --base-href "/SrolanhCity/" --no-web-resources-cdn
```

### Android APK Build
```bash
flutter build apk --release
```
