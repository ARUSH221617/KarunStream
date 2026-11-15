from __future__ import annotations

from typing import Generator
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.core.pairing import (
    format_pairing_url,
    format_wifi_qr,
    parse_pairing_url,
    parse_wifi_qr,
)
from app.main import app
from app.models import PairingPayload


# ---------------------------------------------------------------------------
# WiFi QR Code Tests
# ---------------------------------------------------------------------------

def test_format_and_parse_wifi_qr_standard_wpa() -> None:
    qr = format_wifi_qr(ssid="KarunOffice", password="supersecretpass", auth_type="WPA", hidden=False)
    assert qr == "WIFI:S:KarunOffice;T:WPA;P:supersecretpass;H:false;;"

    parsed = parse_wifi_qr(qr)
    assert parsed["ssid"] == "KarunOffice"
    assert parsed["password"] == "supersecretpass"
    assert parsed["auth_type"] == "WPA"
    assert parsed["hidden"] is False


def test_format_and_parse_wifi_qr_special_characters_escaping() -> None:
    ssid = r'My;Network:WPA\Special,Name"Quote'
    password = r'P@$$;w0rd:With\Backslash,And"Quote'

    qr = format_wifi_qr(ssid=ssid, password=password, auth_type="WPA", hidden=False)

    # Verify that backslashes and special delimiters are properly escaped
    assert r"My\;Network\:WPA\\Special\,Name\"Quote" in qr
    assert r"P@$$\;w0rd\:With\\Backslash\,And\"Quote" in qr

    # Round trip parsing must restore original strings exactly
    parsed = parse_wifi_qr(qr)
    assert parsed["ssid"] == ssid
    assert parsed["password"] == password
    assert parsed["auth_type"] == "WPA"
    assert parsed["hidden"] is False


def test_format_and_parse_wifi_qr_open_network_nopass() -> None:
    # 1. auth_type="nopass", password=None
    qr = format_wifi_qr(ssid="KarunOpenGuest", password=None, auth_type="nopass", hidden=False)
    assert qr == "WIFI:S:KarunOpenGuest;T:nopass;H:false;;"
    assert "P:" not in qr

    parsed = parse_wifi_qr(qr)
    assert parsed["ssid"] == "KarunOpenGuest"
    assert parsed["password"] is None
    assert parsed["auth_type"] == "nopass"
    assert parsed["hidden"] is False

    # 2. auth_type="nopass" with a dummy password should also omit P:
    qr_with_pw = format_wifi_qr(ssid="KarunOpen2", password="ignored", auth_type="nopass", hidden=False)
    assert "P:" not in qr_with_pw


def test_format_and_parse_wifi_qr_hidden_network() -> None:
    qr = format_wifi_qr(ssid="HiddenFieldAP", password="secretkey", auth_type="WPA", hidden=True)
    assert qr == "WIFI:S:HiddenFieldAP;T:WPA;P:secretkey;H:true;;"

    parsed = parse_wifi_qr(qr)
    assert parsed["ssid"] == "HiddenFieldAP"
    assert parsed["password"] == "secretkey"
    assert parsed["hidden"] is True


def test_parse_wifi_qr_malformed_inputs() -> None:
    # Does not start with WIFI:
    with pytest.raises(ValueError, match="must start with 'WIFI:'"):
        parse_wifi_qr("WLAN:S:MyNet;P:1234;;")

    # Does not end with semicolon
    with pytest.raises(ValueError, match="must terminate with ';'"):
        parse_wifi_qr("WIFI:S:MyNet;T:WPA;P:1234")

    # Missing SSID
    with pytest.raises(ValueError, match="missing required 'S'"):
        parse_wifi_qr("WIFI:T:WPA;P:1234;;")

    # Malformed field without colon separator
    with pytest.raises(ValueError, match="Malformed WiFi QR field"):
        parse_wifi_qr("WIFI:S:MyNet;BROKENFIELD;;")

    # Escaped semicolon leaves unclosed trailing content
    with pytest.raises(ValueError):
        parse_wifi_qr(r"WIFI:S:MyNet\;")

    # Non-string input
    with pytest.raises(ValueError):
        parse_wifi_qr(12345)  # type: ignore


# ---------------------------------------------------------------------------
# Pairing URL Tests
# ---------------------------------------------------------------------------

@pytest.mark.parametrize(
    "lan_ip",
    [
        "192.168.1.1",
        "10.0.0.100",
        "172.16.5.20",
        "169.254.1.1",  # Link-local IPv4
        "127.0.0.1",    # Loopback IPv4
        "::1",          # Loopback IPv6
        "fe80::1",      # Link-local IPv6
    ],
)
def test_format_and_parse_pairing_url_valid_lan_ips(lan_ip: str) -> None:
    url = format_pairing_url(ip=lan_ip, port=8080)
    assert url.startswith("karunstream://pair?")

    parsed = parse_pairing_url(url)
    assert parsed["v"] == "1"
    assert parsed["ip"] == lan_ip
    assert parsed["port"] == 8080
    assert parsed["token"] is None
    assert parsed["tls_fingerprint"] is None
    assert parsed["server_name"] is None


