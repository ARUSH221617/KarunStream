from functools import lru_cache
from pathlib import Path
from uuid import uuid4
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="KARUNSTREAM_", env_file=".env")

    app_name: str = "KarunStream Server"
    version: str = "0.1.0"
    server_id: str = str(uuid4())
    host: str = "0.0.0.0"
    port: int = 8080
    server_name: str = "KarunStream LAN"
    service_type: str = "_karunstream._tcp.local."
    upload_dir: Path = Path("/tmp/karunstream/uploads")
    max_upload_bytes: int = 10 * 1024 * 1024 * 1024
    chunk_size: int = 1024 * 1024
    log_dir: Path = Path("/tmp/karunstream/logs")
    log_max_bytes: int = 5 * 1024 * 1024
    log_backup_count: int = 3
    enable_mdns: bool = True
    advertised_ip: str | None = None
    enable_tls: bool = False
    tls_dir: Path = Path("/tmp/karunstream/tls")
    cors_origins: list[str] = ["*"]


@lru_cache
def get_settings() -> Settings:
    settings = Settings()
    settings.upload_dir.mkdir(parents=True, exist_ok=True)
    settings.log_dir.mkdir(parents=True, exist_ok=True)
    settings.tls_dir.mkdir(parents=True, exist_ok=True)
    return settings
