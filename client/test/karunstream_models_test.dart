import 'package:karunstream/features/karunstream/model/chat_message.dart';
import 'package:karunstream/features/karunstream/model/karun_event.dart';
import 'package:karunstream/features/karunstream/model/karun_peer.dart';
import 'package:karunstream/features/karunstream/model/shared_folder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('KarunPeer parses server peer payload', () {
    final peer = KarunPeer.fromJson({
      'peer_id': 'u1',
      'nickname': 'Sarah',
      'platform': 'iOS',
      'ip': '192.168.1.15',
      'avatar_index': 2,
    });

    expect(peer.peerId, 'u1');
    expect(peer.nickname, 'Sarah');
    expect(peer.platform, 'iOS');
    expect(peer.ip, '192.168.1.15');
    expect(peer.avatarIndex, 2);
  });

  test('ChatMessage round trips shared schema fields', () {
    final message = ChatMessage(
      messageId: 'm1',
      senderId: 'u1',
      receiverId: 'global',
      body: 'Ready to test this stream?',
      timestamp: DateTime.fromMillisecondsSinceEpoch(1718290312000),
    );

    final json = message.toJson();
    final parsed = ChatMessage.fromJson(json);

    expect(json['msg_id'], 'm1');
    expect(parsed.body, 'Ready to test this stream?');
    expect(parsed.receiverId, 'global');
  });

  test('KarunEvent wraps protocol payloads', () {
    final event = KarunEvent.fromJson({
      'event_type': 'HEARTBEAT',
      'payload': {'timestamp': 1718290312},
    });

    expect(event.eventType, 'HEARTBEAT');
    expect(event.payload['timestamp'], 1718290312);
  });

  test('SharedFolder serialization and deserialization works', () {
    final folderJson = {
      'share_id': 's1',
      'peer_id': 'p1',
      'peer_nickname': 'Jane',
      'name': 'Photos',
      'files': [
        {
          'relative_path': 'vacation/sunset.jpg',
          'file_name': 'sunset.jpg',
          'file_size': 102400,
        }
      ]
    };

    final folder = SharedFolder.fromJson(folderJson);
    expect(folder.shareId, 's1');
    expect(folder.peerId, 'p1');
    expect(folder.peerNickname, 'Jane');
    expect(folder.name, 'Photos');
    expect(folder.files.length, 1);
    expect(folder.files[0].relativePath, 'vacation/sunset.jpg');
    expect(folder.files[0].fileName, 'sunset.jpg');
    expect(folder.files[0].fileSize, 102400);

    final roundTrip = folder.toJson();
    expect(roundTrip['share_id'], 's1');
    expect(roundTrip['files'][0]['relative_path'], 'vacation/sunset.jpg');
  });
}
