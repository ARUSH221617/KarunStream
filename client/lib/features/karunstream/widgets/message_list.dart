import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../model/chat_message.dart';
import '../model/file_offer.dart';
import '../state/lan_workspace_controller.dart';
import '../../../theme/app_theme.dart';

class MessageList extends ConsumerWidget {
  const MessageList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lanWorkspaceProvider);

    if (state.messages.isEmpty) {
      return const Center(
        child: Text('Lobby messages will appear here.'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 90, // Space for the floating composer
      ),
      itemCount: state.messages.length,
      itemBuilder: (context, index) {
        final message = state.messages[index];
        final isMine = message.senderId == state.peerId;
        return _ChatMessageBubble(
          message: message,
          isMine: isMine,
        );
      },
    );
  }
}

class _ChatMessageBubble extends ConsumerWidget {
  const _ChatMessageBubble({
    required this.message,
    required this.isMine,
  });

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isMe = isMine == true;
    final timeStr = DateFormat('HH:mm').format(message.timestamp);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: isMe ? () => _showActions(context, ref) : null,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: const BoxConstraints(maxWidth: 520),
          decoration: BoxDecoration(
            color: isMe
                ? theme.colorScheme.secondary
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.fileOffers.isNotEmpty) ...[
                for (final offer in message.fileOffers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: _FileAttachment(
                      offer: offer,
                      isMine: isMe,
                    ),
                  ),
                if (message.body.isNotEmpty) const SizedBox(height: 4),
              ],
              if (message.body.isNotEmpty)
                Text(
                  message.body,
                  style: TextStyle(
                    color: isMe ? Colors.white : null,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.isEdited == true)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        'Edited',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: (isMe ? Colors.white : theme.colorScheme.onSurface)
                              .withValues(alpha: 0.5),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  Text(
                    timeStr,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: (isMe ? Colors.white : theme.colorScheme.onSurface)
                          .withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showActions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.edit_rounded, color: Colors.blue),
                  title: Text('Edit', style: AppTheme.subtitle16.copyWith(color: Colors.blue)),
                  onTap: () {
                    Navigator.pop(context);
                    ref.read(lanWorkspaceProvider.notifier).startEditing(message);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_rounded, color: Colors.red),
                  title: Text('Delete', style: AppTheme.subtitle16.copyWith(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    _showDeleteConfirmation(context, ref);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDeleteConfirmation(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Delete Message', style: AppTheme.title18),
          content: const Text(
            'Are you sure you want to delete this message? This action cannot be undone.',
            style: AppTheme.body14,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CANCEL', style: AppTheme.label14.copyWith(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                ref.read(lanWorkspaceProvider.notifier).deleteChat(message.messageId);
                Navigator.pop(context);
              },
              child: Text('DELETE', style: AppTheme.label14.copyWith(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }
}

class _FileAttachment extends ConsumerWidget {
  const _FileAttachment({
    required this.offer,
    required this.isMine,
  });

  final FileOffer offer;
  final bool isMine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(lanWorkspaceProvider);
    final isMe = isMine == true;
    final isDeleted = state.deletedFileIds.contains(offer.transferId);
    final foregroundColor = isMe ? Colors.white : theme.colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.white.withValues(alpha: 0.15)
            : theme.colorScheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDeleted
                ? Icons.block_flipped
                : Icons.insert_drive_file_rounded,
            color: isDeleted ? theme.colorScheme.error : foregroundColor,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isDeleted ? 'Deleted file' : offer.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDeleted ? theme.colorScheme.error : foregroundColor,
                    fontWeight: FontWeight.w700,
                    fontStyle: isDeleted ? FontStyle.italic : null,
                  ),
                ),
                if (!isDeleted)
                  Text(
                    _formatBytes(offer.fileSize),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: foregroundColor.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
          ),
          if (!isDeleted) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => _downloadOffer(context, ref, offer),
              icon: Icon(Icons.download_rounded, color: foregroundColor),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _downloadOffer(
    BuildContext context,
    WidgetRef ref,
    FileOffer offer,
  ) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Browser download is coming next.')),
      );
      return;
    }

    final directory = await getApplicationDocumentsDirectory();
    final savePath = p.join(directory.path, offer.fileName);
    final didDownload = await ref
        .read(lanWorkspaceProvider.notifier)
        .downloadFile(transferId: offer.transferId, savePath: savePath);

    if (context.mounted && didDownload) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to $savePath')),
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
