import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../model/chat_message.dart';
import '../model/file_offer.dart';
import '../model/file_transfer.dart';
import '../model/karun_event.dart';
import '../model/karun_peer.dart';
import '../model/server_status.dart';
import '../model/shared_folder.dart';
import '../repository/lan_server_repository.dart';
import '../../../constants/constants.dart';
import '../../../utils/utils.dart';
import '../../profile/ui/view_model/profile_view_model.dart';

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
    this.editingMessage,
    Set<String>? deletedFileIds,
    this.transferProgress = 0,
    this.transferSpeed = '0 B/s',
    this.transferAverageSpeed = '0 B/s',
    this.isTransferring = false,
    this.isConnecting = false,
    this.isConnected = false,
    this.error,
    this.sharedFolders = const [],
    this.localShares = const {},
  }) : _deletedFileIds = deletedFileIds;

  final String peerId;
  final String nickname;
  final Uri? serverUri;
  final ServerStatus? status;
  final List<KarunPeer> peers;
  final List<ChatMessage> messages;
  final List<FileOffer> fileOffers;
  final List<FileTransfer> files;
  final ChatMessage? editingMessage;
  final Set<String>? _deletedFileIds;
  final double transferProgress;
  final String transferSpeed;
  final String transferAverageSpeed;
  final bool isTransferring;
  final bool isConnecting;
  final bool isConnected;
  final String? error;
  final List<SharedFolder> sharedFolders;
  final Map<String, String> localShares;

  Set<String> get deletedFileIds => _deletedFileIds ?? const {};

  LanWorkspaceState copyWith({
    String? nickname,
    Uri? serverUri,
    ServerStatus? status,
    List<KarunPeer>? peers,
    List<ChatMessage>? messages,
    List<FileOffer>? fileOffers,
    List<FileTransfer>? files,
    ChatMessage? editingMessage,
    Set<String>? deletedFileIds,
    double? transferProgress,
    String? transferSpeed,
    String? transferAverageSpeed,
    bool? isTransferring,
    bool? isConnecting,
    bool? isConnected,
    String? error,
    List<SharedFolder>? sharedFolders,
    Map<String, String>? localShares,
    bool clearError = false,
    bool clearEditingMessage = false,
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
      editingMessage: clearEditingMessage ? null : editingMessage ?? this.editingMessage,
      deletedFileIds: deletedFileIds ?? this.deletedFileIds,
      transferProgress: transferProgress ?? this.transferProgress,
      transferSpeed: transferSpeed ?? this.transferSpeed,
      transferAverageSpeed: transferAverageSpeed ?? this.transferAverageSpeed,
      isTransferring: isTransferring ?? this.isTransferring,
      isConnecting: isConnecting ?? this.isConnecting,
      isConnected: isConnected ?? this.isConnected,
      error: clearError ? null : error ?? this.error,
      sharedFolders: sharedFolders ?? this.sharedFolders,
      localShares: localShares ?? this.localShares,
    );
  }
}

class LanWorkspaceController extends Notifier<LanWorkspaceState> {
  WebSocketChannel? _channel;
  StreamSubscription<KarunEvent>? _eventsSubscription;
  Timer? _heartbeatTimer;
  int _lastTransferredBytes = 0;
  DateTime? _lastSpeedUpdateTime;
  DateTime? _transferStartTime;
  final Map<String, Completer<String>> _pendingDownloadRequests = {};
  final Map<String, StreamSubscription<FileSystemEvent>> _folderSubscriptions = {};
  final Map<String, Timer> _debounceTimers = {};

  LanServerRepository get _repository => ref.read(lanServerRepositoryProvider);

