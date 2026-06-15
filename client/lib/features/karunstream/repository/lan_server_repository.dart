import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../model/karun_event.dart';
import '../model/karun_peer.dart';
import '../model/server_status.dart';

class LanServerRepository {
  LanServerRepository({
    Dio? dio,
    WebSocketConnector? socketConnector,
  })  : _dio = dio ?? Dio(),
        _socketConnector = socketConnector ?? WebSocketChannel.connect;

  final Dio _dio;
  final WebSocketConnector _socketConnector;

  Future<ServerStatus> fetchStatus(Uri serverUri) async {
    final response = await _dio.getUri<Map<String, dynamic>>(
      serverUri.replace(path: '/api/v1/system/status'),
    );
    return ServerStatus.fromJson(response.data ?? {});
  }

  Future<List<KarunPeer>> fetchPeers(Uri serverUri) async {
    final response = await _dio.getUri<Map<String, dynamic>>(
      serverUri.replace(path: '/api/v1/peers'),
    );
    final peers = response.data?['peers'] as List? ?? const [];
    return peers
        .map(
          (peer) => KarunPeer.fromJson(
            Map<String, dynamic>.from(peer as Map),
          ),
        )
        .toList();
  }

  WebSocketChannel connectSocket(
    Uri serverUri,
    Map<String, dynamic> registration,
  ) {
    final wsScheme = serverUri.scheme == 'https' ? 'wss' : 'ws';
    final socketUri = serverUri.replace(
      scheme: wsScheme,
      path: '/ws/orchestrator',
    );
    final channel = _socketConnector(socketUri);
    channel.sink.add(jsonEncode(registration));
    return channel;
  }

  Stream<KarunEvent> events(WebSocketChannel channel) {
    return channel.stream.where((message) => message is String).map(
          (message) => KarunEvent.fromJson(
            jsonDecode(message as String) as Map<String, dynamic>,
          ),
        );
  }

  Future<List<Uri>> discoverServers({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final available = <Uri>{};
    final candidates = <Uri>{
      Uri.parse('http://127.0.0.1:8080'),
      Uri.parse('http://localhost:8080'),
      Uri.parse('http://10.0.2.2:8080'),
    };

    // 1. Try mDNS Discovery
    final client = MDnsClient();
    try {
      await client.start();
      const String serviceType = '_karunstream._tcp.local';
      await for (final PtrResourceRecord ptr in client
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(serviceType),
          )
          .timeout(const Duration(milliseconds: 1500),
              onTimeout: (sink) => sink.close())) {
        await for (final SrvResourceRecord srv in client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
        )) {
          await for (final IPAddressResourceRecord ip
              in client.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
          )) {
            candidates.add(Uri.parse('http://${ip.address.address}:${srv.port}'));
          }
        }
      }
    } catch (_) {} finally {
      client.stop();
    }

    // 2. Parallel Subnet Scan (The "Zero-Config" miracle)
    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );

      for (final interface in interfaces) {
        final address = interface.addresses.first.address;
        if (address.startsWith('127.')) continue;

        final base = address.substring(0, address.lastIndexOf('.') + 1);
        final List<Future<void>> scans = [];

        for (int i = 1; i < 255; i++) {
          final targetIp = '$base$i';
          if (targetIp == address) continue;

          scans.add(() async {
            final uri = Uri.parse('http://$targetIp:8080');
            try {
              await fetchStatus(uri).timeout(const Duration(milliseconds: 500));
              available.add(uri);
            } catch (_) {}
          }());
        }
        await Future.wait(scans);
      }
    } catch (_) {}

    // 3. Final validation of static candidates
    await Future.wait(
      candidates.map((candidate) async {
        try {
          await fetchStatus(candidate)
              .timeout(const Duration(milliseconds: 600));
          available.add(candidate);
        } catch (_) {}
      }),
    );

    return available.toList();
  }
}

typedef WebSocketConnector = WebSocketChannel Function(Uri uri);
