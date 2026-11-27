from __future__ import annotations

import base64
import json
from types import SimpleNamespace
from urllib.parse import quote

import httpx
import pytest
import sqlalchemy as sa
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.api.v1.ai import get_ai_proxy_service
from app.api.v1.citizen.reports import get_report_create_limiter
from app.config import Settings
from app.core.auth import UserRole, create_access_token
from app.db.models.agency import Agency, Province
from app.db.models.alert import Alert
from app.db.models.audit import AuditLog
from app.db.session import OfflineStubSession
from app.schemas.ai import (
    ClassifyIssueRequest,
    HelpChatRequest,
    TranscribeVoiceRequest,
    TranslateRequest,
)
from app.services.ai_proxy import (
    AiInvalidInputError,
    AiPayloadTooLargeError,
    AiProxyService,
    AiUpstreamResponseError,
    SlidingWindowRateLimiter,
)
from app.services.notifications import NotificationService


def test_health_probes_and_cors_offline(stub_client: TestClient) -> None:
    """Verify `/health` and `/api/v1/health` respond cleanly offline plus CORS headers."""
    for path in ("/health", "/api/v1/health"):
        resp = stub_client.get(
            path,
            headers={"Origin": "https://songvansak19.github.io"},
        )
        assert resp.status_code == 200
        body = resp.json()
        assert body["status"] == "ok"
        assert "database" in body["checks"]
        assert resp.headers.get("access-control-allow-origin") == "https://songvansak19.github.io"


def test_openapi_routes_registered(stub_app: FastAPI) -> None:
    """Verify all expected citizen, AI, and authority v1 routes are mounted."""
    paths = set(stub_app.openapi()["paths"].keys())
    expected_paths = {
        "/health",
        "/api/v1/health",
        "/api/v1/ai/classify-issue",
        "/api/v1/ai/transcribe-voice",
        "/api/v1/ai/help-chat",
        "/api/v1/ai/translate",
        "/api/v1/auth/guest",
        "/api/v1/auth/phone/request-otp",
        "/api/v1/auth/phone/verify",
        "/api/v1/auth/me",
        "/api/v1/reports",
        "/api/v1/reports/{report_id}",
        "/api/v1/reports/{report_id}/rating",
        "/api/v1/reports/{report_id}/support",
        "/api/v1/reports/{report_id}/comments",
        "/api/v1/reports/{report_id}/comments/{comment_id}",
        "/api/v1/alerts",
        "/api/v1/alerts/{alert_id}/read",
        "/api/v1/alerts/read-all",
        "/api/v1/alerts/{alert_id}",
        "/api/v1/alerts/restore",
        "/api/v1/authority/queue",
        "/api/v1/authority/reports/{report_id}/dispatch",
        "/api/v1/authority/reports/{report_id}/resolve",
        "/api/v1/authority/analytics/kpis",
        "/api/v1/authority/analytics/heatmap",
    }
    missing = expected_paths - paths
    assert not missing, f"Missing expected API routes: {missing}"


def test_ai_endpoints_unconfigured_and_rate_limited(stub_client: TestClient) -> None:
    """Verify AI proxy returns 503 when GEMINI_API_KEY is unset and 429 on rate limit."""
    sample_b64 = base64.b64encode(b"fake-image-bytes").decode("ascii")
    resp = stub_client.post(
        "/api/v1/ai/classify-issue",
        json={
            "image_base64": sample_b64,
            "mime_type": "image/jpeg",
            "language": "km",
        },
    )
    assert resp.status_code == 503

    limiter = SlidingWindowRateLimiter(max_requests=2, window_seconds=60)
    proxy = AiProxyService(rate_limiter=limiter)
    limiter.check_and_record("client-1", now=100.0)
    limiter.check_and_record("client-1", now=101.0)
    with pytest.raises(Exception) as exc_info:
        proxy.rate_limiter.check_and_record("client-1", now=102.0)
    assert "rate limit" in str(exc_info.value).lower()


@pytest.mark.asyncio
async def test_sqlite_seeds_25_provinces_and_default_agencies(
    sqlite_session_factory: async_sessionmaker[AsyncSession],
) -> None:
    """Verify all 25 official Cambodia provinces and default agencies seed offline."""
    async with sqlite_session_factory() as session:
        provinces = list((await session.execute(sa.select(Province))).scalars().all())
        agencies = list((await session.execute(sa.select(Agency))).scalars().all())

    assert len(provinces) == 25
    province_codes = {p.code for p in provinces}
    assert {"phnom_penh", "siem_reap", "preah_sihanouk", "pailin", "tbong_khmum"} <= province_codes
    agency_codes = {a.code for a in agencies}
    assert {"MPWT", "PPCH", "DPWT", "EDC"} <= agency_codes


