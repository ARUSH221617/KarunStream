import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../model/file_transfer.dart';
import '../model/karun_event.dart';
import '../model/karun_peer.dart';
import '../model/server_status.dart';
import '../model/shared_folder.dart';
import '../model/conversation.dart';
import '../model/chat_message.dart';

class LanServerRepository {
  LanServerRepository({
    Dio? dio,
    WebSocketConnector? socketConnector,
  })  : _dio = dio ?? Dio(),
        _socketConnector = socketConnector ?? WebSocketChannel.connect;

  final Dio _dio;
  final WebSocketConnector _socketConnector;

  Future<Conversation> createConversation({
    required Uri serverUri,
    required String peerId,
    required String type, // 'private', 'group', 'channel'
    String? title,
    String? description,
    required List<String> initialMembers,
  }) async {
    final response = await _dio.postUri<Map<String, dynamic>>(
      serverUri.replace(path: '/api/v1/conversations'),
      data: {
        'conversation_type': type,
        'title': title,
        'description': description,
        'initial_members': initialMembers,
      },
      options: Options(headers: {'X-Peer-ID': peerId}),
    );
    return Conversation.fromJson(response.data ?? {});
  }

  Future<List<Conversation>> fetchConversations({
    required Uri serverUri,
    required String peerId,
  }) async {
    final response = await _dio.getUri<Map<String, dynamic>>(
      serverUri.replace(path: '/api/v1/conversations'),
      options: Options(headers: {'X-Peer-ID': peerId}),
    );
    final list = response.data?['conversations'] as List? ?? const [];
    return list
        .map((c) => Conversation.fromJson(Map<String, dynamic>.from(c as Map)))
        .toList();
  }

  Future<List<ChatMessage>> fetchConversationMessages({
    required Uri serverUri,
    required String conversationId,
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _dio.getUri<Map<String, dynamic>>(
      serverUri.replace(
        path: '/api/v1/conversations/$conversationId/messages',
        queryParameters: {
          'limit': limit.toString(),
          'offset': offset.toString(),
        },
      ),
    );
    final list = response.data?['messages'] as List? ?? const [];
    return list
        .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m as Map)))
        .toList();
  }

  Future<void> addConversationMember({
    required Uri serverUri,
    required String conversationId,
    required String peerId,
    String role = 'member',
  }) async {
    await _dio.postUri<dynamic>(
      serverUri.replace(path: '/api/v1/conversations/$conversationId/members'),
      data: {
        'peer_id': peerId,
        'role': role,
      },
    );
  }

  Future<void> removeConversationMember({
    required Uri serverUri,
    required String conversationId,
    required String peerId,
  }) async {
    await _dio.deleteUri<dynamic>(
      serverUri.replace(
        path: '/api/v1/conversations/$conversationId/members/$peerId',
      ),
    );
  }

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
    CancelToken? cancelToken,
  }) async {
    await _dio.downloadUri(
      serverUri.replace(path: '/api/v1/files/$transferId/download'),
      savePath,
      onReceiveProgress: onReceiveProgress,
      cancelToken: cancelToken,
    );
  }

  Future<List<SharedFolder>> fetchShares(Uri serverUri) async {
    final response = await _dio.getUri<Map<String, dynamic>>(
      serverUri.replace(path: '/api/v1/shares'),
    );
    final shares = response.data?['shares'] as List? ?? const [];
    return shares
        .map(
          (share) => SharedFolder.fromJson(
            Map<String, dynamic>.from(share as Map),
          ),
        )
        .toList();
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
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final available = <Uri>{};
    final candidates = <Uri>{
      Uri.parse('http://127.0.0.1:8080'),
      Uri.parse('http://localhost:8080'),
      Uri.parse('http://10.0.2.2:8080'), // Android Emulator loopback
    };

    // 1. Try mDNS Discovery
    if (!kIsWeb) {
      final client = MDnsClient(
        rawDatagramSocketFactory: (
          dynamic host,
          int port, {
          bool reuseAddress = true,
          bool reusePort = true,
          int ttl = 1,
        }) {
          return RawDatagramSocket.bind(
            host,
            port,
            reuseAddress: reuseAddress,
            reusePort: !Platform.isAndroid && !Platform.isWindows && reusePort,
            ttl: ttl,
          );
        },
      );
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
      } catch (e) {
        developer.log('mDNS Discovery failed: $e', name: 'karunstream.discovery');
      } finally {
        client.stop();
      }
    }

    // 2. Parallel Subnet Scan (The "Zero-Config" miracle)
    if (!kIsWeb) {
      try {
        final interfaces = await NetworkInterface.list(
          includeLinkLocal: false,
          type: InternetAddressType.IPv4,
        );

        final List<String> subnets = [];
        for (final interface in interfaces) {
          for (final addr in interface.addresses) {
            final address = addr.address;
            if (address.startsWith('127.')) continue;
            final base = address.substring(0, address.lastIndexOf('.') + 1);
            if (!subnets.contains(base)) subnets.add(base);
          }
        }

        for (final base in subnets) {
          // Scan in chunks to avoid overwhelming the socket limit
          const int chunkSize = 32;
          for (int i = 1; i < 255; i += chunkSize) {
            final List<Future<void>> chunkScans = [];
            for (int j = i; j < i + chunkSize && j < 255; j++) {
              final targetIp = '$base$j';
              chunkScans.add(() async {
                final uri = Uri.parse('http://$targetIp:8080');
                try {
                  // Increased timeout to 1 second for more reliable scanning
                  await fetchStatus(uri).timeout(const Duration(milliseconds: 1000));
                  available.add(uri);
                } catch (_) {}
              }());
            }
            await Future.wait(chunkScans);
          }
        }
      } catch (e) {
        developer.log('Subnet scan failed: $e', name: 'karunstream.discovery');
      }
    }

    // 3. Final validation of static candidates (including loopbacks)
    await Future.wait(
      candidates.map((candidate) async {
        try {
          await fetchStatus(candidate)
              .timeout(const Duration(milliseconds: 1000));
          available.add(candidate);
        } catch (_) {}
      }),
    );

    return available.toList();
  }
}

typedef WebSocketConnector = WebSocketChannel Function(Uri uri);
