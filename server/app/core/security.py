from pathlib import Path
from uuid import uuid4


def ensure_tls_certificate(tls_dir: Path) -> tuple[Path, Path]:
    cert_path = tls_dir / "karunstream.local.crt"
    key_path = tls_dir / "karunstream.local.key"
    if cert_path.exists() and key_path.exists():
        return cert_path, key_path

    raise RuntimeError(
        "TLS certificate files are missing. Generate local certificates before enabling KARUNSTREAM_ENABLE_TLS.",
    )


def sanitize_filename(filename: str) -> str:
    cleaned = Path(filename).name.strip().replace("\x00", "")
    cleaned = cleaned.replace("/", "_").replace("\\", "_")
    return cleaned or f"karunstream-file-{uuid4().hex}"


def safe_upload_path(upload_dir: Path, filename: str) -> Path:
    upload_dir = upload_dir.resolve()
    destination = (upload_dir / sanitize_filename(filename)).resolve()
    if upload_dir not in destination.parents and destination != upload_dir:
        raise ValueError("Resolved upload path escaped the upload directory")
    return destination
