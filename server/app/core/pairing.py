from __future__ import annotations

from typing import Any
import urllib.parse

from app.core.security import is_lan_ip


def _escape_wifi_field(val: str) -> str:
    """Escape special characters in a WiFi QR code field (\\, ;, ,, :, \")."""
    val = val.replace("\\", "\\\\")
    for char in (";", ",", ":", '"'):
        val = val.replace(char, f"\\{char}")
    return val


def _unescape_wifi_field(val: str) -> str:
    """Unescape special characters in a WiFi QR code field."""
    result: list[str] = []
    i = 0
    length = len(val)
    while i < length:
        if val[i] == "\\" and i + 1 < length:
            result.append(val[i + 1])
            i += 2
        else:
            result.append(val[i])
            i += 1
    return "".join(result)


def format_wifi_qr(
    ssid: str,
    password: str | None = None,
    auth_type: str = "WPA",
    hidden: bool = False,
) -> str:
    """Format WiFi network details into a standard WiFi QR code string.

    Format: WIFI:S:<ssid>;T:<auth_type>;P:<password>;H:<true/false>;;
    If password is None or auth_type is 'nopass', P: is omitted.
    """
    escaped_ssid = _escape_wifi_field(ssid)
    parts = [f"S:{escaped_ssid}", f"T:{auth_type}"]
    if password is not None and auth_type.lower() != "nopass":
        escaped_password = _escape_wifi_field(password)
        parts.append(f"P:{escaped_password}")
    parts.append(f"H:{'true' if hidden else 'false'}")
    return f"WIFI:{';'.join(parts)};;"


def parse_wifi_qr(qr_str: str) -> dict[str, Any]:
    """Parse a standard WiFi QR string into a dictionary of network attributes.

    Returns dict with keys: 'ssid', 'password', 'auth_type', 'hidden'.
    Raises ValueError if the string is malformed or does not start with 'WIFI:'.
    """
    if not isinstance(qr_str, str) or not qr_str.startswith("WIFI:"):
        raise ValueError("Malformed WiFi QR code: must start with 'WIFI:'")

    if not qr_str.endswith(";"):
        raise ValueError("Malformed WiFi QR code: must terminate with ';'")

    content = qr_str[5:]
    fields: list[str] = []
    current: list[str] = []
    i = 0
    length = len(content)

    while i < length:
        char = content[i]
        if char == "\\":
            if i + 1 < length:
                current.append(char)
                current.append(content[i + 1])
                i += 2
            else:
                raise ValueError("Malformed WiFi QR code: trailing escape character")
        elif char == ";":
            token = "".join(current)
            if token:
                fields.append(token)
            current = []
            i += 1
        else:
            current.append(char)
            i += 1

    if current:
        raise ValueError("Malformed WiFi QR code: unclosed content after last semicolon")

    if not fields:
        raise ValueError("Malformed WiFi QR code: no fields found")

    parsed_fields: dict[str, str] = {}
    for field in fields:
        key, sep, val = field.partition(":")
        if not sep:
            raise ValueError(f"Malformed WiFi QR field: '{field}'")
        parsed_fields[key] = _unescape_wifi_field(val)

    if "S" not in parsed_fields:
        raise ValueError("Malformed WiFi QR code: missing required 'S' (SSID) field")

    ssid = parsed_fields["S"]
    password = parsed_fields.get("P")
    auth_type = parsed_fields.get("T", "nopass" if password is None else "WPA")
    hidden_raw = parsed_fields.get("H", "false").lower()
    hidden = hidden_raw in ("true", "1", "yes")

    return {
        "ssid": ssid,
        "password": password,
        "auth_type": auth_type,
        "hidden": hidden,
    }


def format_pairing_url(
    ip: str,
    port: int,
    token: str | None = None,
    tls_fingerprint: str | None = None,
    server_name: str | None = None,
) -> str:
    """Format KarunStream pairing parameters into a custom scheme URL.

    Format: karunstream://pair?v=1&ip=<ip>&port=<port>[&token=...][&tls=...][&name=...]
    """
    params: dict[str, str] = {
        "v": "1",
        "ip": ip,
        "port": str(port),
    }
    if token is not None:
        params["token"] = token
    if tls_fingerprint is not None:
        params["tls"] = tls_fingerprint
    if server_name is not None:
        params["name"] = server_name

    query_string = urllib.parse.urlencode(params)
    return f"karunstream://pair?{query_string}"


def parse_pairing_url(url: str) -> dict[str, Any]:
    """Parse a KarunStream pairing URL and validate its security properties.

    Validates:
      - Scheme must be 'karunstream'.
      - Netloc / target must be 'pair'.
      - IP must be a valid LAN / private / link-local / loopback address.
      - Port must be an integer between 1 and 65535.

    Returns dict with: 'v', 'ip', 'port', 'token', 'tls_fingerprint', 'server_name'.
    Raises ValueError on validation failure.
    """
    if not isinstance(url, str):
        raise ValueError("URL must be a string")

    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "karunstream":
        raise ValueError(f"Invalid URL scheme '{parsed.scheme}'; expected 'karunstream'")

    if parsed.netloc != "pair" and (parsed.netloc or parsed.path.strip("/") != "pair"):
        raise ValueError(f"Invalid URL target; expected 'pair', got '{parsed.netloc or parsed.path}'")

    query = urllib.parse.parse_qs(parsed.query)

    if "ip" not in query or not query["ip"][0]:
        raise ValueError("Missing 'ip' parameter in pairing URL")
    ip = query["ip"][0]
    if not is_lan_ip(ip):
        raise ValueError(f"IP address '{ip}' is not a valid LAN, link-local, private, or loopback address")

    if "port" not in query or not query["port"][0]:
        raise ValueError("Missing 'port' parameter in pairing URL")
    try:
        port = int(query["port"][0])
    except (ValueError, TypeError):
        raise ValueError(f"Invalid port: '{query['port'][0]}'")
    if not (1 <= port <= 65535):
        raise ValueError(f"Port must be between 1 and 65535, got {port}")

    v = query.get("v", ["1"])[0]
    token = query.get("token", [None])[0]
    tls_fingerprint = query.get("tls", [None])[0]
    server_name = query.get("name", [None])[0]

    return {
        "v": v,
        "ip": ip,
        "port": port,
        "token": token,
        "tls_fingerprint": tls_fingerprint,
        "server_name": server_name,
    }
