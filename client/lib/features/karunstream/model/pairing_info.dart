import 'dart:io';

/// Information required to pair a KarunStream client with a host server over LAN.
class PairingInfo {
  const PairingInfo({
    this.version = 1,
    required this.ip,
    required this.port,
    this.token,
    this.tlsFingerprint,
    this.serverName,
  });

  final int version;
  final String ip;
  final int port;
  final String? token;
  final String? tlsFingerprint;
  final String? serverName;

  /// Check whether an IP string represents a private LAN, link-local, or loopback address.
  static bool isLanIp(String ipStr) {
    if (ipStr.isEmpty) return false;
    final cleaned = ipStr.split('%')[0].trim();
    final address = InternetAddress.tryParse(cleaned);
    if (address == null) return false;

    if (address.isLoopback || address.isLinkLocal) return true;

    final raw = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      // 10.0.0.0/8
      if (raw[0] == 10) return true;
      // 172.16.0.0/12 (172.16.0.0 - 172.31.255.255)
      if (raw[0] == 172 && raw[1] >= 16 && raw[1] <= 31) return true;
      // 192.168.0.0/16
      if (raw[0] == 192 && raw[1] == 168) return true;
      // 127.0.0.0/8
      if (raw[0] == 127) return true;
      // 169.254.0.0/16
      if (raw[0] == 169 && raw[1] == 254) return true;
      return false;
    } else if (address.type == InternetAddressType.IPv6) {
      // Unique Local Address (ULA) fc00::/7 (fc00:: - fdff::)
      if ((raw[0] & 0xfe) == 0xfc) return true;
      return false;
    }
    return false;
  }

  /// Parse and validate a KarunStream pairing URL.
  ///
  /// Expected format: `karunstream://pair?v=1&ip=<ip>&port=<port>[&token=...][&tls=...][&name=...]`
  static PairingInfo parse(String urlString) {
    final uri = Uri.parse(urlString);

    if (uri.scheme != 'karunstream') {
      throw FormatException(
        "Invalid URL scheme '${uri.scheme}'; expected 'karunstream'",
      );
    }

    final target = uri.host.isNotEmpty ? uri.host : uri.path.replaceAll('/', '');
    if (target != 'pair') {
      throw FormatException(
        "Invalid URL target '$target'; expected 'pair'",
      );
    }

    final query = uri.queryParameters;

    final ip = query['ip'];
    if (ip == null || ip.isEmpty) {
      throw const FormatException("Missing 'ip' parameter in pairing URL");
    }
    if (!isLanIp(ip)) {
      throw FormatException(
        "IP address '$ip' is not a valid LAN, link-local, private, or loopback address",
      );
    }

    final portStr = query['port'];
    if (portStr == null || portStr.isEmpty) {
      throw const FormatException("Missing 'port' parameter in pairing URL");
    }
    final port = int.tryParse(portStr);
    if (port == null || port < 1 || port > 65535) {
      throw FormatException(
        "Port must be between 1 and 65535, got '$portStr'",
      );
    }

    final vStr = query['v'] ?? '1';
    final version = int.tryParse(vStr);
    if (version == null) {
      throw FormatException("Invalid version parameter: '$vStr'");
    }

    final token = query['token'];
    final tlsFingerprint = query['tls'];
    final serverName = query['name'];

    return PairingInfo(
      version: version,
      ip: ip,
      port: port,
      token: token,
      tlsFingerprint: tlsFingerprint,
      serverName: serverName,
    );
  }

  /// Constructs a `karunstream://pair?...` URI.
  Uri toUri() {
    final params = <String, String>{
      'v': version.toString(),
      'ip': ip,
      'port': port.toString(),
    };
    if (token != null) params['token'] = token!;
    if (tlsFingerprint != null) params['tls'] = tlsFingerprint!;
    if (serverName != null) params['name'] = serverName!;

    return Uri(
      scheme: 'karunstream',
      host: 'pair',
      queryParameters: params,
    );
  }

  /// Constructs `http://$ip:$port`.
  Uri toHttpUri() => Uri.parse('http://$ip:$port');

  /// Constructs `ws://$ip:$port/ws/orchestrator`.
  Uri toWebSocketUri() => Uri.parse('ws://$ip:$port/ws/orchestrator');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PairingInfo &&
          runtimeType == other.runtimeType &&
          version == other.version &&
          ip == other.ip &&
          port == other.port &&
          token == other.token &&
          tlsFingerprint == other.tlsFingerprint &&
          serverName == other.serverName;

  @override
  int get hashCode =>
      version.hashCode ^
      ip.hashCode ^
      port.hashCode ^
      token.hashCode ^
      tlsFingerprint.hashCode ^
      serverName.hashCode;

  @override
  String toString() =>
      'PairingInfo(v: $version, ip: $ip, port: $port, token: $token, tls: $tlsFingerprint, name: $serverName)';
}