@pytest.mark.asyncio
async def test_end_to_end_citizen_and_authority_flow_offline(sqlite_app: FastAPI) -> None:
    """Exercise auth, report creation, viewport bbox, support, comments, and RBAC offline."""
    transport = httpx.ASGITransport(app=sqlite_app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Guest session
        guest_res = await client.post("/api/v1/auth/guest", json={})
        assert guest_res.status_code == 201
        guest_token = guest_res.json()["access_token"]
        guest_headers = {"Authorization": f"Bearer {guest_token}"}

        # 2. Outside Cambodia coordinates rejected
        bad_report = await client.post(
            "/api/v1/reports",
            headers=guest_headers,
            json={
                "category": "pothole",
                "lat": 37.422,
                "lng": -122.084,
                "road_class": "majorArtery",
                "severity": 4,
            },
        )
        assert bad_report.status_code == 422

        # 3. Create valid Phnom Penh majorArtery pothole report -> routed to MPWT
        create_res = await client.post(
            "/api/v1/reports",
            headers=guest_headers,
            json={
                "category": "pothole",
                "khmer_title": "រន្ធផ្លូវធំនៅមហាវិថីនរោត្តម",
                "english_title": "Deep pothole on Norodom Blvd",
                "description": "Dangerous pothole near intersection",
                "lat": 11.5564,
                "lng": 104.9282,
                "road_class": "majorArtery",
                "severity": 5,
            },
        )
        assert create_res.status_code == 201
        created = create_res.json()
        report_id = created["id"]
        encoded_id = quote(report_id, safe="")
        assert report_id.startswith("#SC-")
        assert "MPWT" in created["englishAgency"]
        assert created["priority"]["level"] == 4  # 0.4*5 + 0.3*5 + 0.3*1 = 3.8 -> P4

        # 4. Viewport query at single-pin zoom (14.0)
        map_res = await client.get(
            "/api/v1/reports",
            params={
                "min_lat": 11.4,
                "min_lng": 104.8,
                "max_lat": 11.7,
                "max_lng": 105.0,
                "zoom": 14.0,
            },
        )
        assert map_res.status_code == 200
        map_body = map_res.json()
        assert map_body["tier"] == "single"
        assert map_body["total_matching"] == 1

        # 5. Citizen comment with silent GPS verification tier
        cmt_res = await client.post(
            f"/api/v1/reports/{encoded_id}/comments",
            headers=guest_headers,
            json={
                "report_id": report_id,
                "text": "Confirmed on my morning commute.",
                "is_anonymous": False,
                "author_name": "Sokha",
                "verification_tier": "remoteDistrict",
                "remote_area": "Toul Kork",
            },
        )
        assert cmt_res.status_code == 201

        # 6. Support vote from a second user
        supporter_token = create_access_token(subject="citizen-2", role=UserRole.CITIZEN)
        sup_res = await client.post(
            f"/api/v1/reports/{encoded_id}/support",
            headers={"Authorization": f"Bearer {supporter_token}"},
            json={
                "report_id": report_id,
                "verification_tier": "verifiedNearby",
                "distance_meters": 45,
                "lat": 11.5566,
                "lng": 104.9283,
                "integrity": {
                    "risk_level": "trusted",
                    "reasons": [],
                    "photo_exif_verified": True,
                    "attestation": {"provider": "web_browser"},
                },
            },
        )
        assert sup_res.status_code == 200
        assert sup_res.json()["affected_citizens"] == 2
        assert sup_res.json()["priority"]["rawScore"] == 4.1  # 0.4*5 + 0.3*5 + 0.3*2

        # 7. Authority RBAC: guest/citizen forbidden, agency_staff allowed
        forbidden = await client.get("/api/v1/authority/queue", headers=guest_headers)
        assert forbidden.status_code == 403

        staff_token = create_access_token(
            subject="staff-mpwt-1",
            role=UserRole.AGENCY_STAFF,
            agency_code="MPWT",
        )
        staff_headers = {"Authorization": f"Bearer {staff_token}"}
        queue_res = await client.get("/api/v1/authority/queue", headers=staff_headers)
        assert queue_res.status_code == 200
        assert queue_res.json()["pending_count"] == 1

        dispatch_res = await client.post(
            f"/api/v1/authority/reports/{encoded_id}/dispatch",
            headers=staff_headers,
            json={"crew_code": "B-07"},
        )
        assert dispatch_res.status_code == 200
        assert dispatch_res.json()["status"] == "crewDispatched"

        resolve_res = await client.post(
            f"/api/v1/authority/reports/{encoded_id}/resolve",
            headers=staff_headers,
            json={"after_photo_object_key": "proofs/after-1.jpg"},
        )
        assert resolve_res.status_code == 200
        assert resolve_res.json()["status"] == "resolved"

        kpis_res = await client.get("/api/v1/authority/analytics/kpis", headers=staff_headers)
        assert kpis_res.status_code == 200
        assert kpis_res.json()["resolved_count"] == 1

        heatmap_res = await client.get(
            "/api/v1/authority/analytics/heatmap", headers=staff_headers
        )
        assert heatmap_res.status_code == 200
        assert heatmap_res.json()["type"] == "FeatureCollection"
        assert len(heatmap_res.json()["features"]) == 1


@pytest.mark.asyncio
async def test_auth_ownership_self_support_duplicates_and_rating_guards(
    sqlite_app: FastAPI,
) -> None:
    """Verify ownership checks, self-support rejection, 50m/150m duplicates, and rating guard."""
    transport = httpx.ASGITransport(app=sqlite_app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        user_a_res = await client.post("/api/v1/auth/guest", json={"english_name": "User A"})
        assert user_a_res.status_code == 201
        user_a_id = user_a_res.json()["user_id"]
        headers_a = {"Authorization": f"Bearer {user_a_res.json()['access_token']}"}

        user_b_res = await client.post("/api/v1/auth/guest", json={"english_name": "User B"})
        assert user_b_res.status_code == 201
        user_b_id = user_b_res.json()["user_id"]
        headers_b = {"Authorization": f"Bearer {user_b_res.json()['access_token']}"}

        # User A creates a report
        create_res = await client.post(
            "/api/v1/reports",
            headers=headers_a,
            json={
                "category": "pothole",
                "description": "Deep hole near school",
                "lat": 11.5564,
                "lng": 104.9282,
                "severity": 4,
            },
        )
        assert create_res.status_code == 201
        rid = create_res.json()["id"]
        enc_rid = quote(rid, safe="")

        # 50m self-duplicate guard blocks User A when force_create_new=False
        dup_50m = await client.post(
            "/api/v1/reports",
            headers=headers_a,
            json={
                "category": "pothole",
                "description": "Same spot",
                "lat": 11.5565,
                "lng": 104.9282,
                "severity": 4,
            },
        )
        assert dup_50m.status_code == 409

        # 150m nearby duplicate list surfaced for User B, and force_create_new=True allowed for A
        nearby_b = await client.post(
            "/api/v1/reports",
            headers=headers_b,
            json={
                "category": "pothole",
                "description": "Neighbor spot 90m away",
                "lat": 11.5572,
                "lng": 104.9282,
                "severity": 3,
            },
        )
        assert nearby_b.status_code == 201
        assert rid in nearby_b.json()["nearbyDuplicateIds"]

        forced_a = await client.post(
            "/api/v1/reports",
            headers=headers_a,
            json={
                "category": "pothole",
                "description": "Separate pothole forced",
                "lat": 11.5565,
                "lng": 104.9282,
                "severity": 3,
                "force_create_new": True,
            },
        )
        assert forced_a.status_code == 201

        # Unauthenticated and non-owner quick-edit / withdraw rejected (401 / 403)
        assert (
            await client.patch(
                f"/api/v1/reports/{enc_rid}",
                json={"description": "Anon hijack", "severity": 1},
            )
        ).status_code == 401
        assert (
            await client.patch(
                f"/api/v1/reports/{enc_rid}",
                headers=headers_b,
                json={"description": "User B hijack", "severity": 1},
            )
        ).status_code == 403
        assert (await client.delete(f"/api/v1/reports/{enc_rid}")).status_code == 401
        assert (
            await client.delete(f"/api/v1/reports/{enc_rid}", headers=headers_b)
        ).status_code == 403

        # Owner quick-edit succeeds
        own_patch = await client.patch(
            f"/api/v1/reports/{enc_rid}",
            headers=headers_a,
            json={"description": "Updated by A", "severity": 5},
        )
        assert own_patch.status_code == 200
        assert own_patch.json()["description"] == "Updated by A"

        # Creator self-support rejected with 409
        self_sup = await client.post(
            f"/api/v1/reports/{enc_rid}/support",
            headers=headers_a,
            json={"verification_tier": "verifiedNearby", "distance_meters": 5},
        )
        assert self_sup.status_code == 409

        # User B supports report -> GET detail reflects joined_by_current_user=True for User B
        sup_b = await client.post(
            f"/api/v1/reports/{enc_rid}/support",
            headers=headers_b,
            json={"verification_tier": "verifiedNearby", "distance_meters": 25},
        )
        assert sup_b.status_code == 200
        detail_b = await client.get(f"/api/v1/reports/{enc_rid}", headers=headers_b)
        assert detail_b.status_code == 200
        assert detail_b.json()["joinedByCurrentUser"] is True
        assert detail_b.json()["userSupportTier"] == "verifiedNearby"

        detail_a = await client.get(f"/api/v1/reports/{enc_rid}", headers=headers_a)
        assert detail_a.status_code == 200
        assert detail_a.json()["createdByCurrentUser"] is True
        assert detail_a.json()["joinedByCurrentUser"] is False

        # Comments: original reporter entry cannot be deleted; other user cannot delete B's comment
        orig_cmt = await client.post(
            f"/api/v1/reports/{enc_rid}/comments",
            headers=headers_a,
            json={"text": "Original reporter note"},
        )
        assert orig_cmt.status_code == 201
        orig_cid = orig_cmt.json()["id"]
        assert (
            await client.delete(
                f"/api/v1/reports/{enc_rid}/comments/{orig_cid}", headers=headers_a
            )
        ).status_code == 403

        b_cmt = await client.post(
            f"/api/v1/reports/{enc_rid}/comments",
            headers=headers_b,
            json={"text": "Supporter note"},
        )
        assert b_cmt.status_code == 201
        b_cid = b_cmt.json()["id"]
        assert (
            await client.delete(f"/api/v1/reports/{enc_rid}/comments/{b_cid}")
        ).status_code == 401
        assert (
            await client.delete(
                f"/api/v1/reports/{enc_rid}/comments/{b_cid}", headers=headers_a
            )
        ).status_code == 403
        assert (
            await client.delete(
                f"/api/v1/reports/{enc_rid}/comments/{b_cid}", headers=headers_b
            )
        ).status_code == 200

        # Rating unresolved report fails (401 unauth, 409 unresolved), succeeds once resolved
        assert (
            await client.post(f"/api/v1/reports/{enc_rid}/rating", json={"rating": 5})
        ).status_code == 401
        assert (
            await client.post(
                f"/api/v1/reports/{enc_rid}/rating", headers=headers_a, json={"rating": 5}
            )
        ).status_code == 409

        staff_tok = create_access_token(subject="st-1", role=UserRole.AGENCY_STAFF)
        staff_headers = {"Authorization": f"Bearer {staff_tok}"}
        assert (
            await client.post(
                f"/api/v1/authority/reports/{enc_rid}/resolve",
                headers=staff_headers,
                json={"after_photo_object_key": "proof.jpg"},
            )
        ).status_code == 200
        rated = await client.post(
            f"/api/v1/reports/{enc_rid}/rating", headers=headers_a, json={"rating": 5}
        )
        assert rated.status_code == 200
        assert rated.json()["citizenRating"] == 5

        # Unrelated User C cannot rate or overwrite User A's report rating (403)
        user_c_res = await client.post("/api/v1/auth/guest", json={"english_name": "User C"})
        assert user_c_res.status_code == 201
        headers_c = {"Authorization": f"Bearer {user_c_res.json()['access_token']}"}
        unrelated_rate = await client.post(
            f"/api/v1/reports/{enc_rid}/rating", headers=headers_c, json={"rating": 1}
        )
        assert unrelated_rate.status_code == 403

        # Supporter User B can still submit a rating, and rating remains untouched by User C
        supporter_rate = await client.post(
            f"/api/v1/reports/{enc_rid}/rating", headers=headers_b, json={"rating": 4}
        )
        assert supporter_rate.status_code == 200
        assert supporter_rate.json()["citizenRating"] == 4

        # Owner withdraw on forced_a (still submitted) succeeds
        forced_enc = quote(forced_a.json()["id"], safe="")
        assert (
            await client.delete(f"/api/v1/reports/{forced_enc}", headers=headers_a)
        ).status_code == 200
        assert user_a_id != user_b_id


@pytest.mark.asyncio
async def test_alerts_auth_scoping_and_cross_user_isolation(
    sqlite_app: FastAPI,
    sqlite_session_factory: async_sessionmaker[AsyncSession],
) -> None:
    """Verify `/alerts` requires auth, hides private alerts, and blocks cross-user mutations."""
    transport = httpx.ASGITransport(app=sqlite_app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        # Unauthenticated access rejected on every alerts endpoint
        assert (await client.get("/api/v1/alerts")).status_code == 401
        assert (await client.post("/api/v1/alerts/a-1/read")).status_code == 401
        assert (await client.post("/api/v1/alerts/read-all")).status_code == 401
        assert (await client.delete("/api/v1/alerts/a-1")).status_code == 401
        assert (
            await client.post("/api/v1/alerts/restore", json={"alert_ids": ["a-1"]})
        ).status_code == 401
        assert (await client.delete("/api/v1/alerts")).status_code == 401

        tok_a = create_access_token(subject="alert-user-a", role=UserRole.CITIZEN)
        tok_b = create_access_token(subject="alert-user-b", role=UserRole.CITIZEN)
        headers_a = {"Authorization": f"Bearer {tok_a}"}
        headers_b = {"Authorization": f"Bearer {tok_b}"}
        report_res = await client.post(
            "/api/v1/reports",
            headers=headers_a,
            json={"category": "drain", "lat": 11.5564, "lng": 104.9282},
        )
        rid = report_res.json()["id"]

        async with sqlite_session_factory() as session:
            session.add_all(
                [
                    Alert(
                        id="alert-a-priv",
                        user_id="alert-user-a",
                        report_id=rid,
                        khmer_title="A",
                        english_title="A private",
                    ),
                    Alert(
                        id="alert-b-priv",
                        user_id="alert-user-b",
                        report_id=rid,
                        khmer_title="B",
                        english_title="B private",
                    ),
                    Alert(
                        id="alert-broadcast",
                        user_id=None,
                        report_id=rid,
                        khmer_title="All",
                        english_title="Broadcast",
                    ),
                ]
            )
            await session.commit()

        list_a = await client.get("/api/v1/alerts", headers=headers_a)
        assert list_a.status_code == 200
        ids_a = {item["id"] for item in list_a.json()["items"]}
        assert ids_a == {"alert-a-priv"}
        assert list_a.json()["unread_count"] == 1

        # User B cannot read-mark, soft-delete, or restore User A's private alert
        assert (
            await client.post("/api/v1/alerts/alert-a-priv/read", headers=headers_b)
        ).status_code == 403
        assert (
            await client.delete("/api/v1/alerts/alert-a-priv", headers=headers_b)
        ).status_code == 403
        assert (
            await client.post("/api/v1/alerts/alert-broadcast/read", headers=headers_b)
        ).status_code == 403

        # User A soft-deletes & restores own alert; User B cannot restore User A's deleted alert
        del_a = await client.delete("/api/v1/alerts/alert-a-priv", headers=headers_a)
        assert del_a.status_code == 200
        restore_b = await client.post(
            "/api/v1/alerts/restore",
            headers=headers_b,
            json={"alert_ids": ["alert-a-priv"]},
        )
        assert restore_b.status_code == 200
        assert restore_b.json()["items"] == []

        restore_a = await client.post(
            "/api/v1/alerts/restore",
            headers=headers_a,
            json={"alert_ids": ["alert-a-priv"]},
        )
        assert restore_a.status_code == 200
        assert [i["id"] for i in restore_a.json()["items"]] == ["alert-a-priv"]

        # Bulk read-all and bulk clear leave zero unread / remaining alerts for User A
        read_all_a = await client.post("/api/v1/alerts/read-all", headers=headers_a)
        assert read_all_a.status_code == 200
        assert read_all_a.json()["marked_read"] == 1
        after_read_all = await client.get("/api/v1/alerts", headers=headers_a)
        assert after_read_all.status_code == 200
        assert after_read_all.json()["unread_count"] == 0

        clear_a = await client.delete("/api/v1/alerts?mode=all", headers=headers_a)
        assert clear_a.status_code == 200
        assert clear_a.json()["cleared_ids"] == ["alert-a-priv"]
        after_clear = await client.get("/api/v1/alerts", headers=headers_a)
        assert after_clear.status_code == 200
        assert after_clear.json()["items"] == []
        assert after_clear.json()["unread_count"] == 0

        # NotificationService fan-out builds per-user Alert rows with non-null user_id
        fanout_rows = NotificationService.build_alert_rows(
            report_id=rid,
            recipient_user_ids=["alert-user-a", "", "  ", "alert-user-a", "alert-user-b"],
            khmer_title="បានដោះស្រាយ",
            english_title="Resolved",
        )
        assert [r.user_id for r in fanout_rows] == ["alert-user-a", "alert-user-b"]
        assert all(r.user_id is not None for r in fanout_rows)


@pytest.mark.asyncio
async def test_repeat_phone_otp_verify_and_audit_json_escaping(
    sqlite_app: FastAPI,
    sqlite_session_factory: async_sessionmaker[AsyncSession],
) -> None:
    """Verify repeat phone login reuses existing user and AuditLog escapes JSON safely."""
    transport = httpx.ASGITransport(app=sqlite_app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        # Whitespace-only or too-short trimmed phone numbers fail validation with 422
        ws_phone = await client.post(
            "/api/v1/auth/phone/verify",
            json={"phone_number": "      ", "otp_code": "1234"},
        )
        assert ws_phone.status_code == 422
        short_trimmed = await client.post(
            "/api/v1/auth/phone/verify",
            json={"phone_number": "  12345  ", "otp_code": "1234"},
        )
        assert short_trimmed.status_code == 422

        first = await client.post(
            "/api/v1/auth/phone/verify",
            json={"phone_number": "+85512345678", "otp_code": "123456"},
        )
        assert first.status_code == 200
        second = await client.post(
            "/api/v1/auth/phone/verify",
            json={
                "phone_number": " +85512345678 ",
                "otp_code": "654321",
                "english_name": "Updated Citizen",
            },
        )
        assert second.status_code == 200
        assert second.json()["user_id"] == first.json()["user_id"]

        # Production app_env rejects stub OTP acceptance with 503
        import app.api.v1.citizen.auth as auth_mod
        from app.api.v1.citizen.auth import PhoneOtpVerifyRequest, verify_phone_otp

        prod_settings = Settings(app_env="production", offline_stub_db=True)
        orig_get_settings = auth_mod.get_settings
        auth_mod.get_settings = lambda: prod_settings
        try:
            with pytest.raises(Exception) as exc_info:
                await verify_phone_otp(
                    PhoneOtpVerifyRequest(phone_number="+85512345678", otp_code="123456"),
                    db=OfflineStubSession(),  # type: ignore[arg-type]
                )
            assert getattr(exc_info.value, "status_code", 0) == 503
        finally:
            auth_mod.get_settings = orig_get_settings

        # AuditLog JSON escaping with quotes/braces in crew_code and after_photo_object_key
        staff_tok = create_access_token(subject="st-json", role=UserRole.AGENCY_STAFF)
        staff_headers = {"Authorization": f"Bearer {staff_tok}"}
        rep = await client.post(
            "/api/v1/reports",
            headers=staff_headers,
            json={"category": "trash", "lat": 11.5564, "lng": 104.9282},
        )
        enc_rid = quote(rep.json()["id"], safe="")
        crew_payload = 'B-07","injected":1'
        proof_payload = 'proof.jpg","injected":true}'
        assert (
            await client.post(
                f"/api/v1/authority/reports/{enc_rid}/dispatch",
                headers=staff_headers,
                json={"crew_code": crew_payload},
            )
        ).status_code == 200
        assert (
            await client.post(
                f"/api/v1/authority/reports/{enc_rid}/resolve",
                headers=staff_headers,
                json={"after_photo_object_key": proof_payload},
            )
        ).status_code == 200

        async with sqlite_session_factory() as session:
            logs = list((await session.execute(sa.select(AuditLog))).scalars().all())
        assert len(logs) == 2
        parsed = {log.action: json.loads(log.details_json) for log in logs}
        assert parsed["dispatch_crew"] == {"crew_code": crew_payload}
        assert parsed["resolve_report"] == {"after_photo_object_key": proof_payload}


@pytest.mark.asyncio
async def test_offline_stub_session_create_report_and_methods(stub_client: TestClient) -> None:
    """Verify `OFFLINE_STUB_DB=true` report creation and stub `flush()`/`delete()`."""
    stub = OfflineStubSession()
    await stub.flush()
    await stub.delete(object())

    resp = stub_client.post(
        "/api/v1/reports",
        json={"category": "pothole", "lat": 11.5564, "lng": 104.9282},
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["afterDateLabel"] == ""
    assert body["fixedDurationKhmer"] == ""
    assert body["fixedDurationEnglish"] == ""


@pytest.mark.asyncio
async def test_ai_proxy_hardening_base64_json_and_rate_limiter_pruning(
    stub_client: TestClient,
) -> None:
    """Verify invalid base64, payload size cap, malformed Gemini JSON, and limiter pruning."""
    bad_b64 = stub_client.post(
        "/api/v1/ai/classify-issue",
        json={"image_base64": "!!!not-base64!!!", "mime_type": "image/jpeg", "language": "en"},
    )
    assert bad_b64.status_code == 400

    oversized_b64 = "A" * ((AiProxyService.MAX_IMAGE_BYTES * 4) // 3 + 64)
    too_big = stub_client.post(
        "/api/v1/ai/classify-issue",
        json={"image_base64": oversized_b64, "mime_type": "image/jpeg", "language": "en"},
    )
    assert too_big.status_code == 413

    # Direct unit tests for AiProxyService invalid base64, oversize, malformed JSON, and pruning
    proxy = AiProxyService(settings=Settings(gemini_api_key="fake-key", offline_stub_db=True))
    with pytest.raises(AiInvalidInputError):
        await proxy.classify_issue(
            ClassifyIssueRequest(image_base64="not*valid", mime_type="image/jpeg", language="en")
        )
    with pytest.raises(AiPayloadTooLargeError):
        await proxy.classify_issue(
            ClassifyIssueRequest(image_base64=oversized_b64, mime_type="image/jpeg", language="en")
        )

    async def _bad_json_generate(*_args: object, **_kwargs: object) -> SimpleNamespace:
        return SimpleNamespace(text="{not-valid-json")

    fake_client = SimpleNamespace(
        aio=SimpleNamespace(models=SimpleNamespace(generate_content=_bad_json_generate))
    )
    proxy._require_client = lambda: fake_client  # type: ignore[method-assign]
    with pytest.raises(AiUpstreamResponseError):
        await proxy.help_chat(HelpChatRequest(message="Hello", language="en"))

    # Limiter prunes expired buckets
    limiter = SlidingWindowRateLimiter(max_requests=2, window_seconds=10)
    limiter.check_and_record("stale-client", now=0.0)
    assert "stale-client" in limiter._hits
    limiter.check_and_record("active-client", now=25.0)
    assert "stale-client" not in limiter._hits


@pytest.mark.asyncio
async def test_ai_proxy_non_integer_and_invalid_model_fields_return_502(
    stub_app: FastAPI,
    stub_client: TestClient,
) -> None:
    """Verify upstream LLM field type variance maps to AiUpstreamResponseError / HTTP 502."""
    sample_img = base64.b64encode(b"fake-image").decode("ascii")
    sample_aud = base64.b64encode(b"fake-audio").decode("ascii")

    def _make_proxy(payload_text: str) -> AiProxyService:
        proxy = AiProxyService(settings=Settings(gemini_api_key="fake-key", offline_stub_db=True))

        async def _fake_generate(*_args: object, **_kwargs: object) -> SimpleNamespace:
            return SimpleNamespace(text=payload_text)

        fake_client = SimpleNamespace(
            aio=SimpleNamespace(models=SimpleNamespace(generate_content=_fake_generate))
        )
        proxy._require_client = lambda: fake_client  # type: ignore[method-assign]
        return proxy

    # HTTP route check: non-integer severity & confidence_percent return 502 instead of 500
    bad_classify_proxy = _make_proxy(
        '{"is_civic_issue": true, "category": "pothole", '
        '"severity": "high", "confidence_percent": "90%"}'
    )
    stub_app.dependency_overrides[get_ai_proxy_service] = lambda: bad_classify_proxy
    try:
        http_resp = stub_client.post(
            "/api/v1/ai/classify-issue",
            json={"image_base64": sample_img, "mime_type": "image/jpeg", "language": "en"},
        )
        assert http_resp.status_code == 502
    finally:
        stub_app.dependency_overrides.pop(get_ai_proxy_service, None)

    # Direct service checks for classify_issue, transcribe_voice, help_chat, and translate_text
    with pytest.raises(AiUpstreamResponseError):
        await _make_proxy('{"severity": null}').classify_issue(
            ClassifyIssueRequest(image_base64=sample_img, mime_type="image/jpeg", language="en")
        )
    with pytest.raises(AiUpstreamResponseError):
        await _make_proxy('{"khmer_summary": ["bad-list"]}').classify_issue(
            ClassifyIssueRequest(image_base64=sample_img, mime_type="image/jpeg", language="en")
        )
    with pytest.raises(AiUpstreamResponseError):
        await _make_proxy('{"transcript": "ok", "category": ["pothole"]}').transcribe_voice(
            TranscribeVoiceRequest(audio_base64=sample_aud, mime_type="audio/aac", language="en")
        )
    with pytest.raises(AiUpstreamResponseError):
        await _make_proxy('{"reply": "hi", "report_id": 12345}').help_chat(
            HelpChatRequest(message="Help", language="en")
        )
    with pytest.raises(AiUpstreamResponseError):
        await _make_proxy('{"translated_text": "hi", "source_lang": ["en"]}').translate_text(
            TranslateRequest(text="Hello", targetLang="km")
        )


@pytest.mark.asyncio
async def test_ai_proxy_wrong_type_json_fields_reject_coercion_with_502(
    stub_app: FastAPI,
    stub_client: TestClient,
) -> None:
    """Verify wrong-type LLM JSON fields are never silently coerced and return HTTP 502."""
    sample_img = base64.b64encode(b"fake-image").decode("ascii")
    sample_aud = base64.b64encode(b"fake-audio").decode("ascii")

    def _make_proxy(payload_text: str) -> AiProxyService:
        proxy = AiProxyService(settings=Settings(gemini_api_key="fake-key", offline_stub_db=True))

        async def _fake_generate(*_args: object, **_kwargs: object) -> SimpleNamespace:
            return SimpleNamespace(text=payload_text)

        fake_client = SimpleNamespace(
            aio=SimpleNamespace(models=SimpleNamespace(generate_content=_fake_generate))
        )
        proxy._require_client = lambda: fake_client  # type: ignore[method-assign]
        return proxy

    def _post_response_with_upstream(
        path: str, body: dict[str, object], upstream_json: str
    ) -> httpx.Response:
        proxy = _make_proxy(upstream_json)
        stub_app.dependency_overrides[get_ai_proxy_service] = lambda: proxy
        try:
            return stub_client.post(path, json=body)
        finally:
            stub_app.dependency_overrides.pop(get_ai_proxy_service, None)

    def _post_with_upstream(path: str, body: dict[str, object], upstream_json: str) -> int:
        return _post_response_with_upstream(path, body, upstream_json).status_code

    img_req = {"image_base64": sample_img, "mime_type": "image/jpeg", "language": "en"}
    aud_req = {"audio_base64": sample_aud, "mime_type": "audio/aac", "language": "en"}
    chat_req = {"message": "Help", "language": "en"}
    tr_req = {"text": "Hello", "targetLang": "km"}

    # 1. classify-issue rejects non-bool is_civic_issue, bad numbers, and non-string category
    for bad_classify_json in (
        '{"is_civic_issue": "false", "category": "pothole", '
        '"severity": 3, "confidence_percent": 80}',
        '{"is_civic_issue": "maybe", "category": "pothole", '
        '"severity": 3, "confidence_percent": 80}',
        '{"is_civic_issue": 123}',
        '{"is_civic_issue": [1, 2]}',
        '{"is_civic_issue": null}',
        '{"severity": true}',
        '{"confidence_percent": true}',
        '{"severity": 1e400}',
        '{"category": 99}',
        '{"category": true}',
        '{"category": 3.14}',
        '{"category": ["pothole"]}',
    ):
        assert _post_with_upstream("/api/v1/ai/classify-issue", img_req, bad_classify_json) == 502
        with pytest.raises(AiUpstreamResponseError):
            await _make_proxy(bad_classify_json).classify_issue(
                ClassifyIssueRequest(image_base64=sample_img, mime_type="image/jpeg", language="en")
            )

    # 2. transcribe-voice rejects non-string transcript and non-string category
    for bad_transcribe_json in (
        '{"transcript": 123}',
        '{"transcript": ["a"]}',
        '{"transcript": true}',
        '{"category": 99}',
        '{"category": true}',
        '{"category": 3.14}',
        '{"category": ["pothole"]}',
    ):
        assert (
            _post_with_upstream("/api/v1/ai/transcribe-voice", aud_req, bad_transcribe_json) == 502
        )
        with pytest.raises(AiUpstreamResponseError):
            await _make_proxy(bad_transcribe_json).transcribe_voice(
                TranscribeVoiceRequest(
                    audio_base64=sample_aud, mime_type="audio/aac", language="en"
                )
            )

    # 3. help-chat rejects non-string reply
    for bad_chat_json in ('{"reply": 123}', '{"reply": ["hi"]}', '{"reply": false}'):
        assert _post_with_upstream("/api/v1/ai/help-chat", chat_req, bad_chat_json) == 502
        with pytest.raises(AiUpstreamResponseError):
            await _make_proxy(bad_chat_json).help_chat(
                HelpChatRequest(message="Help", language="en")
            )

    # 4. translate rejects non-string translated_text and source_lang
    for bad_tr_json in (
        '{"translated_text": 123}',
        '{"translated_text": ["x"]}',
        '{"translated_text": "hello", "source_lang": 123}',
        '{"translated_text": "hello", "source_lang": true}',
    ):
        assert _post_with_upstream("/api/v1/ai/translate", tr_req, bad_tr_json) == 502
        with pytest.raises(AiUpstreamResponseError):
            await _make_proxy(bad_tr_json).translate_text(
                TranslateRequest(text="Hello", targetLang="km")
            )

    # 5. Legitimate null/omitted optional fields and unknown string category fall back with 200
    assert _post_with_upstream("/api/v1/ai/classify-issue", img_req, "{}") == 200
    assert (
        _post_with_upstream("/api/v1/ai/transcribe-voice", aud_req, '{"transcript": null}') == 200
    )
    assert _post_with_upstream("/api/v1/ai/help-chat", chat_req, '{"reply": null}') == 200
    assert (
        _post_with_upstream(
            "/api/v1/ai/translate", tr_req, '{"translated_text": null, "source_lang": null}'
        )
        == 200
    )
    for path, req_body in (
        ("/api/v1/ai/classify-issue", img_req),
        ("/api/v1/ai/transcribe-voice", aud_req),
    ):
        for valid_fallback_json in ('{"category": "unknown_cat"}', '{"category": null}'):
            resp = _post_response_with_upstream(path, req_body, valid_fallback_json)
            assert resp.status_code == 200
            assert resp.json()["category"] is None


@pytest.mark.asyncio
async def test_classify_issue_public_space_and_confidence_guard() -> None:
    """Reject non-public spaces and low-confidence detections even if Gemini flags an issue."""
    sample_img = base64.b64encode(b"fake-image").decode("ascii")
    req = ClassifyIssueRequest(image_base64=sample_img, mime_type="image/jpeg", language="en")

    def _make_proxy(raw_json: str) -> AiProxyService:
        proxy = AiProxyService(settings=Settings(gemini_api_key="fake-key", offline_stub_db=True))

        async def _fake_generate(*_args: object, **_kwargs: object) -> SimpleNamespace:
            return SimpleNamespace(text=raw_json)

        fake_client = SimpleNamespace(
            aio=SimpleNamespace(models=SimpleNamespace(generate_content=_fake_generate))
        )
        proxy._require_client = lambda: fake_client  # type: ignore[method-assign]
        return proxy

    # 1. Private backyard (is_public_space=False) is downgraded to non-civic
    backyard_res = await _make_proxy(
        '{"is_civic_issue": true, "is_public_space": false, "category": "trash", '
        '"confidence_percent": 90, "severity": 3}'
    ).classify_issue(req)
    assert backyard_res.is_civic_issue is False
    assert backyard_res.category is None
    assert backyard_res.english_reason

    # 2. Low confidence (< 75) is downgraded to non-civic
    low_conf_res = await _make_proxy(
        '{"is_civic_issue": true, "is_public_space": true, "category": "trash", '
        '"confidence_percent": 65, "severity": 3}'
    ).classify_issue(req)
    assert low_conf_res.is_civic_issue is False
    assert low_conf_res.category is None
    assert low_conf_res.khmer_reason

    # 3. High-confidence public civic issue passes both gates
    valid_res = await _make_proxy(
        '{"is_civic_issue": true, "is_public_space": true, "category": "pothole", '
        '"confidence_percent": 88, "severity": 5, '
        '"english_summary": "Deep pothole", "khmer_summary": "រណ្តៅផ្លូវជ្រៅ"}'
    ).classify_issue(req)
    assert valid_res.is_civic_issue is True
    assert valid_res.category is not None
    assert valid_res.category.value == "pothole"
    assert valid_res.confidence_percent == 88


@pytest.mark.asyncio
async def test_translate_text_rejects_thai_script_for_khmer_target() -> None:
    """Reject Thai script when translating to Khmer so client falls back cleanly."""
    req = TranslateRequest(
        text="Drain grate is packed with plastic bags; water stays stagnant for hours.",
        targetLang="km",
    )

    def _make_proxy(raw_json: str) -> AiProxyService:
        proxy = AiProxyService(settings=Settings(gemini_api_key="fake-key", offline_stub_db=True))

        async def _fake_generate(*_args: object, **_kwargs: object) -> SimpleNamespace:
            return SimpleNamespace(text=raw_json)

        fake_client = SimpleNamespace(
            aio=SimpleNamespace(models=SimpleNamespace(generate_content=_fake_generate))
        )
        proxy._require_client = lambda: fake_client  # type: ignore[method-assign]
        return proxy

    with pytest.raises(AiUpstreamResponseError):
        await _make_proxy(
            '{"translated_text": "ตะแกรงระบายน้ำอัดแน่นไปด้วยถุงพลาสติก", "source_lang": "en"}'
        ).translate_text(req)

    ok_res = await _make_proxy(
        '{"translated_text": "គម្របលូត្រូវបានស្ទះដោយថង់ប្លាស្ទិក", "source_lang": "en"}'
    ).translate_text(req)
    assert ok_res.translated_text == "គម្របលូត្រូវបានស្ទះដោយថង់ប្លាស្ទិក"
    assert ok_res.target_lang == "km"


def test_create_report_enforces_photo_hmac_duplicate_and_rate_limits(
    sqlite_app: FastAPI,
) -> None:
    """Verify photo requirement, magic bytes, HMAC token, duplicate check, and rate limit."""
    valid_jpeg = b"\xff\xd8\xff\xe0" + (b"\x11" * 1200) + b"\xff\xd9"
    alt_jpeg = b"\xff\xd8\xff\xe0" + (b"\x22" * 1200) + b"\xff\xd9"
    valid_b64 = base64.b64encode(valid_jpeg).decode("ascii")
    alt_b64 = base64.b64encode(alt_jpeg).decode("ascii")

    gemini_calls = 0
    next_ai_response = (
        '{"is_civic_issue": true, "is_public_space": true, "category": "pothole", '
        '"confidence_percent": 92, "severity": 3}'
    )

    proxy = AiProxyService(
        settings=Settings(
            gemini_api_key="fake-key",
            jwt_secret_key="test-secret-key",
            offline_stub_db=False,
        )
    )

    async def _fake_generate(*_args: object, **_kwargs: object) -> SimpleNamespace:
        nonlocal gemini_calls
        gemini_calls += 1
        return SimpleNamespace(text=next_ai_response)

    fake_client = SimpleNamespace(
        aio=SimpleNamespace(models=SimpleNamespace(generate_content=_fake_generate))
    )
    proxy._require_client = lambda: fake_client  # type: ignore[method-assign]

    limiter = SlidingWindowRateLimiter(max_requests=5, window_seconds=3600)
    sqlite_app.dependency_overrides[get_ai_proxy_service] = lambda: proxy
    sqlite_app.dependency_overrides[get_report_create_limiter] = lambda: limiter

    base_payload = {
        "category": "pothole",
        "description": "Deep pothole",
        "lat": 11.5564,
        "lng": 104.9282,
        "severity": 3,
        "is_anonymous": False,
    }

    try:
        with TestClient(sqlite_app) as client:
            # 1. Missing photo -> 422 photo_required
            r_missing = client.post("/api/v1/reports", json=base_payload)
            assert r_missing.status_code == 422
            assert r_missing.json()["detail"]["code"] == "photo_required"

            # 2. Invalid binary / tiny payload -> 400
            r_tiny = client.post(
                "/api/v1/reports",
                json={
                    **base_payload,
                    "photo_base64": base64.b64encode(b"not-an-image").decode("ascii"),
                },
            )
            assert r_tiny.status_code == 400

            # 3. Classify legit photo -> receives HMAC photo_verification_token
            r_cls = client.post(
                "/api/v1/ai/classify-issue",
                json={"image_base64": valid_b64, "mime_type": "image/jpeg", "language": "en"},
            )
            assert r_cls.status_code == 200
            token = r_cls.json()["photo_verification_token"]
            assert isinstance(token, str) and len(token) > 20
            assert gemini_calls == 1

            # 4. Create report with valid HMAC token -> 201 with ZERO second Gemini call
            r_ok = client.post(
                "/api/v1/reports",
                json={
                    **base_payload,
                    "photo_base64": valid_b64,
                    "photo_verification_token": token,
                },
            )
            assert r_ok.status_code == 201
            assert gemini_calls == 1

            # 5. Re-submitting exact same photo on open report -> 409 duplicate_photo
            r_dup = client.post(
                "/api/v1/reports",
                json={
                    **base_payload,
                    "lat": 11.5664,
                    "photo_base64": valid_b64,
                    "photo_verification_token": token,
                },
            )
            assert r_dup.status_code == 409
            assert r_dup.json()["detail"]["code"] == "duplicate_photo"

            # 6. Tampered photo reusing valid token -> falls back to Gemini & rejects 422
            next_ai_response = (
                '{"is_civic_issue": false, "is_public_space": false, "category": null, '
                '"confidence_percent": 95, "severity": 2, '
                '"english_reason": "Private backyard"}'
            )
            r_tampered = client.post(
                "/api/v1/reports",
                json={
                    **base_payload,
                    "lat": 11.5764,
                    "photo_base64": alt_b64,
                    "photo_verification_token": token,
                },
            )
            assert r_tampered.status_code == 422
            assert r_tampered.json()["detail"]["code"] == "not_civic_issue"
            assert gemini_calls == 2

            # 7. Exceeding creation rate limit (5 requests used above) -> 429 rate_limited
            r_rate = client.post("/api/v1/reports", json=base_payload)
            assert r_rate.status_code == 429
            assert r_rate.json()["detail"]["code"] == "rate_limited"
    finally:
        sqlite_app.dependency_overrides.pop(get_ai_proxy_service, None)
        sqlite_app.dependency_overrides.pop(get_report_create_limiter, None)


def test_ai_proxy_fallback_model_and_429_quota_handling(stub_app: FastAPI) -> None:
    """Fallback to secondary models on 429 quota errors, and return 429 when all models exhaust."""
    sample_img = base64.b64encode(b"fake-image").decode("ascii")
    req_body = {"image_base64": sample_img, "mime_type": "image/jpeg", "language": "en"}
    called_models: list[str] = []
    fail_all = False

    proxy = AiProxyService(
        settings=Settings(
            gemini_api_key="fake-key",
            gemini_model="gemini-primary",
            gemini_fallback_models="gemini-fallback-1, gemini-fallback-2",
            offline_stub_db=True,
        )
    )

    async def _fake_generate(*, model: str, **_kwargs: object) -> SimpleNamespace:
        called_models.append(model)
        if fail_all or model == "gemini-primary":
            raise RuntimeError("429 RESOURCE_EXHAUSTED: quota exceeded")
        return SimpleNamespace(
            text=(
                '{"is_civic_issue": true, "is_public_space": true, '
                '"category": "pothole", "confidence_percent": 90, "severity": 3}'
            )
        )

    fake_client = SimpleNamespace(
        aio=SimpleNamespace(models=SimpleNamespace(generate_content=_fake_generate))
    )
    proxy._require_client = lambda: fake_client  # type: ignore[method-assign]
    stub_app.dependency_overrides[get_ai_proxy_service] = lambda: proxy

    try:
        with TestClient(stub_app) as client:
            # 1. Primary 429 -> seamlessly falls back to gemini-fallback-1 -> 200 OK
            ok_resp = client.post("/api/v1/ai/classify-issue", json=req_body)
            assert ok_resp.status_code == 200
            assert ok_resp.json()["is_civic_issue"] is True
            assert called_models == ["gemini-primary", "gemini-fallback-1"]

            # 2. All models 429 -> clean HTTP 429 instead of 502
            called_models.clear()
            fail_all = True
            exhausted_resp = client.post("/api/v1/ai/classify-issue", json=req_body)
            assert exhausted_resp.status_code == 429
            assert called_models == [
                "gemini-primary",
                "gemini-fallback-1",
                "gemini-fallback-2",
            ]
    finally:
        stub_app.dependency_overrides.pop(get_ai_proxy_service, None)
