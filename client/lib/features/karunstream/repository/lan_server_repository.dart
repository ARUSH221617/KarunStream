import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../model/file_transfer.dart';
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

  Future<FileTransfer> uploadFile({
    required Uri serverUri,
    required String fileName,
    required String senderId,
    required String recipientId,
    String? filePath,
    Uint8List? bytes,
    ProgressCallback? onSendProgress,
  }) async {
    final multipartFile = filePath != null
        ? await MultipartFile.fromFile(filePath, filename: fileName)
        : MultipartFile.fromBytes(bytes ?? Uint8List(0), filename: fileName);
    final formData = FormData.fromMap({
      'file': multipartFile,
    });
    final response = await _dio.postUri<Map<String, dynamic>>(
      serverUri.replace(path: '/api/v1/files/upload'),
      data: formData,
      options: Options(
        headers: {
          'X-Sender-ID': senderId,
          'X-Recipient-ID': recipientId,
        },
      ),
      onSendProgress: onSendProgress,
    );
    return FileTransfer.fromJson(response.data ?? {});
  }

  Future<List<FileTransfer>> fetchFiles(
    Uri serverUri, {
    String? peerId,
  }) async {
    final response = await _dio.getUri<Map<String, dynamic>>(
      serverUri.replace(
        path: '/api/v1/files',
        queryParameters: {
          if (peerId != null) 'peer_id': peerId,
        },
      ),
    );
    final files = response.data?['files'] as List? ?? const [];
    return files
        .map(
          (file) => FileTransfer.fromJson(
            Map<String, dynamic>.from(file as Map),
          ),
        )
        .toList();
  }

  Future<void> downloadFile({
    required Uri serverUri,
    required String transferId,
    required String savePath,
    ProgressCallback? onReceiveProgress,
  }) async {
    await _dio.downloadUri(
      serverUri.replace(path: '/api/v1/files/$transferId/download'),
      savePath,
      onReceiveProgress: onReceiveProgress,
    );
  }

  Future<void> deleteFile({
    required Uri serverUri,
    required String transferId,
    required String peerId,
  }) async {
    await _dio.deleteUri<void>(
      serverUri.replace(path: '/api/v1/files/$transferId'),
      options: Options(headers: {'X-Peer-ID': peerId}),
    );
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
