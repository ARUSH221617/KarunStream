from contextlib import asynccontextmanager

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

from app.db.engine import init_db, close_db
from app.api.routes import router
from app.core.config import get_settings
from app.core.logging import configure_logging
from app.models import PeerRegistration
from app.services.discovery import MdnsAdvertiser
from app.services.sockets import receive_orchestrator_messages, registry

settings = get_settings()
configure_logging(settings)
mdns_advertiser = MdnsAdvertiser(settings)


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    mdns_advertiser.start()
    yield
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
app.include_router(router)


@app.websocket("/ws/orchestrator")
async def websocket_orchestrator(websocket: WebSocket) -> None:
    await websocket.accept()
    peer_id: str | None = None
    try:
        registration_payload = await websocket.receive_json()
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
