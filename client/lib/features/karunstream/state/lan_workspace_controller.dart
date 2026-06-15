import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../model/chat_message.dart';
import '../model/file_offer.dart';
import '../model/file_transfer.dart';
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
    this.fileOffers = const [],
    this.files = const [],
    this.transferProgress = 0,
    this.isTransferring = false,
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
  final List<FileOffer> fileOffers;
  final List<FileTransfer> files;
  final double transferProgress;
  final bool isTransferring;
  final bool isConnecting;
  final bool isConnected;
  final String? error;

  LanWorkspaceState copyWith({
    String? nickname,
    Uri? serverUri,
    ServerStatus? status,
    List<KarunPeer>? peers,
    List<ChatMessage>? messages,
    List<FileOffer>? fileOffers,
    List<FileTransfer>? files,
    double? transferProgress,
    bool? isTransferring,
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
      fileOffers: fileOffers ?? this.fileOffers,
      files: files ?? this.files,
      transferProgress: transferProgress ?? this.transferProgress,
      isTransferring: isTransferring ?? this.isTransferring,
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

  Future<void> uploadAndOfferFile({
    required String fileName,
    String? filePath,
    Uint8List? bytes,
    String recipientId = 'global',
  }) async {
    final serverUri = state.serverUri;
    if (!state.isConnected || serverUri == null) {
      state = state.copyWith(error: 'Connect to a LAN server before sharing files.');
      return;
    }
    if (filePath == null && bytes == null) {
      state = state.copyWith(error: 'Select a readable file before sharing.');
      return;
    }

    state = state.copyWith(
      isTransferring: true,
      transferProgress: 0,
      clearError: true,
    );

    try {
      final transfer = await _repository.uploadFile(
        serverUri: serverUri,
        fileName: fileName,
        filePath: filePath,
        bytes: bytes,
        senderId: state.peerId,
        recipientId: recipientId,
        onSendProgress: (sent, total) {
          if (total > 0) {
            state = state.copyWith(transferProgress: sent / total);
          }
        },
      );
      final offer = FileOffer(
        transferId: transfer.transferId,
        senderId: transfer.senderId,
        receiverId: recipientId == 'global' ? null : recipientId,
        fileName: transfer.fileName,
        fileSize: transfer.bytes,
        sha256: transfer.sha256,
        downloadUrl: transfer.downloadUrl,
      );
      _sendEvent('FILE_OFFER', offer.toJson());
      state = state.copyWith(
        files: [transfer, ...state.files],
        fileOffers: [offer, ...state.fileOffers],
        transferProgress: 1,
        isTransferring: false,
      );
    } catch (error) {
      state = state.copyWith(
        isTransferring: false,
        error: 'File upload failed: $error',
      );
    }
  }

  Future<void> refreshFiles() async {
    final serverUri = state.serverUri;
    if (serverUri == null) {
      return;
    }
    try {
      final files = await _repository.fetchFiles(serverUri, peerId: state.peerId);
      state = state.copyWith(files: files, clearError: true);
    } catch (error) {
      state = state.copyWith(error: 'Could not refresh files: $error');
    }
  }

  Future<bool> downloadFile({
    required String transferId,
    required String savePath,
  }) async {
    final serverUri = state.serverUri;
    if (serverUri == null) {
      state = state.copyWith(error: 'Connect to a LAN server before downloading files.');
      return false;
    }

    state = state.copyWith(
      isTransferring: true,
      transferProgress: 0,
      clearError: true,
    );
    try {
      await _repository.downloadFile(
        serverUri: serverUri,
        transferId: transferId,
        savePath: savePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            state = state.copyWith(transferProgress: received / total);
          }
        },
      );
      state = state.copyWith(
        isTransferring: false,
        transferProgress: 1,
        clearError: true,
      );
      return true;
    } catch (error) {
      state = state.copyWith(
        isTransferring: false,
        error: 'File download failed: $error',
      );
      return false;
    }
  }

  Future<void> deleteUploadedFile(String transferId) async {
    final serverUri = state.serverUri;
    if (serverUri == null) {
      state = state.copyWith(error: 'Connect to a LAN server before deleting files.');
      return;
    }

    try {
      await _repository.deleteFile(
        serverUri: serverUri,
        transferId: transferId,
        peerId: state.peerId,
      );
      state = state.copyWith(
        files: state.files
            .where((file) => file.transferId != transferId)
            .toList(),
        fileOffers: state.fileOffers
            .where((offer) => offer.transferId != transferId)
            .toList(),
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(error: 'File delete failed: $error');
    }
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
      case 'FILE_OFFER':
        state = state.copyWith(
          fileOffers: [
            FileOffer.fromJson(event.payload),
            ...state.fileOffers,
          ],
        );
        refreshFiles();
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
