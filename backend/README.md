# SrolanhCity Backend (Step 1 Core Skeleton)

Modular FastAPI + PostGIS + Redis + S3/R2 backend shared by:
- **Citizen Client**: SrolanhCity Flutter Mobile (Android/iOS) & Web PWA (`https://songvansak19.github.io/SrolanhCity/`)
- **Authority Platform**: Ministry / Provincial Department / Municipal Monitoring & Dispatch Console (MPWT, PPCH, DPWT, EDC)

## Stack (Option A)
- **Runtime**: Python 3.13 + FastAPI + Uvicorn
- **Validation**: Pydantic v2 + `pydantic-settings`
- **Database**: SQLAlchemy 2.0 (async) + PostgreSQL 16 / PostGIS 3.4 + GeoAlchemy2 + Alembic
- **Cache / Rate Limit**: Redis 7
- **Media Storage**: MinIO (local dev) / Cloudflare R2 (production S3-compatible)
- **Auth & AI**: PyJWT + server-side Gemini AI proxy (`google-genai`)

## Quick Start (Local Tooling via `uv`)
```bash
cd backend
/usr/bin/uv venv --python 3.13 .venv
/usr/bin/uv pip install --python .venv/bin/python -e ".[dev]"
cp .env.example .env

# Run offline tests & lint (zero running containers required)
.venv/bin/ruff check app tests
.venv/bin/pytest -v

# Start local API server
.venv/bin/uvicorn app.main:app --reload --port 8000
```

## Docker Compose Stack
```bash
cd backend
docker compose config -q
docker compose up -d
```

## API Surface
- Readiness: `GET /health`, `GET /api/v1/health`
- AI Proxy: `POST /api/v1/ai/{classify-issue,transcribe-voice,help-chat,translate}`
- Citizen Auth: `POST /api/v1/auth/{guest,phone/request-otp,phone/verify}`, `GET /api/v1/auth/me`
- Citizen Reports: `GET/POST /api/v1/reports`, `GET/PATCH/DELETE /api/v1/reports/{report_id}`
- Support & Comments: `POST/DELETE /api/v1/reports/{report_id}/support`, `GET/POST /api/v1/reports/{report_id}/comments`, `DELETE /api/v1/reports/{report_id}/comments/{comment_id}`
- Alerts: `GET/DELETE /api/v1/alerts`, `POST /api/v1/alerts/{alert_id}/read`, `POST /api/v1/alerts/read-all`, `DELETE /api/v1/alerts/{alert_id}`, `POST /api/v1/alerts/restore`
- Authority Console: `GET /api/v1/authority/queue`, `POST /api/v1/authority/reports/{report_id}/{dispatch,resolve}`, `GET /api/v1/authority/analytics/{kpis,heatmap}`

See [`ARCHITECTURE.md`](./ARCHITECTURE.md) for the contract-first specification.