  @override
  LanWorkspaceState build() {
    ref.onDispose(() {
      _heartbeatTimer?.cancel();
      _eventsSubscription?.cancel();
      _channel?.sink.close();
      for (final sub in _folderSubscriptions.values) {
        sub.cancel();
      }
      _folderSubscriptions.clear();
      for (final timer in _debounceTimers.values) {
        timer.cancel();
      }
      _debounceTimers.clear();
    });

    final profileName = ref.watch(profileViewModelProvider
        .select((p) => p.value?.profile?.name ?? Constants.defaultName));

    return LanWorkspaceState(
      peerId: const Uuid().v4(),
      nickname: profileName,
    );
  }

  Future<void> autoDiscoverAndConnect({List<Uri>? preferredCandidates}) async {
    state = state.copyWith(isConnecting: true, clearError: true);
    final servers = await _repository.discoverServers();

    // Add preferred candidates that might have been missed by the scan
    if (preferredCandidates != null) {
      for (final uri in preferredCandidates) {
        if (!servers.contains(uri)) {
          try {
            await _repository.fetchStatus(uri).timeout(const Duration(seconds: 1));
            servers.add(uri);
          } catch (_) {}
        }
      }
    }

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
      refreshFiles();
      refreshShares();
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
      sharedFolders: [],
      localShares: {},
    );
  }

  void sendChat(String body, {List<FileOffer> fileOffers = const []}) {
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty && fileOffers.isEmpty) {
      return;
    }
    if (_channel == null) {
      return;
    }
    final message = ChatMessage(
      messageId: const Uuid().v4(),
      senderId: state.peerId,
      receiverId: 'global',
      body: trimmedBody,
      timestamp: DateTime.now(),
      fileOffers: fileOffers,
    );
    _sendEvent('CHAT_MESSAGE', message.toJson());
  }

  void editChat(String messageId, String newBody, {List<FileOffer>? fileOffers}) {
    final trimmedBody = newBody.trim();
    final message = state.messages.firstWhere((m) => m.messageId == messageId);
    
    // Check if anything actually changed
    final isBodyChanged = trimmedBody.isNotEmpty && trimmedBody != message.body;
    final isFilesChanged = fileOffers != null && !listEquals(fileOffers, message.fileOffers);
    
    if (!isBodyChanged && !isFilesChanged) {
      cancelEditing();
      return;
    }

    final updatedMessage = message.copyWith(
      body: trimmedBody, 
      fileOffers: fileOffers ?? message.fileOffers,
      isEdited: true,
    );
    
    _sendEvent('CHAT_EDIT', updatedMessage.toJson());
    cancelEditing();
  }

  void startEditing(ChatMessage message) {
    state = state.copyWith(editingMessage: message);
  }

  void cancelEditing() {
    state = state.copyWith(clearEditingMessage: true);
  }

  void deleteChat(String messageId) {
    _sendEvent('CHAT_DELETE', {'msg_id': messageId});
    if (state.editingMessage?.messageId == messageId) {
      cancelEditing();
    }
  }

  Future<FileOffer?> uploadFileOnly({
    required String fileName,
    String? filePath,
    Uint8List? bytes,
    String recipientId = 'global',
  }) async {
    final serverUri = state.serverUri;
    if (!state.isConnected || serverUri == null) {
      state = state.copyWith(error: 'Connect to a LAN server before sharing files.');
      return null;
    }
    if (filePath == null && bytes == null) {
      state = state.copyWith(error: 'Select a readable file before sharing.');
      return null;
    }

    _lastTransferredBytes = 0;
    _lastSpeedUpdateTime = DateTime.now();
    _transferStartTime = DateTime.now();
    state = state.copyWith(
      isTransferring: true,
      transferProgress: 0,
      transferSpeed: '0 B/s',
      transferAverageSpeed: '0 B/s',
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
            final now = DateTime.now();
            final elapsedMs = now.difference(_lastSpeedUpdateTime ?? now).inMilliseconds;
            String currentSpeed = state.transferSpeed;
            if (elapsedMs >= 350 || sent == total) {
              final bytesSentSinceLast = sent - _lastTransferredBytes;
              final speedBytesPerSec = elapsedMs > 0 
                  ? (bytesSentSinceLast / elapsedMs) * 1000 
                  : 0.0;
              currentSpeed = Utils.formatSpeed(speedBytesPerSec);
              _lastTransferredBytes = sent;
              _lastSpeedUpdateTime = now;
            }

            final elapsedTotalMs = now.difference(_transferStartTime ?? now).inMilliseconds;
            final avgSpeedBytesPerSec = elapsedTotalMs > 0 
                ? (sent / elapsedTotalMs) * 1000 
                : 0.0;
            final currentAvgSpeed = Utils.formatSpeed(avgSpeedBytesPerSec);

            state = state.copyWith(
              transferProgress: sent / total,
              transferSpeed: currentSpeed,
              transferAverageSpeed: currentAvgSpeed,
            );
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
      state = state.copyWith(
        files: [transfer, ...state.files],
        fileOffers: [offer, ...state.fileOffers],
        transferProgress: 1,
        transferSpeed: '0 B/s',
        transferAverageSpeed: '0 B/s',
        isTransferring: false,
      );
      refreshFiles();
      return offer;
    } catch (error) {
      state = state.copyWith(
        isTransferring: false,
        transferSpeed: '0 B/s',
        transferAverageSpeed: '0 B/s',
        error: 'File upload failed: $error',
      );
      return null;
    }
  }

  Future<void> uploadAndOfferFile({
    required String fileName,
    String? filePath,
    Uint8List? bytes,
    String recipientId = 'global',
  }) async {
    final offer = await uploadFileOnly(
      fileName: fileName,
      filePath: filePath,
      bytes: bytes,
      recipientId: recipientId,
    );
    if (offer != null) {
      _sendEvent('FILE_OFFER', offer.toJson());
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

    _lastTransferredBytes = 0;
    _lastSpeedUpdateTime = DateTime.now();
    _transferStartTime = DateTime.now();
    state = state.copyWith(
      isTransferring: true,
      transferProgress: 0,
      transferSpeed: '0 B/s',
      transferAverageSpeed: '0 B/s',
      clearError: true,
    );
    try {
      await _repository.downloadFile(
        serverUri: serverUri,
        transferId: transferId,
        savePath: savePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final now = DateTime.now();
            final elapsedMs = now.difference(_lastSpeedUpdateTime ?? now).inMilliseconds;
            String currentSpeed = state.transferSpeed;
            if (elapsedMs >= 350 || received == total) {
              final bytesReceivedSinceLast = received - _lastTransferredBytes;
              final speedBytesPerSec = elapsedMs > 0 
                  ? (bytesReceivedSinceLast / elapsedMs) * 1000 
                  : 0.0;
              currentSpeed = Utils.formatSpeed(speedBytesPerSec);
              _lastTransferredBytes = received;
              _lastSpeedUpdateTime = now;
            }

            final elapsedTotalMs = now.difference(_transferStartTime ?? now).inMilliseconds;
            final avgSpeedBytesPerSec = elapsedTotalMs > 0 
                ? (received / elapsedTotalMs) * 1000 
                : 0.0;
            final currentAvgSpeed = Utils.formatSpeed(avgSpeedBytesPerSec);

            state = state.copyWith(
              transferProgress: received / total,
              transferSpeed: currentSpeed,
              transferAverageSpeed: currentAvgSpeed,
            );
          }
        },
      );
      state = state.copyWith(
        isTransferring: false,
        transferProgress: 1,
        transferSpeed: '0 B/s',
        transferAverageSpeed: '0 B/s',
        clearError: true,
      );
      return true;
    } catch (error) {
      state = state.copyWith(
        isTransferring: false,
        transferSpeed: '0 B/s',
        transferAverageSpeed: '0 B/s',
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
        deletedFileIds: {...state.deletedFileIds, transferId},
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
        final message = ChatMessage.fromJson(event.payload);
        state = state.copyWith(
          messages: [
            ...state.messages,
            message,
          ],
        );
        if (message.fileOffers.isNotEmpty) {
          refreshFiles();
        }
        break;
      case 'CHAT_EDIT':
        final updatedMessage = ChatMessage.fromJson(event.payload);
        state = state.copyWith(
          messages: state.messages.map((m) {
            return m.messageId == updatedMessage.messageId ? updatedMessage : m;
          }).toList(),
        );
        break;
      case 'CHAT_DELETE':
        final msgId = event.payload['msg_id'] as String?;
        if (msgId != null) {
          state = state.copyWith(
            messages: state.messages.where((m) => m.messageId != msgId).toList(),
          );
        }
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
      case 'FILE_DELETED':
        final deletedId = event.payload['transfer_id'] as String?;
        if (deletedId != null) {
          state = state.copyWith(
            deletedFileIds: {...state.deletedFileIds, deletedId},
            files: state.files
                .where((file) => file.transferId != deletedId)
                .toList(),
            fileOffers: state.fileOffers
                .where((offer) => offer.transferId != deletedId)
                .toList(),
          );
        }
        break;
      case 'FOLDER_SHARE':
        final share = SharedFolder.fromJson(event.payload);
        if (share.peerId != state.peerId) {
          state = state.copyWith(
            sharedFolders: [
              ...state.sharedFolders.where((s) => s.shareId != share.shareId),
              share,
            ],
          );
        }
        break;
      case 'FOLDER_UNSHARE':
        final shareId = event.payload['share_id'] as String?;
        if (shareId != null) {
          state = state.copyWith(
            sharedFolders: state.sharedFolders.where((s) => s.shareId != shareId).toList(),
          );
        }
        break;
      case 'SHARE_FILE_REQUEST':
        final requestId = event.payload['request_id'] as String?;
        final shareId = event.payload['share_id'] as String?;
        final relativePath = event.payload['relative_path'] as String?;
        final requesterId = event.payload['sender_id'] as String?;
        if (requestId != null && shareId != null && relativePath != null && requesterId != null) {
          _handleShareFileRequest(
            requestId: requestId,
            shareId: shareId,
            relativePath: relativePath,
            requesterId: requesterId,
          );
        }
        break;
      case 'SHARE_FILE_READY':
        final requestId = event.payload['request_id'] as String?;
        final transferId = event.payload['transfer_id'] as String?;
        if (requestId != null && transferId != null) {
          final completer = _pendingDownloadRequests.remove(requestId);
          if (completer != null && !completer.isCompleted) {
            completer.complete(transferId);
          }
        }
        break;
      case 'SHARE_FILE_ERROR':
        final requestId = event.payload['request_id'] as String?;
        final errorMsg = event.payload['error'] as String? ?? 'Unknown error';
        if (requestId != null) {
          final completer = _pendingDownloadRequests.remove(requestId);
          if (completer != null && !completer.isCompleted) {
            completer.completeError(errorMsg);
          }
        }
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

  Future<List<SharedFolderFile>> _scanDirectory(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) {
      return [];
    }

    final List<SharedFolderFile> folderFiles = [];
    try {
      final entities = dir.listSync(recursive: true, followLinks: false);
      int fileCount = 0;
      for (final entity in entities) {
        if (entity is File) {
          final relative = p.relative(entity.path, from: directoryPath);
          final pathSegments = p.split(relative);
          if (pathSegments.any((segment) => segment.startsWith('.'))) {
            continue;
          }

          fileCount++;
          if (fileCount > 500) {
            break;
          }

          final stat = await entity.stat();
          folderFiles.add(SharedFolderFile(
            relativePath: relative,
            fileName: p.basename(entity.path),
            fileSize: stat.size,
          ));
        }
      }
    } catch (e) {
      debugPrint('Error scanning directory $directoryPath: $e');
    }
    return folderFiles;
  }

  void _onFolderChanged(String shareId, String path) {
    _debounceTimers[shareId]?.cancel();
    _debounceTimers[shareId] = Timer(const Duration(milliseconds: 500), () {
      _updateSharedFolder(shareId, path);
    });
  }

  Future<void> _updateSharedFolder(String shareId, String path) async {
    final serverUri = state.serverUri;
    if (!state.isConnected || serverUri == null) {
      return;
    }
    if (!state.localShares.containsKey(shareId)) {
      return;
    }

    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        unshareFolder(shareId);
        return;
      }

      final dirName = p.basename(path);
      final folderFiles = await _scanDirectory(path);

      final shareRecord = SharedFolder(
        shareId: shareId,
        peerId: state.peerId,
        peerNickname: state.nickname,
        name: dirName.isEmpty ? 'Shared Folder' : dirName,
        files: folderFiles,
      );

      state = state.copyWith(
        sharedFolders: [
          ...state.sharedFolders.where((s) => s.shareId != shareId),
          shareRecord,
        ],
      );

      _sendEvent('FOLDER_SHARE', shareRecord.toJson());
    } catch (e) {
      debugPrint('Error updating watched folder: $e');
    }
  }

  Future<void> shareFolder() async {
    final serverUri = state.serverUri;
    if (!state.isConnected || serverUri == null) {
      state = state.copyWith(error: 'Connect to a LAN server before sharing folders.');
      return;
    }

    try {
      final selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory == null) {
        return; // User cancelled
      }

      final dir = Directory(selectedDirectory);
      if (!await dir.exists()) {
        state = state.copyWith(error: 'Selected directory does not exist.');
        return;
      }

      final dirName = p.basename(selectedDirectory);
      final folderFiles = await _scanDirectory(selectedDirectory);

      final shareId = const Uuid().v4();
      final shareRecord = SharedFolder(
        shareId: shareId,
        peerId: state.peerId,
        peerNickname: state.nickname,
        name: dirName.isEmpty ? 'Shared Folder' : dirName,
        files: folderFiles,
      );

      // Start watching the directory for changes
      try {
        final subscription = dir.watch(recursive: true).listen(
          (event) => _onFolderChanged(shareId, selectedDirectory),
          onError: (Object error) {
            debugPrint('Error watching folder $selectedDirectory: $error');
          },
        );
        _folderSubscriptions[shareId] = subscription;
      } catch (e) {
        // Fallback for environments that do not support recursive directory watch
        try {
          final subscription = dir.watch(recursive: false).listen(
            (event) => _onFolderChanged(shareId, selectedDirectory),
            onError: (Object error) {
              debugPrint('Error watching folder non-recursively: $error');
            },
          );
          _folderSubscriptions[shareId] = subscription;
        } catch (watchError) {
          debugPrint('Could not watch directory: $watchError');
        }
      }

      state = state.copyWith(
        localShares: {...state.localShares, shareId: selectedDirectory},
        sharedFolders: [...state.sharedFolders, shareRecord],
      );

      _sendEvent('FOLDER_SHARE', shareRecord.toJson());
    } catch (e) {
      state = state.copyWith(error: 'Failed to share folder: $e');
    }
  }

  Future<void> unshareFolder(String shareId) async {
    _sendEvent('FOLDER_UNSHARE', {'share_id': shareId});
    _folderSubscriptions.remove(shareId)?.cancel();
    _debounceTimers.remove(shareId)?.cancel();
    state = state.copyWith(
      localShares: Map.from(state.localShares)..remove(shareId),
      sharedFolders: state.sharedFolders.where((s) => s.shareId != shareId).toList(),
    );
  }

  Future<bool> downloadFolderFile({
    required String shareId,
    required String relativePath,
    required String fileName,
  }) async {
    final serverUri = state.serverUri;
    if (serverUri == null) {
      state = state.copyWith(error: 'Connect to a LAN server before downloading files.');
      return false;
    }

    final shareList = state.sharedFolders.where((s) => s.shareId == shareId).toList();
    if (shareList.isEmpty) {
      state = state.copyWith(error: 'Shared folder is no longer active.');
      return false;
    }
    final share = shareList.first;
    final ownerId = share.peerId;

    final requestId = const Uuid().v4();
    final completer = Completer<String>();
    _pendingDownloadRequests[requestId] = completer;

    _lastTransferredBytes = 0;
    _lastSpeedUpdateTime = DateTime.now();
    state = state.copyWith(
      isTransferring: true,
      transferProgress: 0,
      transferSpeed: 'Requesting...',
      transferAverageSpeed: 'Requesting...',
      clearError: true,
    );

    _sendEvent('SHARE_FILE_REQUEST', {
      'request_id': requestId,
      'share_id': shareId,
      'relative_path': relativePath,
      'recipient_id': ownerId,
    });

    try {
      final transferId = await completer.future.timeout(const Duration(seconds: 30));
      final directory = await getApplicationDocumentsDirectory();
      final savePath = p.join(directory.path, fileName);

      return await downloadFile(
        transferId: transferId,
        savePath: savePath,
      );
    } catch (e) {
      state = state.copyWith(
        isTransferring: false,
        transferSpeed: '0 B/s',
        transferAverageSpeed: '0 B/s',
        error: 'Failed to download file from shared folder: $e',
      );
      _pendingDownloadRequests.remove(requestId);
      return false;
    }
  }

  Future<void> refreshShares() async {
    final serverUri = state.serverUri;
    if (serverUri == null) {
      return;
    }
    try {
      final shares = await _repository.fetchShares(serverUri);
      final updatedShares = <SharedFolder>[];
      for (final share in shares) {
        if (share.peerId != state.peerId) {
          updatedShares.add(share);
        }
      }
      for (final myShareId in state.localShares.keys) {
        final myRecord = state.sharedFolders.firstWhere((s) => s.shareId == myShareId);
        updatedShares.add(myRecord);
      }
      state = state.copyWith(sharedFolders: updatedShares, clearError: true);
    } catch (error) {
      state = state.copyWith(error: 'Could not refresh shared folders: $error');
    }
  }

  Future<void> _handleShareFileRequest({
    required String requestId,
    required String shareId,
    required String relativePath,
    required String requesterId,
  }) async {
    final localFolderPath = state.localShares[shareId];
    if (localFolderPath == null) {
      _sendEvent('SHARE_FILE_ERROR', {
        'request_id': requestId,
        'recipient_id': requesterId,
        'error': 'Shared folder not found locally',
      });
      return;
    }

    final localFilePath = p.join(localFolderPath, relativePath);
    final file = File(localFilePath);
    if (!await file.exists()) {
      _sendEvent('SHARE_FILE_ERROR', {
        'request_id': requestId,
        'recipient_id': requesterId,
        'error': 'Requested file does not exist',
      });
      return;
    }

    try {
      final fileName = p.basename(localFilePath);
      final offer = await uploadFileOnly(
        fileName: fileName,
        filePath: localFilePath,
        recipientId: requesterId,
      );

      if (offer != null) {
        _sendEvent('SHARE_FILE_READY', {
          'request_id': requestId,
          'transfer_id': offer.transferId,
          'relative_path': relativePath,
          'recipient_id': requesterId,
        });
      } else {
        _sendEvent('SHARE_FILE_ERROR', {
          'request_id': requestId,
          'recipient_id': requesterId,
          'error': 'Failed to upload requested file to server',
        });
      }
    } catch (e) {
      _sendEvent('SHARE_FILE_ERROR', {
        'request_id': requestId,
        'recipient_id': requesterId,
        'error': 'Error reading/uploading file: $e',
      });
    }
  }
}