def test_format_and_parse_pairing_url_token_and_tls_inclusion() -> None:
    fingerprint = "e" * 64
    url = format_pairing_url(
        ip="192.168.1.200",
        port=9090,
        token="field-auth-jwt-token",
        tls_fingerprint=fingerprint,
        server_name="Karun Field Host #1",
    )
    assert "token=field-auth-jwt-token" in url
    assert f"tls={fingerprint}" in url
    assert "name=Karun+Field+Host+%231" in url

    parsed = parse_pairing_url(url)
    assert parsed["v"] == "1"
    assert parsed["ip"] == "192.168.1.200"
    assert parsed["port"] == 9090
    assert parsed["token"] == "field-auth-jwt-token"
    assert parsed["tls_fingerprint"] == fingerprint
    assert parsed["server_name"] == "Karun Field Host #1"


@pytest.mark.parametrize(
    "wan_ip",
    [
        "8.8.8.8",
        "1.1.1.1",
        "142.250.190.46",
        "2607:f8b0:4005:805::200e",
        "not-an-ip",
        "999.999.999.999",
    ],
)
def test_parse_pairing_url_rejects_wan_or_invalid_ip(wan_ip: str) -> None:
    url = f"karunstream://pair?v=1&ip={wan_ip}&port=8080"
    with pytest.raises(ValueError, match="not a valid LAN"):
        parse_pairing_url(url)


@pytest.mark.parametrize(
    "bad_port",
    [
        "99999",
        "-1",
        "0",
        "65536",
        "abc",
    ],
)
def test_parse_pairing_url_rejects_invalid_port(bad_port: str) -> None:
    url = f"karunstream://pair?v=1&ip=192.168.1.10&port={bad_port}"
    with pytest.raises(ValueError, match="[Pp]ort"):
        parse_pairing_url(url)


@pytest.mark.parametrize(
    "bad_scheme_url",
    [
        "http://pair?v=1&ip=192.168.1.10&port=8080",
        "https://pair?v=1&ip=192.168.1.10&port=8080",
        "ftp://pair?v=1&ip=192.168.1.10&port=8080",
        "karunstream://connect?v=1&ip=192.168.1.10&port=8080",  # wrong path/netloc
    ],
)
def test_parse_pairing_url_rejects_non_karunstream_schemes_or_targets(bad_scheme_url: str) -> None:
    with pytest.raises(ValueError):
        parse_pairing_url(bad_scheme_url)


# ---------------------------------------------------------------------------
# API Endpoint Tests: GET /api/v1/system/pair-payload
# ---------------------------------------------------------------------------

def test_pair_payload_endpoint_default_settings() -> None:
    settings = get_settings()
    original_ssid = settings.hotspot_ssid
    original_advertised_ip = settings.advertised_ip
    settings.hotspot_ssid = None
    settings.advertised_ip = "192.168.1.42"

    try:
        with TestClient(app) as client:
            response = client.get("/api/v1/system/pair-payload")

        assert response.status_code == 200
        data = response.json()

        # Validate with Pydantic model
        payload = PairingPayload(**data)
        assert payload.host_ip == "192.168.1.42"
        assert payload.port == settings.port
        assert payload.server_name == settings.server_name
        assert payload.wifi_qr is None
        assert payload.pairing_url.startswith("karunstream://pair?")

        # Verify pairing_url parses correctly
        parsed_url = parse_pairing_url(payload.pairing_url)
        assert parsed_url["ip"] == "192.168.1.42"
        assert parsed_url["port"] == settings.port
    finally:
        settings.hotspot_ssid = original_ssid
        settings.advertised_ip = original_advertised_ip


def test_pair_payload_endpoint_with_hotspot_configured() -> None:
    settings = get_settings()
    original_ssid = settings.hotspot_ssid
    original_pw = settings.hotspot_password
    original_auth = settings.hotspot_auth_type
    original_adv_ip = settings.advertised_ip
    original_token = settings.auth_token
    original_tls = settings.tls_fingerprint

    settings.hotspot_ssid = "KarunFieldHotspot"
    settings.hotspot_password = "field-secret-pass"
    settings.hotspot_auth_type = "WPA"
    settings.advertised_ip = "192.168.43.1"
    settings.auth_token = "hotspot-auth-token"
    settings.tls_fingerprint = "f" * 64

    try:
        with TestClient(app) as client:
            response = client.get("/api/v1/system/pair-payload")

        assert response.status_code == 200
        data = response.json()

        payload = PairingPayload(**data)
        assert payload.host_ip == "192.168.43.1"
        assert payload.auth_token == "hotspot-auth-token"
        assert payload.tls_fingerprint == "f" * 64
        assert payload.wifi_qr is not None

        # Verify wifi_qr contents
        parsed_wifi = parse_wifi_qr(payload.wifi_qr)
        assert parsed_wifi["ssid"] == "KarunFieldHotspot"
        assert parsed_wifi["password"] == "field-secret-pass"
        assert parsed_wifi["auth_type"] == "WPA"
        assert parsed_wifi["hidden"] is False

        # Verify pairing_url contents
        parsed_url = parse_pairing_url(payload.pairing_url)
        assert parsed_url["ip"] == "192.168.43.1"
        assert parsed_url["token"] == "hotspot-auth-token"
        assert parsed_url["tls_fingerprint"] == "f" * 64
    finally:
        settings.hotspot_ssid = original_ssid
        settings.hotspot_password = original_pw
        settings.hotspot_auth_type = original_auth
        settings.advertised_ip = original_adv_ip
        settings.auth_token = original_token
        settings.tls_fingerprint = original_tls
