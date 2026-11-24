# SrolanhCity · ស្រឡាញ់ទីក្រុង

A **Khmer-first, bilingual (Khmer / English) civic infrastructure reporting app** for all **25 Capital & Provinces of Cambodia** — helping citizens report potholes, broken streetlights, clogged drains, illegal waste dumping, and other street hazards in seconds, track repairs transparently, and prioritize urgent road hazards automatically.

🌐 **Live Web Demo:** [https://songvansak19.github.io/SrolanhCity/](https://songvansak19.github.io/SrolanhCity/)

---

## Key Features

### 1. Fast 3-Step Civic Reporting
- **Photo-First (≥ 1 Required) with Automatic Privacy & Mobile-Web Resilience**: Requires at least 1 real photo (Camera or Gallery, up to 3 angles, with saved draft photo-anchor persistence) with pure-Dart pre-strip EXIF GPS/timestamp extraction (for anti-spoof verification) followed by complete JPEG **EXIF / GPS metadata stripping** (`APP1`, `APP2`, `APP13`, `COM` markers removed before storage or upload). Direct Web `FileReader` + `<canvas>` decoding ensures reliable gallery uploads on Android/iOS mobile browsers.
- **Online & Offline Khmer/English Voice Reporting**: Supports both Hold-to-Speak and Tap-to-Toggle voice reporting with a 1-tap `ខ្មែរ / EN` switcher, live sound-level waveform, real offline local voice memo recording & inline playback across Step 2, Submitted Confirmation, Tracking (top card & per-comment), Map sheet, and Staff Console (`MediaRecorder` on Web, `package:record` on Native), auto-finalizing active recordings on navigation, automatic Brave/browser fallback, and backend-ready transcription.
- **5-Layer Anti-Spoof, 250 m Photo-Anchored Fence & Smart Distance Gate**: Combines OS mock-location blocking, impossible-travel velocity detection (`> 250 km/h` / teleport guard), synthetic GPS accuracy heuristics, pre-strip photo EXIF & live camera capture anchoring (hard-blocking pins dragged `> 250 m` from where the photo was taken with a visual 250 m ring and 1-tap **Snap to photo location**), **dual Master Incident duplicate detection** checking both the dragged pin and the photo's capture spot, soft IP-vs-GPS country checks, transparent **municipal review tagging** for gallery photos lacking EXIF GPS, and a Step 3 **15 km Smart Distance Gate** blocking cross-province pins unless inside the citizen's saved Home District.
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
- **Multi-Citizen Comment Threads & Inline Translation**: Joining a Master Incident preserves every reporter's written comment and extra photos, and citizens can add, delete, or **translate comments inline (`Khmer ↔ English`)** directly on the **Tracking** screen. Notes use privacy-first labels (`Original reporter`, `Citizen #N`, `You`, `Anonymous`), reconcile silent confirmations honestly (`N other citizen(s) confirmed without commenting`), fall back to `No comment` when empty, and surface compact `+N more` pills across the Map sheet, My Reports, and Area News.
- **Priority Score Breakdown & P5 → P1 Threshold Table**: Combines Road Traffic (`40%`), Danger Level (`30%`), and Affected Citizens (`30%`) into an interactive donut chart, factor bars, and a highlighted **P5 (`4.5 – 5.0`) → P1 (`1.0 – 1.4`)** target-fix threshold table.

### 4. Distance-Aware `"Affects me"` Voting & Anti-Abuse Guardrails
- **`≤ 500 m`** → **Verified nearby (`ផ្ទៀងផ្ទាត់ជិតទីតាំង`)**
- **`500 m – 15 km`** → **City commuter (`អ្នកដំណើរក្នុងតំបន់`)**
- **`> 15 km` or GPS off** → Allowed only inside the citizen's saved **Home District (`អ្នករស់នៅក្នុងតំបន់`)** across all 25 provinces; otherwise blocked with exact distance feedback.
- **Hard Guardrails**: Mock/Fake GPS is always blocked (never bypassed by Home District), and voting is rate-limited to **10 votes per 24 hours** (automatically refunded on **Undo Support**).

### 5. 4-Stage Accountability Tracking & Nationwide Area News
- **Live Timeline**: `Submitted` → `Scheduled` → `Crew On-Site` → `Resolved` with a **Before / After draggable comparison slider**, pinch-to-zoom lightbox, 5-emoji satisfaction rating, and a **15-minute Quick Edit / Withdraw** grace period for newly submitted reports.
- **3-Level Nationwide Area News & GIS Routing**: Browse reports across **25 Capital & Provinces → Khan / Krong / Srok → Sangkat / Khum** (or **All Cambodia**), with automatic routing to **MPWT**, **Phnom Penh Capital Hall**, **Provincial DPWT**, **EDC Branches**, and **Municipal / District Administrations**.
- **Offline-First Reopen Auto-Sync & Installable Mobile PWA**: Queues reports and voice memos created offline with a global sync status banner and automatically syncs queued items both on live reconnect and on cold reopen when back online; persists locally as JSON on mobile and `window.localStorage` on Web; ships with a custom offline-first Service Worker ([sw.js](web/sw.js)) caching the app shell, local CanvasKit, bundled assets, Khmer/English fonts, and visited map tiles for full offline cold-launch, plus full **SrolanhCity** PWA branding (`manifest.json`, Mekong Teal theme color, adaptive maskable icons, and iOS Apple Touch icon).
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
The test suite includes **108 unit, widget, and WCAG 2.1 AA accessibility tests** covering Priority Score tiers, multi-citizen Master Incident comments & inline Khmer/English translation, self-duplicate & `"It's a different problem"` flows, Guest profile & resilient data-URI avatar uploads, Khmer/English online/offline voice memos, 5-layer anti-spoof, 250 m photo-anchored fence & dual Master Incident deduplication, Step 3 15 km Smart Distance Gate & unverified gallery review tagging, ODC/25-province GIS routing, stable zoom clustering & overview carousel visibility, distance-aware `"Affects me"` anti-abuse rules, offline reopen auto-sync, floating AI Assistant bubble & Help Center ticket lookup, PWA manifest & cache-first CDN map tile service worker, and automated Flutter accessibility guidelines.

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

---

## Roadmap & Venture Vision

- **MVP (Current Build)**: Bilingual Flutter mobile & web app, fast cache-first 25-province OpenStreetMap interactive map, pure-Dart EXIF stripping, dual-point spatial deduplication, `P1–P5` priority scoring, 250 m photo-anchored fence, Smart Distance Gate & 5-layer anti-spoof, floating AI Assistant bubble, and 108 automated tests.
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
