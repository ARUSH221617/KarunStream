import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../model/chat_message.dart';
import '../model/karun_event.dart';
import '../model/karun_peer.dart';
import '../model/server_status.dart';
import '../repository/lan_server_repository.dart';

final lanServerRepositoryProvider = Provider<LanServerRepository>((ref) {
  return LanServerRepository();
});

final lanWorkspaceProvider =
    NotifierProvider<LanWorkspaceController, LanWorkspaceState>(
  LanWorkspaceController.new,
);

class LanWorkspaceState {
  const LanWorkspaceState({
    required this.peerId,
    this.nickname = 'KarunStream User',
    this.serverUri,
    this.status,
    this.peers = const [],
    this.messages = const [],
    this.isConnecting = false,
    this.isConnected = false,
    this.error,
  });

  final String peerId;
  final String nickname;
  final Uri? serverUri;
  final ServerStatus? status;
  final List<KarunPeer> peers;
  final List<ChatMessage> messages;
  final bool isConnecting;
  final bool isConnected;
  final String? error;

  LanWorkspaceState copyWith({
    String? nickname,
    Uri? serverUri,
    ServerStatus? status,
    List<KarunPeer>? peers,
    List<ChatMessage>? messages,
    bool? isConnecting,
    bool? isConnected,
    String? error,
    bool clearError = false,
  }) {
    return LanWorkspaceState(
      peerId: peerId,
      nickname: nickname ?? this.nickname,
      serverUri: serverUri ?? this.serverUri,
      status: status ?? this.status,
      peers: peers ?? this.peers,
      messages: messages ?? this.messages,
      isConnecting: isConnecting ?? this.isConnecting,
      isConnected: isConnected ?? this.isConnected,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class LanWorkspaceController extends Notifier<LanWorkspaceState> {
  WebSocketChannel? _channel;
  StreamSubscription<KarunEvent>? _eventsSubscription;
  Timer? _heartbeatTimer;

  LanServerRepository get _repository => ref.read(lanServerRepositoryProvider);

  @override
  LanWorkspaceState build() {
    ref.onDispose(() {
      _heartbeatTimer?.cancel();
      _eventsSubscription?.cancel();
      _channel?.sink.close();
    });
    return LanWorkspaceState(peerId: const Uuid().v4());
  }

  Future<void> autoDiscoverAndConnect() async {
    state = state.copyWith(isConnecting: true, clearError: true);
    final servers = await _repository.discoverServers();
    if (servers.isEmpty) {
      state = state.copyWith(
        isConnecting: false,
        error:
            'No LAN server found. Start Docker server or enter an IP manually.',
      );
      return;
    }
    await connect(servers.first);
  }

  Future<void> connect(Uri serverUri) async {
    state = state.copyWith(
      isConnecting: true,
      serverUri: serverUri,
      clearError: true,
    );
    try {
      await _eventsSubscription?.cancel();
      await _channel?.sink.close();

      final status = await _repository.fetchStatus(serverUri);
      final registration = {
        'peer_id': state.peerId,
        'nickname': state.nickname,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      };
      final channel = _repository.connectSocket(serverUri, registration);
      _channel = channel;
      _eventsSubscription = _repository.events(channel).listen(
            _handleEvent,
            onError: (Object error) => state = state.copyWith(
              isConnected: false,
              error: 'Socket error: $error',
            ),
            onDone: () => state = state.copyWith(isConnected: false),
          );
      _startHeartbeat();
      state = state.copyWith(
        status: status,
        isConnecting: false,
        isConnected: true,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        isConnecting: false,
        isConnected: false,
        error: 'Connection failed: $error',
      );
    }
  }

  void disconnect() {
    _heartbeatTimer?.cancel();
    _eventsSubscription?.cancel();
    _channel?.sink.close();
    state = state.copyWith(
      isConnected: false,
      isConnecting: false,
      status: null,
      peers: [],
    );
  }

  void sendChat(String body) {
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty || _channel == null) {
      return;
    }
    final message = ChatMessage(
      messageId: const Uuid().v4(),
      senderId: state.peerId,
      receiverId: 'global',
      body: trimmedBody,
      timestamp: DateTime.now(),
    );
    _sendEvent('CHAT_MESSAGE', message.toJson());
  }

  void updateNickname(String nickname) {
    final trimmedNickname = nickname.trim();
    if (trimmedNickname.isNotEmpty) {
      state = state.copyWith(nickname: trimmedNickname);
    }
  }

  void _handleEvent(KarunEvent event) {
    switch (event.eventType) {
      case 'PEER_LIST':
        final peers = event.payload['peers'] as List? ?? const [];
        state = state.copyWith(
          peers: peers
              .map(
                (peer) => KarunPeer.fromJson(
                  Map<String, dynamic>.from(peer as Map),
                ),
              )
              .toList(),
        );
        break;
      case 'PEER_JOIN':
        final joinedPeer = KarunPeer.fromJson(event.payload);
        state = state.copyWith(peers: {...state.peers, joinedPeer}.toList());
        break;
      case 'PEER_LEAVE':
        final peerId = event.payload['peer_id'] as String?;
        state = state.copyWith(
          peers: state.peers.where((peer) => peer.peerId != peerId).toList(),
        );
        break;
      case 'CHAT_MESSAGE':
        state = state.copyWith(
          messages: [
            ...state.messages,
            ChatMessage.fromJson(event.payload),
          ],
        );
        break;
      case 'ERROR':
        state = state.copyWith(error: event.payload['message'] as String?);
        break;
    }
  }

  void _sendEvent(String eventType, Map<String, dynamic> payload) {
    _channel?.sink.add(jsonEncode({
      'event_type': eventType,
      'payload': payload,
    }));
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _sendEvent('HEARTBEAT', {
        'timestamp': DateTime.now().millisecondsSinceEpoch / 1000,
      });
    });
  }
}
