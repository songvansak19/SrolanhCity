# SrolanhCity Backend — Contract-First Architecture Specification

This document defines the architectural boundaries, domain invariants, and Flutter `lib/` contract parity rules for developers and `/teamwork` agents extending `backend/`.

---

## 1. Platform Boundary & Shared Modular Monolith

A single FastAPI codebase (`app/`) serves both clients cleanly via explicit API route groups:
- **`/api/v1/ai/*`** — Server-side Gemini proxy (`classify-issue`, `transcribe-voice`, `help-chat`, `translate`), keeping `GEMINI_API_KEY` off client binaries and enforcing sliding-window rate limits (`429` on excess).
- **`/api/v1/*` (`citizen/`)** — Citizen Mobile & Web PWA endpoints (guest/phone auth, viewport-clustered map pins, report creation with 150m clustering & 50m self-guard, 15-min quick-edit/withdraw, "Affects me" remote support with 24h caps, comments, alerts).
- **`/api/v1/authority/*` (`authority/`)** — Ministry/Department monitoring console (priority-sorted incident queue, crew dispatch, before/after proof resolution, MTTR & SLA breach analytics, GeoJSON heatmaps).

---

## 2. Flutter `lib/` Parity Contracts

### 2.1 Case Convention
- Explicit REST API payload builders in Flutter (`BackendCivicAiService`, `buildMapViewportQuery`, `buildCommentApiPayload`, `buildSupportApiPayload`, `buildIntegrityApiPayload`) transmit **snake_case** keys (`image_base64`, `verification_tier`, `remote_area`, `author_name`, `min_lat`).
- Local Flutter persistence models (`CivicReport.toJson`, `CitizenComment.toJson`, `AlertItem.toJson`, `TimelineEntry.toJson`) serialize in **camelCase**.
- Pydantic v2 schemas in `app/schemas/` define canonical `snake_case` attributes and configure `ConfigDict(populate_by_name=True)` with `camelCase` aliases where appropriate so both conventions validate seamlessly.

### 2.2 Priority Formula (`app/core/priority.py` ↔ `lib/domain/services/priority_calculator.dart`)
- Formula: `raw = (0.4 * clamped_traffic) + (0.3 * clamped_severity) + (0.3 * count_score)`
  - `clamped_traffic = clamp(traffic_score, 1, 5)` (`RoadClass`: `alley=1`, `residential=2`, `secondary=3`, `commercial=4`, `majorArtery=5`)
  - `clamped_severity = clamp(severity_score, 1, 5)`
  - `score_report_count(count)`: `<=1 -> 1`, `<=3 -> 2`, `<=7 -> 3`, `<=14 -> 4`, `>=15 -> 5`
- **Half-away-from-zero rounding**: `level = clamp(Decimal(str(raw)).quantize(Decimal("1"), rounding=ROUND_HALF_UP), 1, 5)` so `.5` boundaries (`2.5 -> P3`, `3.5 -> P4`, `4.5 -> P5`) match Dart's `double.round()` identically (never Python's banker's rounding).
- **P5 -> P1 SLA Tiers**:
  - `P5` (`4.5 – 5.0`): Critical (`បន្ទាន់បំផុត`) / `Within 24h` (`24`h)
  - `P4` (`3.5 – 4.4`): High (`អាទិភាពខ្ពស់`) / `2–3 days` (`72`h)
  - `P3` (`2.5 – 3.4`): Medium (`អាទិភាពមធ្យម`) / `Weekly` (`168`h)
  - `P2` (`1.5 – 2.4`): Low (`អាទិភាពទាប`) / `Batched` (`336`h)
  - `P1` (`1.0 – 1.4`): Minor (`កម្រិតស្រាល`) / `Seasonal` (`720`h)

### 2.3 Privacy & EXIF Stripping (`app/core/exif.py` ↔ `lib/data/services/exif_stripper.dart`)
- Server-side defense-in-depth pure-Python JPEG byte segment stripper drops `APP1` (`0xE1`: EXIF/GPS/XMP), `APP2` (`0xE2`: ICC/extended EXIF), `APP13` (`0xED`: IPTC), and `COM` (`0xFE`) while keeping `SOI` (`0xFFD8`), `APP0`, `DQT`, `DHT`, `SOF`, `DRI`, `SOS` (`0xFFDA` + entropy stream verbatim), and `EOI` (`0xFFD9`). Non-JPEG/malformed buffers are returned untouched.

### 2.4 Geospatial, Anti-Spoof & Support Rules (`app/core/integrity.py`, `app/services/spatial.py`)
- Cambodia strict coordinate bounds: `9.9 <= lat <= 14.7` and `102.3 <= lng <= 107.7`.
- Nearby duplicate clustering radius: `150.0 m`; hard self-duplicate block radius: `50.0 m`.
- Map viewport zoom tiers: `< 10.2` (`province`), `10.2 <= zoom < 13.4` (`area`), `>= 13.4` (`single`).
- Support 24h quotas: `10` total supports / 24h, `3` cross-province (`remoteProvince`) supports / 24h; `support_reason_note` requires `>= 10` characters when `verification_tier == "remoteProvince"` or `support_reason_category == "other"`.

### 2.5 GIS Agency Routing & 25 Provinces (`app/services/routing.py`, `app/db/seeds/__init__.py`)
- Exact 25 Cambodia province slugs matching `lib/domain/models/cambodia_locations.dart`.
- Agency assignment: `MPWT` (`1190`) for major artery potholes nationwide; `PPCH` (`Phnom Penh Capital Hall` / `Dept. of Public Works & Drainage`) in Phnom Penh; `DPWT` in the 24 provinces; `EDC` (`1298`) for streetlights nationwide; Khan/Municipal Waste Management for trash.

---

## 3. Offline Testability & Database Portability
- `app/db/base.py` defines geospatial `POINT` columns using `sa.Text().with_variant(Geometry("POINT", srid=4326), "postgresql")`.
- PostgreSQL 16/PostGIS 3.4 gets native `GEOMETRY(POINT, 4326)` columns and `ST_DWithin` queries, while offline `pytest` runs cleanly against `sqlite+aiosqlite:///:memory:` or an `OfflineStubSession` without running containers.
- `app/db/session.py` creates engines lazily so importing `app.main` never attempts a network socket connection.
