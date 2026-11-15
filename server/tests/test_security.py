from pathlib import Path
import unicodedata
import httpx
import pytest

from app.core.config import get_settings
from app.core.security import is_lan_ip, safe_upload_path, sanitize_filename
from app.main import app


def test_sanitize_filename_strips_path_segments() -> None:
    assert sanitize_filename("../../secret.txt") == "secret.txt"
    assert sanitize_filename(r"..\secret.txt") == "secret.txt"


def test_safe_upload_path_stays_inside_upload_dir(tmp_path: Path) -> None:
    destination = safe_upload_path(tmp_path, "../../secret.txt")
    assert destination == (tmp_path / "secret.txt").resolve()


def test_is_lan_ip_valid_lan_addresses() -> None:
    # Private IPv4
    assert is_lan_ip("192.168.1.1") is True
    assert is_lan_ip("10.0.0.1") is True
    assert is_lan_ip("172.16.0.1") is True
    # Loopback
    assert is_lan_ip("127.0.0.1") is True
    assert is_lan_ip("::1") is True
    # Link-local
    assert is_lan_ip("169.254.1.2") is True
    assert is_lan_ip("fe80::1") is True
    # IPv6 ULA
    assert is_lan_ip("fd00::1") is True


def test_is_lan_ip_wan_and_invalid_addresses() -> None:
    # Public WAN IPs
    assert is_lan_ip("8.8.8.8") is False
    assert is_lan_ip("1.1.1.1") is False
    assert is_lan_ip("2607:f8b0:4005:805::200e") is False
    # Invalid strings and garbage
    assert is_lan_ip("garbage") is False
    assert is_lan_ip("") is False
    assert is_lan_ip(None) is False
    assert is_lan_ip("999.999.999.999") is False


def test_sanitize_filename_windows_reserved() -> None:
    assert sanitize_filename("CON.txt") == "safe_CON.txt"
    assert sanitize_filename("aux") == "safe_aux"
    assert sanitize_filename("NUL") == "safe_NUL"
    assert sanitize_filename("com1.dat") == "safe_com1.dat"
    assert sanitize_filename("lpt1.log") == "safe_lpt1.log"
    assert sanitize_filename("aux.tar.gz") == "safe_aux.tar.gz"


def test_sanitize_filename_drive_letters() -> None:
    assert sanitize_filename(r"C:\file.txt") == "file.txt"
    assert sanitize_filename("D:/data.csv") == "data.csv"
    assert sanitize_filename("E:relative.bin") == "relative.bin"


def test_sanitize_filename_nfd_normalization() -> None:
    nfd_name = unicodedata.normalize("NFD", "café_naïve.txt")
    assert not unicodedata.is_normalized("NFC", nfd_name)
    sanitized = sanitize_filename(nfd_name)
    assert unicodedata.is_normalized("NFC", sanitized)
    assert sanitized == "café_naïve.txt"


def test_sanitize_filename_fallback_on_empty() -> None:
    fallback = sanitize_filename("")
    assert fallback.startswith("karunstream-file-")
    fallback_spaces = sanitize_filename("   \x00   ")
    assert fallback_spaces.startswith("karunstream-file-")


@pytest.mark.asyncio
async def test_zero_wan_http_middleware_blocks_non_lan() -> None:
    # Non-LAN client blocked with 403
    transport_wan = httpx.ASGITransport(app=app, client=("8.8.8.8", 12345))
    async with httpx.AsyncClient(transport=transport_wan, base_url="http://test") as client:
        response = await client.get("/")
        assert response.status_code == 403
        assert response.json()["detail"] == "Zero-WAN violation: Non-LAN access forbidden"

    # LAN client allowed with 200
    transport_lan = httpx.ASGITransport(app=app, client=("192.168.1.50", 12345))
    async with httpx.AsyncClient(transport=transport_lan, base_url="http://test") as client:
        response = await client.get("/")
        assert response.status_code == 200

    # Boundary enforcement disabled allows WAN client
    settings = get_settings()
    settings.enforce_lan_boundary = False
    try:
        async with httpx.AsyncClient(transport=transport_wan, base_url="http://test") as client:
            response = await client.get("/")
            assert response.status_code == 200
    finally:
        settings.enforce_lan_boundary = True
