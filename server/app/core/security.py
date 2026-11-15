from __future__ import annotations

import ipaddress
from pathlib import Path
import re
import unicodedata
from uuid import uuid4

WINDOWS_RESERVED = {
    "CON",
    "PRN",
    "AUX",
    "NUL",
    *(f"COM{i}" for i in range(1, 10)),
    *(f"LPT{i}" for i in range(1, 10)),
}


def is_lan_ip(ip_str: str | None) -> bool:
    """Return True if ip_str represents a LAN/private/loopback/link-local address.

    Returns False for WAN/public IPs or invalid IP strings.
    """
    if not ip_str or not isinstance(ip_str, str):
        return False
    cleaned = ip_str.split("%")[0].strip()
    try:
        ip = ipaddress.ip_address(cleaned)
        return bool(ip.is_loopback or ip.is_private or ip.is_link_local)
    except ValueError:
        return False


def ensure_tls_certificate(tls_dir: Path) -> tuple[Path, Path]:
    cert_path = tls_dir / "karunstream.local.crt"
    key_path = tls_dir / "karunstream.local.key"
    if cert_path.exists() and key_path.exists():
        return cert_path, key_path

    raise RuntimeError(
        "TLS certificate files are missing. Generate local certificates before enabling KARUNSTREAM_ENABLE_TLS.",
    )


def sanitize_filename(filename: str) -> str:
    if not filename:
        return f"karunstream-file-{uuid4().hex}"

    cleaned_input = filename.replace("\x00", "")
    normalized = unicodedata.normalize("NFC", cleaned_input)
    normalized = normalized.replace("\\", "/")
    normalized = re.sub(r"^[a-zA-Z]:", "", normalized)
    cleaned = Path(normalized).name.strip()
    cleaned = cleaned.replace("/", "_").replace("\\", "_").strip()

    if not cleaned:
        return f"karunstream-file-{uuid4().hex}"

    stem = Path(cleaned).stem.upper()
    base = cleaned.split(".")[0].upper()
    if stem in WINDOWS_RESERVED or base in WINDOWS_RESERVED:
        cleaned = f"safe_{cleaned}"

    return cleaned


def safe_upload_path(upload_dir: Path, filename: str) -> Path:
    upload_dir = upload_dir.resolve()
    destination = (upload_dir / sanitize_filename(filename)).resolve()
    if upload_dir not in destination.parents and destination != upload_dir:
        raise ValueError("Resolved upload path escaped the upload directory")
    return destination
