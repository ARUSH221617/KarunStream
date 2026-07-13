import 'dart:async';
import 'dart:ui';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../utils/utils.dart';
import '../model/chat_message.dart';
import '../model/file_offer.dart';
import '../state/lan_workspace_controller.dart';
import '../../../theme/app_theme.dart';
import 'karun_empty_state.dart';

class MessageList extends ConsumerWidget {
  const MessageList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lanWorkspaceProvider);

    if (state.messages.isEmpty) {
      return const KarunEmptyState(
        icon: Icons.forum_outlined,
        title: 'No Messages Yet',
        subtitle:
            'Start the conversation! Messages sent here are only visible to devices on your local network.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(
        left: 16,
        right: 16,
        top: 80,
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

class _ChatMessageBubble extends ConsumerStatefulWidget {
  const _ChatMessageBubble({
    required this.message,
    required this.isMine,
  });

  final ChatMessage message;
  final bool isMine;

  @override
  ConsumerState<_ChatMessageBubble> createState() => _ChatMessageBubbleState();
}

class _ChatMessageBubbleState extends ConsumerState<_ChatMessageBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _showContextMenu(BuildContext context, Offset pressPosition) async {
    final Size screenSize = MediaQuery.of(context).size;
    final isMe = widget.isMine;

    await _pressController.forward();
    if (!context.mounted) return;

    final overlay = Overlay.of(context);
    final result = await _showGlassMenu(
      overlay: overlay,
      screenSize: screenSize,
      pressPosition: pressPosition,
      isMe: isMe,
      context: context,
    );

    await _pressController.reverse();

    if (!context.mounted) return;
    if (result == 'edit') {
      ref.read(lanWorkspaceProvider.notifier).startEditing(widget.message);
    } else if (result == 'delete') {
      _showDeleteConfirmation(context);
    }
  }

  Future<String?> _showGlassMenu({
    required OverlayState overlay,
    required Size screenSize,
    required Offset pressPosition,
    required bool isMe,
    required BuildContext context,
  }) {
    final completer = Completer<String?>();
    const double menuWidth = 160;
    const double menuHeight = 104; // 2 items × 48 + divider + padding

    // Position the menu near the press point.
    // Vertical: prefer below the press; if not enough room, go above.
    double dy = pressPosition.dy + 4;
    if (dy + menuHeight > screenSize.height - 100) {
      dy = pressPosition.dy - menuHeight - 4;
    }
    dy = dy.clamp(12.0, screenSize.height - menuHeight - 12);

    // Horizontal: align based on message ownership.
    double dx = isMe ? pressPosition.dx - menuWidth : pressPosition.dx;
    dx = dx.clamp(12.0, screenSize.width - menuWidth - 12);

    late final OverlayEntry scrimEntry;
    late final OverlayEntry menuEntry;

    void dismiss(String? value) {
      menuEntry.remove();
      scrimEntry.remove();
      if (!completer.isCompleted) completer.complete(value);
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    scrimEntry = OverlayEntry(
      builder: (_) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => dismiss(null),
        child: const SizedBox.expand(),
      ),
    );

    menuEntry = OverlayEntry(
      builder: (_) => Positioned(
        left: dx,
        top: dy,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Transform.scale(
              scale: 0.85 + 0.15 * value,
              alignment: isMe ? Alignment.topRight : Alignment.topLeft,
              child: Opacity(opacity: value, child: child),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                width: menuWidth,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.8),
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildMenuItem(
                      icon: Icons.edit_rounded,
                      label: 'Edit',
                      color: const Color(0xFF4A90D9),
                      isDark: isDark,
                      onTap: () => dismiss('edit'),
                    ),
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.12)
                          : Colors.black.withValues(alpha: 0.08),
                      indent: 16,
                      endIndent: 16,
                    ),
                    _buildMenuItem(
                      icon: Icons.delete_rounded,
                      label: 'Delete',
                      color: const Color(0xFFE53935),
                      isDark: isDark,
                      onTap: () => dismiss('delete'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(scrimEntry);
    overlay.insert(menuEntry);
    return completer.future;
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: color.withValues(alpha: 0.10),
        highlightColor: color.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Text(
                label,
                style: AppTheme.subtitle16.copyWith(
                  color: isDark ? Colors.white : color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Delete Message', style: AppTheme.title18),
          content: const Text(
            'Are you sure you want to delete this message? This action cannot be undone.',
            style: AppTheme.body14,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CANCEL',
                  style: AppTheme.label14.copyWith(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                ref
                    .read(lanWorkspaceProvider.notifier)
                    .deleteChat(widget.message.messageId);
                Navigator.pop(context);
              },
              child: Text('DELETE',
                  style: AppTheme.label14.copyWith(
                      color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final theme = Theme.of(context);
    final isMe = widget.isMine;
    final timeStr = DateFormat('HH:mm').format(widget.message.timestamp);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: GestureDetector(
          onLongPressStart: isMe
              ? (details) => _showContextMenu(context, details.globalPosition)
              : null,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Container(
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
                  if (widget.message.fileOffers.isNotEmpty) ...[
                    for (final offer in widget.message.fileOffers)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: _FileAttachment(
                          offer: offer,
                          isMine: isMe,
                        ),
                      ),
                    if (widget.message.body.isNotEmpty)
                      const SizedBox(height: 4),
                  ],
                  if (widget.message.body.isNotEmpty)
                    Text(
                      widget.message.body,
                      style: TextStyle(
                        color: isMe ? Colors.white : null,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.message.isEdited == true)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            'Edited',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: (isMe
                                      ? Colors.white
                                      : theme.colorScheme.onSurface)
                                  .withValues(alpha: 0.5),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      Text(
                        timeStr,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: (isMe
                                  ? Colors.white
                                  : theme.colorScheme.onSurface)
                              .withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
            isDeleted ? Icons.block_flipped : Utils.getFileIcon(offer.fileName),
            color: isDeleted
                ? theme.colorScheme.error
                : Utils.getFileColor(offer.fileName),
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
                    color:
                        isDeleted ? theme.colorScheme.error : foregroundColor,
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
