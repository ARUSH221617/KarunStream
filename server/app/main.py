from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
import hmac

from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.db.engine import init_db, close_db
from app.api.routes import router
from app.core.config import get_settings
from app.core.logging import configure_logging
from app.core.security import is_lan_ip
from app.models import PeerRegistration
from app.services.discovery import MdnsAdvertiser
from app.services.sockets import receive_orchestrator_messages, registry

settings = get_settings()
configure_logging(settings)
mdns_advertiser = MdnsAdvertiser(settings)


@asynccontextmanager
async def lifespan(app: FastAPI):
    current_settings = get_settings()
    await init_db()
    if current_settings.enable_mdns:
        mdns_advertiser.settings = current_settings
        mdns_advertiser.start()
    yield
    if current_settings.enable_mdns:
        mdns_advertiser.stop()
    await close_db()


app = FastAPI(title=settings.app_name, version=settings.version, lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def lan_boundary_middleware(request: Request, call_next):
    current_settings = get_settings()
    if current_settings.enforce_lan_boundary:
        client = request.client
        if client and client.host and client.host not in ("testclient", "localhost"):
            if not is_lan_ip(client.host):
                return JSONResponse(
                    status_code=403,
                    content={"detail": "Zero-WAN violation: Non-LAN access forbidden"},
                )
    return await call_next(request)


app.include_router(router)


@app.websocket("/ws/orchestrator")
async def websocket_orchestrator(websocket: WebSocket) -> None:
    current_settings = get_settings()
    client = websocket.client
    client_host = client.host if client else None
    if current_settings.enforce_lan_boundary and client_host and client_host not in ("testclient", "localhost"):
        if not is_lan_ip(client_host):
            await websocket.close(code=1008)
            return

    await websocket.accept()
    peer_id: str | None = None
    try:
        try:
            registration_payload = await asyncio.wait_for(
                websocket.receive_json(),
                timeout=2.0,
            )
        except (asyncio.TimeoutError, TimeoutError):
            await websocket.close(code=1008)
            return

        if not isinstance(registration_payload, dict):
            await websocket.close(code=1008)
            return

        if current_settings.auth_token:
            token = registration_payload.get("auth_token")
            if token is None and isinstance(registration_payload.get("payload"), dict):
                token = registration_payload.get("payload", {}).get("auth_token")

            if not hmac.compare_digest(str(token) if token is not None else "", current_settings.auth_token):
                await websocket.close(code=1008)
                return

        registration = PeerRegistration(**registration_payload.get("payload", registration_payload))
        peer = await registry.register(websocket, registration)
        peer_id = peer.peer_id
        await receive_orchestrator_messages(websocket, peer)
    except WebSocketDisconnect:
        await registry.unregister(peer_id)
    except Exception:
        await registry.unregister(peer_id)
        raise


@app.get("/")
async def root() -> dict:
    return {
        "name": settings.app_name,
        "version": settings.version,
        "status_url": "/api/v1/system/status",
        "websocket_url": "/ws/orchestrator",
    }
