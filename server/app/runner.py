import uvicorn

from app.core.config import get_settings
from app.core.security import ensure_tls_certificate


def main() -> None:
    settings = get_settings()
    uvicorn_kwargs = {
        "app": "app.main:app",
        "host": settings.host,
        "port": settings.port,
    }
    if settings.enable_tls:
        cert_path, key_path = ensure_tls_certificate(settings.tls_dir)
        uvicorn_kwargs["ssl_certfile"] = str(cert_path)
        uvicorn_kwargs["ssl_keyfile"] = str(key_path)
    uvicorn.run(**uvicorn_kwargs)


if __name__ == "__main__":
    main()
