import 'package:flutter_test/flutter_test.dart';
import 'package:karunstream/features/karunstream/model/pairing_info.dart';

void main() {
  group('PairingInfo', () {
    test('parses valid LAN pairing URL correctly', () {
      const url =
          'karunstream://pair?v=1&ip=192.168.1.50&port=8080&token=abc&tls=fingerprint123&name=NodeA';
      final info = PairingInfo.parse(url);

      expect(info.version, 1);
      expect(info.ip, '192.168.1.50');
      expect(info.port, 8080);
      expect(info.token, 'abc');
      expect(info.tlsFingerprint, 'fingerprint123');
      expect(info.serverName, 'NodeA');
      expect(info.toHttpUri().toString(), 'http://192.168.1.50:8080');
      expect(
        info.toWebSocketUri().toString(),
        'ws://192.168.1.50:8080/ws/orchestrator',
      );
    });

    test('accepts loopback (127.0.0.1) and link-local (169.254.1.1) addresses', () {
      final loopback = PairingInfo.parse('karunstream://pair?ip=127.0.0.1&port=5000');
      expect(loopback.ip, '127.0.0.1');
      expect(loopback.port, 5000);

      final linkLocal = PairingInfo.parse('karunstream://pair?ip=169.254.1.1&port=9000');
      expect(linkLocal.ip, '169.254.1.1');
      expect(linkLocal.port, 9000);

      final ipv6Loopback = PairingInfo.parse('karunstream://pair?ip=::1&port=8080');
      expect(ipv6Loopback.ip, '::1');
    });

    test('accepts other private RFC1918 subnets (10.x and 172.16-31.x)', () {
      final ip10 = PairingInfo.parse('karunstream://pair?ip=10.200.1.5&port=8080');
      expect(ip10.ip, '10.200.1.5');

      final ip172 = PairingInfo.parse('karunstream://pair?ip=172.20.10.2&port=8080');
      expect(ip172.ip, '172.20.10.2');
    });

    test('rejects public WAN IP addresses', () {
      expect(
        () => PairingInfo.parse('karunstream://pair?ip=8.8.8.8&port=8080'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PairingInfo.parse('karunstream://pair?ip=1.1.1.1&port=8080'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PairingInfo.parse('karunstream://pair?ip=172.32.0.1&port=8080'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-karunstream schemes and invalid targets', () {
      expect(
        () => PairingInfo.parse('http://pair?ip=192.168.1.1&port=8080'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PairingInfo.parse('karunstream://invalid_target?ip=192.168.1.1&port=8080'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects invalid ports', () {
      expect(
        () => PairingInfo.parse('karunstream://pair?ip=192.168.1.1&port=99999'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PairingInfo.parse('karunstream://pair?ip=192.168.1.1&port=-5'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PairingInfo.parse('karunstream://pair?ip=192.168.1.1&port=0'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PairingInfo.parse('karunstream://pair?ip=192.168.1.1&port=abc'),
        throwsA(isA<FormatException>()),
      );
    });

    test('round trips via toUri()', () {
      const original =
          'karunstream://pair?v=1&ip=192.168.1.100&port=9090&token=sec_token&tls=cert_hash&name=HostServer';
      final parsed = PairingInfo.parse(original);
      final reconstructed = parsed.toUri().toString();
      final reParsed = PairingInfo.parse(reconstructed);

      expect(reParsed, equals(parsed));
    });
  });

  group('WifiQrInfo', () {
    test('parses standard WPA network QR', () {
      const qr = 'WIFI:S:HomeNet;T:WPA;P:SecretPass123;H:false;;';
      final wifi = WifiQrInfo.parse(qr);

      expect(wifi, isNotNull);
      expect(wifi!.ssid, 'HomeNet');
      expect(wifi.authType, 'WPA');
      expect(wifi.password, 'SecretPass123');
      expect(wifi.hidden, isFalse);
    });

    test('parses nopass and hidden networks', () {
      const openHidden = 'WIFI:S:GuestAir;T:nopass;H:true;;';
      final wifi = WifiQrInfo.parse(openHidden);

      expect(wifi, isNotNull);
      expect(wifi!.ssid, 'GuestAir');
      expect(wifi.authType, 'nopass');
      expect(wifi.password, isNull);
      expect(wifi.hidden, isTrue);
    });

    test('handles escaped special characters properly', () {
      const qr = r'WIFI:S:My\;SSID\:1\,name;T:WPA;P:p\@ss\;\,word;H:true;;';
      final wifi = WifiQrInfo.parse(qr);

      expect(wifi, isNotNull);
      expect(wifi!.ssid, 'My;SSID:1,name');
      expect(wifi.password, 'p@ss;,word');
      expect(wifi.hidden, isTrue);

      final barcode = wifi.toBarcodeString();
      final roundTripped = WifiQrInfo.parse(barcode);
      expect(roundTripped, equals(wifi));
    });

    test('returns null on invalid formatting', () {
      expect(WifiQrInfo.parse('NOT_WIFI_QR'), isNull);
      expect(WifiQrInfo.parse('WIFI:T:WPA;P:pass;;'), isNull); // Missing SSID
      expect(WifiQrInfo.parse('WIFI:S:test'), isNull); // Not ending with ;
    });
  });
}