/// Information for a Wi-Fi QR code configuration.
class WifiQrInfo {
  const WifiQrInfo({
    required this.ssid,
    this.password,
    this.authType = 'WPA',
    this.hidden = false,
  });

  final String ssid;
  final String? password;
  final String authType;
  final bool hidden;

  static String _escapeWifiField(String val) {
    var escaped = val.replaceAll(r'\', r'\\');
    for (final char in [';', ',', ':', '"']) {
      escaped = escaped.replaceAll(char, '\\$char');
    }
    return escaped;
  }

  static String _unescapeWifiField(String val) {
    final buffer = StringBuffer();
    var i = 0;
    while (i < val.length) {
      if (val[i] == r'\' && i + 1 < val.length) {
        buffer.write(val[i + 1]);
        i += 2;
      } else {
        buffer.write(val[i]);
        i++;
      }
    }
    return buffer.toString();
  }

  /// Formats standard `WIFI:S:<ssid>;T:<auth>;P:<pass>;H:<hidden>;;` string.
  String toBarcodeString() {
    final escapedSsid = _escapeWifiField(ssid);
    final parts = <String>['S:$escapedSsid', 'T:$authType'];
    if (password != null && authType.toLowerCase() != 'nopass') {
      final escapedPassword = _escapeWifiField(password!);
      parts.add('P:$escapedPassword');
    }
    parts.add('H:${hidden ? "true" : "false"}');
    return 'WIFI:${parts.join(';')};;';
  }

  /// Parse a standard Wi-Fi QR code string.
  ///
  /// Format: `WIFI:S:<ssid>;T:<auth>;P:<pass>;H:<hidden>;;`
  static WifiQrInfo? parse(String qrString) {
    if (!qrString.startsWith('WIFI:') || !qrString.endsWith(';')) {
      return null;
    }

    final content = qrString.substring(5);
    final fields = <String>[];
    final current = StringBuffer();
    var i = 0;
    while (i < content.length) {
      final char = content[i];
      if (char == r'\') {
        if (i + 1 < content.length) {
          current.write(char);
          current.write(content[i + 1]);
          i += 2;
        } else {
          return null; // Trailing escape
        }
      } else if (char == ';') {
        final token = current.toString();
        if (token.isNotEmpty) {
          fields.add(token);
        }
        current.clear();
        i++;
      } else {
        current.write(char);
        i++;
      }
    }

    if (current.isNotEmpty) {
      return null;
    }

    if (fields.isEmpty) {
      return null;
    }

    final parsedFields = <String, String>{};
    for (final field in fields) {
      final colonIdx = field.indexOf(':');
      if (colonIdx <= 0) continue;
      final key = field.substring(0, colonIdx);
      final rawVal = field.substring(colonIdx + 1);
      parsedFields[key] = _unescapeWifiField(rawVal);
    }

    final ssid = parsedFields['S'];
    if (ssid == null) return null;

    final password = parsedFields['P'];
    final authType = parsedFields['T'] ?? (password == null ? 'nopass' : 'WPA');
    final hiddenRaw = parsedFields['H']?.toLowerCase() ?? 'false';
    final hidden = hiddenRaw == 'true' || hiddenRaw == '1' || hiddenRaw == 'yes';

    return WifiQrInfo(
      ssid: ssid,
      password: password,
      authType: authType,
      hidden: hidden,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WifiQrInfo &&
          runtimeType == other.runtimeType &&
          ssid == other.ssid &&
          password == other.password &&
          authType == other.authType &&
          hidden == other.hidden;

  @override
  int get hashCode =>
      ssid.hashCode ^ password.hashCode ^ authType.hashCode ^ hidden.hashCode;

  @override
  String toString() =>
      'WifiQrInfo(ssid: $ssid, authType: $authType, hidden: $hidden, hasPassword: ${password != null})';
}
