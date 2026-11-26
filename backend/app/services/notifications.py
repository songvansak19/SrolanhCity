from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from uuid import uuid4

from app.db.models.alert import Alert
from app.schemas.alert import AlertItemOut


@dataclass(frozen=True, slots=True)
class PushDispatchResult:
    """Result of fanning out an alert to FCM / Web Push subscribers."""

    alert_count: int
    fcm_dispatched: int
    web_push_dispatched: int


class NotificationService:
    """Reporter + supporter fan-out alert builder & FCM/Web Push hook."""

    @staticmethod
    def build_alert_item(
        *,
        report_id: str,
        khmer_title: str,
        english_title: str,
        khmer_subtitle: str = "",
        english_subtitle: str = "",
        prefix: str = "alert",
    ) -> AlertItemOut:
        return AlertItemOut(
            id=f"{prefix}-{uuid4().hex[:12]}",
            report_id=report_id,
            khmer_title=khmer_title,
            english_title=english_title,
            khmer_subtitle=khmer_subtitle,
            english_subtitle=english_subtitle,
            created_at=datetime.now(UTC),
            is_read=False,
        )

    @classmethod
    def build_alert_rows(
        cls,
        *,
        report_id: str,
        recipient_user_ids: list[str],
        khmer_title: str,
        english_title: str,
        khmer_subtitle: str = "",
        english_subtitle: str = "",
        prefix: str = "alert",
    ) -> list[Alert]:
        """Build per-user `Alert` ORM rows with guaranteed non-null `user_id`."""
        unique_ids = list(
            dict.fromkeys(uid.strip() for uid in recipient_user_ids if uid and uid.strip())
        )
        now = datetime.now(UTC)
        return [
            Alert(
                id=f"{prefix}-{uuid4().hex[:12]}",
                user_id=uid,
                report_id=report_id,
                khmer_title=khmer_title,
                english_title=english_title,
                khmer_subtitle=khmer_subtitle,
                english_subtitle=english_subtitle,
                is_read=False,
                is_deleted=False,
                created_at=now,
                updated_at=now,
            )
            for uid in unique_ids
        ]

    @classmethod
    async def fanout_status_update(
        cls,
        *,
        report_id: str,
        recipient_user_ids: list[str],
        khmer_title: str,
        english_title: str,
        khmer_subtitle: str = "",
        english_subtitle: str = "",
    ) -> tuple[list[AlertItemOut], PushDispatchResult]:
        """Create per-recipient alerts and dispatch push notifications (hook)."""
        unique_ids = list(
            dict.fromkeys(uid.strip() for uid in recipient_user_ids if uid and uid.strip())
        )
        alerts = [
            cls.build_alert_item(
                report_id=report_id,
                khmer_title=khmer_title,
                english_title=english_title,
                khmer_subtitle=khmer_subtitle,
                english_subtitle=english_subtitle,
            )
            for _ in unique_ids
        ]
        # Step 1 hook: FCM / Web Push provider integration connects here in Step 2.
        dispatch = PushDispatchResult(
            alert_count=len(alerts),
            fcm_dispatched=0,
            web_push_dispatched=0,
        )
        return alerts, dispatch
