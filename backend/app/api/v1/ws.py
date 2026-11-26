from __future__ import annotations

import logging

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

logger = logging.getLogger(__name__)

router = APIRouter(tags=["realtime"])


class ReportConnectionManager:
    """Tracks active WebSocket clients and broadcasts report-feed updates."""

    def __init__(self) -> None:
        self._connections: set[WebSocket] = set()

    async def connect(self, websocket: WebSocket) -> None:
        await websocket.accept()
        self._connections.add(websocket)

    def disconnect(self, websocket: WebSocket) -> None:
        self._connections.discard(websocket)

    async def broadcast_reports_updated(self, event: str = "reports_updated") -> None:
        stale: list[WebSocket] = []
        payload = {"type": event}
        for conn in list(self._connections):
            try:
                await conn.send_json(payload)
            except Exception:
                stale.append(conn)
        for conn in stale:
            self._connections.discard(conn)


report_ws_manager = ReportConnectionManager()


@router.websocket("/ws/reports")
async def reports_websocket(websocket: WebSocket) -> None:
    await report_ws_manager.connect(websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        report_ws_manager.disconnect(websocket)
    except Exception:
        logger.debug("WebSocket closed unexpectedly", exc_info=True)
        report_ws_manager.disconnect(websocket)
