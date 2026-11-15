import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karunstream/features/karunstream/services/embedded_server.dart';

void main() {
  group('EmbeddedServer', () {
    late EmbeddedServer server;
    late HttpClient httpClient;

    setUp(() async {
      server = EmbeddedServer();
      await server.start(port: 0);
      httpClient = HttpClient();
    });

    tearDown(() async {
      httpClient.close(force: true);
      await server.stop();
    });

    test('GET /api/v1/system/status returns healthy status and capabilities',
        () async {
      final port = server.port;
      expect(port, greaterThan(0));

      final req = await httpClient.getUrl(
        Uri.parse('http://127.0.0.1:$port/api/v1/system/status'),
      );
      final res = await req.close();
      expect(res.statusCode, HttpStatus.ok);

      final bodyStr = await res.transform(utf8.decoder).join();
      final body = jsonDecode(bodyStr) as Map<String, dynamic>;

      expect(body['status'], 'healthy');
      expect(body['version'], '1.0.0');
      expect(body['server_id'], isNotEmpty);
      expect(body['server_uuid'], isNotEmpty);

      final capabilities = List<String>.from(body['capabilities'] as List);
      expect(capabilities, contains('resume'));
      expect(capabilities, contains('chunk_manifest'));
      expect(capabilities, contains('folders'));
      expect(capabilities, contains('tus_upload'));
    });

    test('GET /api/v1/system/pair-payload returns valid pairing details',
        () async {
      final port = server.port;
      final req = await httpClient.getUrl(
        Uri.parse('http://127.0.0.1:$port/api/v1/system/pair-payload'),
      );
      final res = await req.close();
      expect(res.statusCode, HttpStatus.ok);

      final bodyStr = await res.transform(utf8.decoder).join();
      final body = jsonDecode(bodyStr) as Map<String, dynamic>;

      expect(body['port'], port);
      expect(body['host_ip'], '127.0.0.1');
      expect(body['server_name'], server.serverName);
      expect(body['pairing_url'], startsWith('karunstream://pair?'));
    });

    test('WebSocket /ws/orchestrator handles handshake, PEER_LIST, and HEARTBEAT',
        () async {
      final port = server.port;
      final socket = await WebSocket.connect('ws://127.0.0.1:$port/ws/orchestrator');

      final completerPeerList = Completer<Map<String, dynamic>>();
      final completerHeartbeat = Completer<Map<String, dynamic>>();

      final sub = socket.listen((data) {
        final msg = jsonDecode(data as String) as Map<String, dynamic>;
        final eventType = msg['event_type'];
        if (eventType == 'PEER_LIST') {
          if (!completerPeerList.isCompleted) {
            completerPeerList.complete(msg);
          }
        } else if (eventType == 'HEARTBEAT') {
          if (!completerHeartbeat.isCompleted) {
            completerHeartbeat.complete(msg);
          }
        }
      });

      // Send registration handshake
      socket.add(jsonEncode({
        'peer_id': 'test-peer-1',
        'nickname': 'TesterNode',
        'platform': 'dart_test',
      }));

      final peerListEvent = await completerPeerList.future.timeout(
        const Duration(seconds: 3),
      );
      expect(peerListEvent['event_type'], 'PEER_LIST');
      final peers = peerListEvent['payload']['peers'] as List;
      expect(peers.any((p) => p['peer_id'] == 'test-peer-1'), isTrue);

      // Send HEARTBEAT
      socket.add(jsonEncode({
        'event_type': 'HEARTBEAT',
        'payload': {'ping': 12345},
      }));

      final heartbeatEvent = await completerHeartbeat.future.timeout(
        const Duration(seconds: 3),
      );
      expect(heartbeatEvent['event_type'], 'HEARTBEAT');
      expect(heartbeatEvent['payload']['ping'], 12345);

      await sub.cancel();
      await socket.close();
    });

    test('Resumable upload (POST, HEAD, PATCH) and range download work end-to-end',
        () async {
      final port = server.port;

      // 1. POST /api/v1/transfers
      final initReq = await httpClient.postUrl(
        Uri.parse('http://127.0.0.1:$port/api/v1/transfers'),
      );
      initReq.headers.contentType = ContentType.json;
      initReq.write(jsonEncode({
        'transfer_id': '33333333-3333-3333-3333-333333333333',
        'sender_id': 'sender_1',
        'recipient_id': 'recipient_1',
        'file_name': 'sample.txt',
        'total_bytes': 15,
        'chunk_size': 1024,
      }));
      final initRes = await initReq.close();
      expect(initRes.statusCode, HttpStatus.created);

      final initBodyStr = await initRes.transform(utf8.decoder).join();
      final initBody = jsonDecode(initBodyStr) as Map<String, dynamic>;
      final transferId = initBody['transfer_id'] as String;
      expect(transferId, '33333333-3333-3333-3333-333333333333');
      expect(initBody['upload_offset'], 0);

      // 2. HEAD /api/v1/transfers/{id}/upload (check offset 0)
      final headReq = await httpClient.headUrl(
        Uri.parse('http://127.0.0.1:$port/api/v1/transfers/$transferId/upload'),
      );
      final headRes = await headReq.close();
      expect(headRes.statusCode, HttpStatus.ok);
      expect(headRes.headers.value('Upload-Offset'), '0');
      expect(headRes.headers.value('Upload-Length'), '15');
      expect(headRes.headers.value('Tus-Resumable'), '1.0.0');

      // 3. PATCH first chunk (offset 0, 7 bytes: "Hello, ")
      final patchReq1 = await httpClient.patchUrl(
        Uri.parse('http://127.0.0.1:$port/api/v1/transfers/$transferId/upload'),
      );
      patchReq1.headers.set('Upload-Offset', '0');
      patchReq1.write('Hello, ');
      final patchRes1 = await patchReq1.close();
      expect(patchRes1.statusCode, HttpStatus.noContent);
      expect(patchRes1.headers.value('Upload-Offset'), '7');

      // Verify offset via HEAD
      final headReq2 = await httpClient.headUrl(
        Uri.parse('http://127.0.0.1:$port/api/v1/transfers/$transferId/upload'),
      );
      final headRes2 = await headReq2.close();
      expect(headRes2.headers.value('Upload-Offset'), '7');

      // 4. Test conflict on wrong offset
      final badPatch = await httpClient.patchUrl(
        Uri.parse('http://127.0.0.1:$port/api/v1/transfers/$transferId/upload'),
      );
      badPatch.headers.set('Upload-Offset', '0'); // Expected 7
      badPatch.write('Wrong');
      final badRes = await badPatch.close();
      expect(badRes.statusCode, HttpStatus.conflict);

      // 5. PATCH second chunk (offset 7, 8 bytes: "Flutter!") -> Total 15 bytes
      final patchReq2 = await httpClient.patchUrl(
        Uri.parse('http://127.0.0.1:$port/api/v1/transfers/$transferId/upload'),
      );
      patchReq2.headers.set('Upload-Offset', '7');
      patchReq2.write('Flutter!');
      final patchRes2 = await patchReq2.close();
      expect(patchRes2.statusCode, HttpStatus.noContent);
      expect(patchRes2.headers.value('Upload-Offset'), '15');

      // 6. Resumable download: GET /api/v1/files/{id}/download with Range bytes=0-4
      // "Hello" is bytes 0..4
      final getRangeReq = await httpClient.getUrl(
        Uri.parse('http://127.0.0.1:$port/api/v1/files/$transferId/download'),
      );
      getRangeReq.headers.set('Range', 'bytes=0-4');
      final getRangeRes = await getRangeReq.close();

      expect(getRangeRes.statusCode, HttpStatus.partialContent);
      expect(getRangeRes.headers.value('Accept-Ranges'), 'bytes');
      expect(getRangeRes.headers.value('Content-Range'), 'bytes 0-4/15');
      final rangeBytes = await getRangeRes.fold<List<int>>(
        <int>[],
        (prev, elem) => prev..addAll(elem),
      );
      expect(utf8.decode(rangeBytes), 'Hello');

      // 7. Full download without Range header
      final getFullReq = await httpClient.getUrl(
        Uri.parse('http://127.0.0.1:$port/api/v1/files/$transferId/download'),
      );
      final getFullRes = await getFullReq.close();
      expect(getFullRes.statusCode, HttpStatus.ok);
      final fullBytes = await getFullRes.fold<List<int>>(
        <int>[],
        (prev, elem) => prev..addAll(elem),
      );
      expect(utf8.decode(fullBytes), 'Hello, Flutter!');
    });
  });
}
