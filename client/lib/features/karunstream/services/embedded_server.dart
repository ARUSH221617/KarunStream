import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Lightweight embedded HTTP and WebSocket server for KarunStream host mode.
///
/// Runs directly inside the Flutter app without requiring an external Python daemon.
class EmbeddedServer {
  HttpServer? _server;
  final String _serverUuid = const Uuid().v4();
  final String _serverName = 'KarunStream Embedded';
  late String _storageDir;
  bool _isCustomStorageDir = false;
  String _hostIp = '127.0.0.1';

  final Map<String, Map<String, dynamic>> _peers = {};
  final Map<String, WebSocket> _sockets = {};
  final Map<String, Map<String, dynamic>> _transfers = {};

  bool get isRunning => _server != null;
  int get port => _server?.port ?? 0;
  String get serverUuid => _serverUuid;
  String get serverName => _serverName;
  String get storageDir => _storageDir;
  Map<String, Map<String, dynamic>> get peers => Map.unmodifiable(_peers);
  Map<String, WebSocket> get sockets => Map.unmodifiable(_sockets);
  Map<String, Map<String, dynamic>> get transfers => Map.unmodifiable(_transfers);

  /// Start the embedded HTTP and WebSocket server.
  Future<void> start({
    int port = 0,
    String? hostIp,
    String? storageDir,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('EmbeddedServer is not supported on web');
    }

    await stop();

    _hostIp = hostIp ?? '127.0.0.1';

    if (storageDir != null) {
      _storageDir = storageDir;
      _isCustomStorageDir = true;
    } else {
      final temp = await Directory.systemTemp.createTemp('karunstream_server_');
      _storageDir = temp.path;
      _isCustomStorageDir = false;
    }
    await Directory(_storageDir).create(recursive: true);

    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_handleHttpRequest);
  }

  /// Stop the embedded server and close all active connections.
  Future<void> stop() async {
    if (kIsWeb) return;

    for (final socket in _sockets.values) {
      try {
        await socket.close(1000, 'Server stopping');
      } catch (_) {}
    }
    _sockets.clear();
    _peers.clear();
    _transfers.clear();

    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
    }

    if (!_isCustomStorageDir) {
      try {
        final dir = Directory(_storageDir);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  Future<void> _handleHttpRequest(HttpRequest request) async {
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add(
      'Access-Control-Allow-Methods',
      'GET, POST, PATCH, HEAD, DELETE, OPTIONS',
    );
    request.response.headers.add('Access-Control-Allow-Headers', '*');
    request.response.headers.add(
      'Access-Control-Expose-Headers',
      'Upload-Offset, Upload-Length, Tus-Resumable, Content-Range, ETag',
    );

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    final path = request.uri.path;
    final method = request.method;

    try {
      if (path == '/ws/orchestrator') {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final socket = await WebSocketTransformer.upgrade(request);
          _handleWebSocketClient(socket, request);
        } else {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
        }
        return;
      }

      if (method == 'GET' &&
          (path == '/api/v1/system/status' || path == '/system/status')) {
        await _handleSystemStatus(request);
        return;
      }

      if (method == 'GET' &&
          (path == '/api/v1/system/pair-payload' ||
              path == '/system/pair-payload')) {
        await _handlePairPayload(request);
        return;
      }

      if (method == 'POST' && path == '/api/v1/transfers') {
        await _handleTransferInit(request);
        return;
      }

      if (path.startsWith('/api/v1/transfers/') && path.endsWith('/upload')) {
        final segments = request.uri.pathSegments;
        final transferId = segments.length >= 2 ? segments[segments.length - 2] : '';
        if (method == 'HEAD') {
          await _handleTransferHead(request, transferId);
          return;
        } else if (method == 'PATCH') {
          await _handleTransferPatch(request, transferId);
          return;
        }
      }

      if (method == 'GET' &&
          path.startsWith('/api/v1/files/') &&
          path.endsWith('/download')) {
        final segments = request.uri.pathSegments;
        final fileId = segments.length >= 2 ? segments[segments.length - 2] : '';
        await _handleFileDownload(request, fileId);
        return;
      }

      if (method == 'GET' && path == '/api/v1/files') {
        await _handleListFiles(request);
        return;
      }

      if (method == 'GET' && path == '/api/v1/peers') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'peers': _peers.values.toList()}));
        await request.response.close();
        return;
      }

      if (method == 'GET' && path == '/api/v1/shares') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'shares': []}));
        await request.response.close();
        return;
      }

      if (method == 'GET' && path == '/api/v1/conversations') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'conversations': []}));
        await request.response.close();
        return;
      }

      if (method == 'GET' &&
          path.startsWith('/api/v1/conversations/') &&
          path.endsWith('/messages')) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'messages': []}));
        await request.response.close();
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } catch (e) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write(e.toString());
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _handleSystemStatus(HttpRequest request) async {
    final statusJson = {
      'name': _serverName,
      'version': '1.0.0',
      'status': 'healthy',
      'server_id': _serverUuid,
      'server_uuid': _serverUuid,
      'active_peers': _peers.length,
      'peer_count': _peers.length,
      'capabilities': ['resume', 'chunk_manifest', 'folders', 'tus_upload'],
    };
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(statusJson));
    await request.response.close();
  }

  Future<void> _handlePairPayload(HttpRequest request) async {
    final pairingUrl =
        'karunstream://pair?v=1&ip=$_hostIp&port=$port&name=${Uri.encodeComponent(_serverName)}';
    final payload = {
      'pairing_url': pairingUrl,
      'host_ip': _hostIp,
      'port': port,
      'auth_token': null,
      'tls_fingerprint': null,
      'wifi_qr': null,
      'server_name': _serverName,
    };
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(payload));
    await request.response.close();
  }

  Future<void> _handleTransferInit(HttpRequest request) async {
    final bodyBytes = await request.fold<List<int>>(
      <int>[],
      (prev, element) => prev..addAll(element),
    );
    final bodyStr = utf8.decode(bodyBytes);
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(bodyStr) as Map<String, dynamic>;
    } catch (_) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final transferId = json['transfer_id'] as String? ?? const Uuid().v4();
    final totalBytes = json['total_bytes'] as int? ?? 0;
    final fileName = json['file_name'] as String? ?? 'upload.bin';
    final chunkSize = json['chunk_size'] as int? ?? 1048576;
    final senderId = json['sender_id'] as String? ?? '';
    final recipientId = json['recipient_id'] as String? ?? '';

    final partFile = File(p.join(_storageDir, '$transferId.part'));
    await partFile.create(recursive: true);

    _transfers[transferId] = {
      'transfer_id': transferId,
      'sender_id': senderId,
      'recipient_id': recipientId,
      'file_name': fileName,
      'total_bytes': totalBytes,
      'committed_bytes': 0,
      'chunk_size': chunkSize,
      'status': 'INIT',
      'temp_path': partFile.path,
      'stored_path': null,
      'sha256': null,
    };

    request.response
      ..statusCode = HttpStatus.created
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'transfer_id': transferId,
        'upload_url': '/api/v1/transfers/$transferId/upload',
        'upload_offset': 0,
        'chunk_size': chunkSize,
      }));
    await request.response.close();
  }

  Future<void> _handleTransferHead(
    HttpRequest request,
    String transferId,
  ) async {
    final transfer = _transfers[transferId];
    if (transfer == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final committed = transfer['committed_bytes'] as int? ?? 0;
    final total = transfer['total_bytes'] as int? ?? 0;

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.set('Upload-Offset', committed.toString())
      ..headers.set('Upload-Length', total.toString())
      ..headers.set('Tus-Resumable', '1.0.0')
      ..headers.set('Cache-Control', 'no-store');
    await request.response.close();
  }

  Future<void> _handleTransferPatch(
    HttpRequest request,
    String transferId,
  ) async {
    final transfer = _transfers[transferId];
    if (transfer == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final offsetHeader = request.headers.value('Upload-Offset');
    if (offsetHeader == null) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    final uploadOffset = int.tryParse(offsetHeader);
    if (uploadOffset == null || uploadOffset < 0) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final committed = transfer['committed_bytes'] as int? ?? 0;
    final total = transfer['total_bytes'] as int? ?? 0;

    if (transfer['status'] == 'COMPLETED') {
      request.response
        ..statusCode = HttpStatus.noContent
        ..headers.set('Upload-Offset', total.toString())
        ..headers.set('Tus-Resumable', '1.0.0');
      await request.response.close();
      return;
    }

    if (uploadOffset != committed) {
      request.response
        ..statusCode = HttpStatus.conflict
        ..headers.set('Upload-Offset', committed.toString())
        ..headers.set('Tus-Resumable', '1.0.0')
        ..write('Upload-Offset conflict');
      await request.response.close();
      return;
    }

    final partFile = File(transfer['temp_path'] as String);
    if (await partFile.exists()) {
      final fileLen = await partFile.length();
      if (fileLen > uploadOffset) {
        final existingBytes = await partFile.readAsBytes();
        await partFile.writeAsBytes(existingBytes.sublist(0, uploadOffset));
      }
    } else {
      await partFile.create(recursive: true);
    }

    final sink = partFile.openWrite(mode: FileMode.append);
    var currentOffset = uploadOffset;
    await for (final chunk in request) {
      sink.add(chunk);
      currentOffset += chunk.length;
    }
    await sink.flush();
    await sink.close();

    transfer['committed_bytes'] = currentOffset;

    if (currentOffset >= total) {
      transfer['status'] = 'COMPLETED';
      final bytes = await partFile.readAsBytes();
      final hash = sha256.convert(bytes).toString();
      transfer['sha256'] = hash;

      final fileName = transfer['file_name'] as String? ?? 'upload.bin';
      final destFile = File(p.join(_storageDir, '${transferId}_$fileName'));
      if (await destFile.exists()) {
        await destFile.delete();
      }
      await partFile.rename(destFile.path);
      transfer['stored_path'] = destFile.path;

      final offerPayload = {
        'transfer_id': transferId,
        'sender_id': transfer['sender_id'],
        'receiver_id': transfer['recipient_id'],
        'file_name': fileName,
        'file_size': total,
        'sha256': hash,
        'download_url': '/api/v1/files/$transferId/download',
      };
      final recipientId = transfer['recipient_id'] as String?;
      if (recipientId != null &&
          recipientId.isNotEmpty &&
          recipientId != 'global') {
        final clientSocket = _sockets[recipientId];
        if (clientSocket != null) {
          _sendWsEvent(clientSocket, 'FILE_OFFER', offerPayload);
        }
      } else {
        _broadcastWsEvent('FILE_OFFER', offerPayload);
      }
    } else {
      transfer['status'] = 'ACTIVE';
    }

    request.response
      ..statusCode = HttpStatus.noContent
      ..headers.set('Upload-Offset', currentOffset.toString())
      ..headers.set('Tus-Resumable', '1.0.0');
    await request.response.close();
  }

  Future<void> _handleFileDownload(
    HttpRequest request,
    String fileId,
  ) async {
    final transfer = _transfers[fileId];
    String? filePath = transfer?['stored_path'] as String?;
    File? file;
    if (filePath != null) {
      file = File(filePath);
    }

    if (file == null || !await file.exists()) {
      final candidate = File(p.join(_storageDir, fileId));
      if (await candidate.exists()) {
        file = candidate;
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
    }

    final total = await file.length();
    final mtime = (await file.lastModified()).millisecondsSinceEpoch ~/ 1000;
    final etag = 'W/"$total-$mtime"';

    final range = request.headers.value('Range');
    if (range != null && range.startsWith('bytes=')) {
      final rangeSpec = range.substring(6).trim();
      final parts = rangeSpec.split('-');
      final start = int.tryParse(parts[0]) ?? 0;
      final end = (parts.length > 1 && parts[1].isNotEmpty)
          ? int.tryParse(parts[1]) ?? (total - 1)
          : total - 1;
      final actualEnd = end >= total ? total - 1 : end;

      if (start > actualEnd || start < 0) {
        request.response
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..headers.set('Content-Range', 'bytes */$total');
        await request.response.close();
        return;
      }

      final sliceLength = actualEnd - start + 1;
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set('Accept-Ranges', 'bytes')
        ..headers.set('Content-Range', 'bytes $start-$actualEnd/$total')
        ..headers.set('Content-Length', sliceLength.toString())
        ..headers.set('ETag', etag)
        ..headers.contentType = ContentType.binary;

      await request.response.addStream(file.openRead(start, actualEnd + 1));
      await request.response.close();
    } else {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.set('Accept-Ranges', 'bytes')
        ..headers.set('Content-Length', total.toString())
        ..headers.set('ETag', etag)
        ..headers.contentType = ContentType.binary;

      await request.response.addStream(file.openRead());
      await request.response.close();
    }
  }

  Future<void> _handleListFiles(HttpRequest request) async {
    final files = _transfers.values
        .where((t) => t['status'] == 'COMPLETED')
        .map((t) => {
              'transfer_id': t['transfer_id'],
              'sender_id': t['sender_id'],
              'recipient_id': t['recipient_id'],
              'file_name': t['file_name'],
              'file_bytes': t['total_bytes'],
              'sha256': t['sha256'],
              'download_url': '/api/v1/files/${t['transfer_id']}/download',
              'created_at': DateTime.now().toIso8601String(),
            })
        .toList();

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'files': files}));
    await request.response.close();
  }

  void _handleWebSocketClient(WebSocket socket, HttpRequest request) {
    bool isHandshakeComplete = false;
    String? registeredPeerId;

    final handshakeCompleter = Completer<dynamic>();
    final timer = Timer(const Duration(milliseconds: 2000), () {
      if (!handshakeCompleter.isCompleted) {
        handshakeCompleter.completeError(
          TimeoutException(
            'Handshake timeout: first frame registration expected within 2.0s',
          ),
        );
      }
    });

    socket.listen(
      (message) {
        if (!isHandshakeComplete) {
          if (!handshakeCompleter.isCompleted) {
            handshakeCompleter.complete(message);
          }
          return;
        }

        if (registeredPeerId != null) {
          _onSocketMessage(registeredPeerId!, message);
        }
      },
      onError: (err) {
        if (!handshakeCompleter.isCompleted) {
          handshakeCompleter.completeError(err);
        }
        if (registeredPeerId != null) {
          _unregisterPeer(registeredPeerId!);
        }
      },
      onDone: () {
        if (!handshakeCompleter.isCompleted) {
          handshakeCompleter.completeError(
            Exception('Socket closed during handshake'),
          );
        }
        if (registeredPeerId != null) {
          _unregisterPeer(registeredPeerId!);
        }
      },
    );

    () async {
      try {
        final dynamic rawFirst = await handshakeCompleter.future;
        timer.cancel();

        final Map<String, dynamic> regData;
        if (rawFirst is String) {
          final decoded = jsonDecode(rawFirst);
          if (decoded is Map<String, dynamic>) {
            if (decoded.containsKey('payload') &&
                decoded['payload'] is Map<String, dynamic>) {
              regData = Map<String, dynamic>.from(decoded['payload'] as Map);
            } else {
              regData = decoded;
            }
          } else {
            throw const FormatException('Invalid registration JSON');
          }
        } else {
          throw const FormatException('Binary first frame not supported');
        }

        final peerId = regData['peer_id'] as String? ?? const Uuid().v4();
        registeredPeerId = peerId;
        final peer = <String, dynamic>{
          'peer_id': peerId,
          'nickname': regData['nickname'] as String? ?? 'Anonymous',
          'platform': regData['platform'] as String? ?? 'unknown',
          'ip': request.connectionInfo?.remoteAddress.address ?? '127.0.0.1',
        };

        _peers[peerId] = peer;
        _sockets[peerId] = socket;

        // Broadcast PEER_JOIN to other peers
        _broadcastWsEvent(
          'PEER_JOIN',
          peer,
          excludePeerId: peerId,
        );

        // Reply to connecting peer with PEER_LIST
        _sendWsEvent(
          socket,
          'PEER_LIST',
          {'peers': _peers.values.toList()},
        );

        isHandshakeComplete = true;
      } catch (_) {
        timer.cancel();
        if (registeredPeerId != null) {
          _unregisterPeer(registeredPeerId!);
        }
        try {
          await socket.close(1008, 'Handshake failed');
        } catch (_) {}
      }
    }();
  }

  void _onSocketMessage(String senderId, dynamic message) {
    if (message is! String) return;
    try {
      final data = jsonDecode(message);
      if (data is! Map<String, dynamic>) return;
      final eventType = data['event_type'] as String? ?? '';
      final payload = Map<String, dynamic>.from(data['payload'] as Map? ?? {});

      switch (eventType) {
        case 'HEARTBEAT':
          final socket = _sockets[senderId];
          if (socket != null) {
            _sendWsEvent(
              socket,
              'HEARTBEAT',
              payload.isNotEmpty
                  ? payload
                  : {'timestamp': DateTime.now().millisecondsSinceEpoch},
            );
          }
          break;
        case 'CHAT_MESSAGE':
          final receiverId = payload['receiver_id'] as String?;
          if (receiverId != null &&
              receiverId != 'global' &&
              receiverId.isNotEmpty) {
            final destSocket = _sockets[receiverId];
            if (destSocket != null) {
              _sendWsEvent(destSocket, 'CHAT_MESSAGE', payload);
            } else {
              final senderSocket = _sockets[senderId];
              if (senderSocket != null) {
                _sendWsEvent(senderSocket, 'ERROR', {
                  'message': 'Recipient is not connected',
                });
              }
            }
          } else {
            _broadcastWsEvent(
              'CHAT_MESSAGE',
              payload,
              excludePeerId: senderId,
            );
          }
          break;
        case 'FILE_OFFER':
          final receiverId = payload['receiver_id'] as String?;
          if (receiverId != null &&
              receiverId != 'global' &&
              receiverId.isNotEmpty) {
            final destSocket = _sockets[receiverId];
            if (destSocket != null) {
              _sendWsEvent(destSocket, 'FILE_OFFER', payload);
            } else {
              final senderSocket = _sockets[senderId];
              if (senderSocket != null) {
                _sendWsEvent(senderSocket, 'ERROR', {
                  'message': 'Recipient is not connected',
                });
              }
            }
          } else {
            _broadcastWsEvent(
              'FILE_OFFER',
              payload,
              excludePeerId: senderId,
            );
          }
          break;
        default:
          final recipientId =
              payload['receiver_id'] ?? payload['recipient_id'];
          if (recipientId is String &&
              recipientId.isNotEmpty &&
              recipientId != 'global') {
            final destSocket = _sockets[recipientId];
            if (destSocket != null) {
              _sendWsEvent(destSocket, eventType, payload);
            }
          } else {
            _broadcastWsEvent(
              eventType,
              payload,
              excludePeerId: senderId,
            );
          }
          break;
      }
    } catch (_) {}
  }

  void _unregisterPeer(String peerId) {
    final removed = _peers.remove(peerId);
    _sockets.remove(peerId);
    if (removed != null) {
      _broadcastWsEvent('PEER_LEAVE', {'peer_id': peerId});
    }
  }

  void _sendWsEvent(WebSocket socket, String eventType, Map<String, dynamic> payload) {
    try {
      socket.add(jsonEncode({
        'event_type': eventType,
        'payload': payload,
      }));
    } catch (_) {}
  }

  void _broadcastWsEvent(
    String eventType,
    Map<String, dynamic> payload, {
    String? excludePeerId,
  }) {
    final msg = jsonEncode({
      'event_type': eventType,
      'payload': payload,
    });
    for (final entry in _sockets.entries) {
      if (entry.key != excludePeerId) {
        try {
          entry.value.add(msg);
        } catch (_) {}
      }
    }
  }
}
