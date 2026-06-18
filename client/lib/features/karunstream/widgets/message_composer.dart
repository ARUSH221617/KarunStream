import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../model/chat_message.dart';
import '../model/file_offer.dart';
import '../state/lan_workspace_controller.dart';
import '../../../theme/app_theme.dart';

class MessageComposer extends ConsumerStatefulWidget {
  const MessageComposer({super.key});

  @override
  ConsumerState<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends ConsumerState<MessageComposer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isTextEmpty = true;
  bool _isHovered = false;
  final List<XFile> _pendingFiles = [];
  List<FileOffer> _editingAttachedFiles = [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleTextChange);
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    setState(() {});
  }

  void _handleTextChange() {
    final isEmpty = _controller.text.trim().isEmpty;
    if (isEmpty != _isTextEmpty) {
      setState(() {
        _isTextEmpty = isEmpty;
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChange);
    _controller.dispose();
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(lanWorkspaceProvider);
    final notifier = ref.read(lanWorkspaceProvider.notifier);

    ref.listen(lanWorkspaceProvider.select((s) => s.editingMessage),
        (prev, next) {
      if (next != null && prev?.messageId != next.messageId) {
        _controller.text = next.body;
        setState(() {
          _editingAttachedFiles = List.from(next.fileOffers);
          _pendingFiles.clear();
        });
      } else if (next == null && prev != null) {
        _controller.clear();
        setState(() {
          _editingAttachedFiles.clear();
          _pendingFiles.clear();
        });
      }
    });

    final canAttach = state.isConnected && !state.isTransferring;
    final canSend = state.isConnected &&
        (!_isTextEmpty ||
            _pendingFiles.isNotEmpty ||
            _editingAttachedFiles.isNotEmpty);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_pendingFiles.isNotEmpty || _editingAttachedFiles.isNotEmpty)
          _FilesPreviewList(
            existingFiles: _editingAttachedFiles,
            newFiles: _pendingFiles,
            onRemoveExisting: (index) =>
                setState(() => _editingAttachedFiles.removeAt(index)),
            onRemoveNew: (index) =>
                setState(() => _pendingFiles.removeAt(index)),
            onDeleteExisting: (index) {
              final offer = _editingAttachedFiles[index];
              notifier.deleteUploadedFile(offer.transferId);
              setState(() => _editingAttachedFiles.removeAt(index));
            },
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: GestureDetector(
              onTap: () {
                if (!_focusNode.hasFocus) {
                  _focusNode.requestFocus();
                }
              },
              child: _GlassContainer(
                isHovered: _isHovered,
                isFocused: _focusNode.hasFocus,
                borderRadius: BorderRadius.circular(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (state.editingMessage != null)
                      _EditMessageBanner(
                        message: state.editingMessage!,
                        onCancel: () => ref
                            .read(lanWorkspaceProvider.notifier)
                            .cancelEditing(),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Attachment Button
                        Padding(
                          padding: const EdgeInsets.only(left: 6.0),
                          child: IconButton(
                            tooltip: 'Share file',
                            onPressed: canAttach ? _attachFile : null,
                            icon: state.isTransferring
                                ? SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: theme.colorScheme.primary,
                                    ),
                                  )
                                : Icon(
                                    Icons.add_circle_outline_rounded,
                                    color:
                                        canAttach ? null : theme.disabledColor,
                                  ),
                          ),
                        ),

                        // Text Field
                        Expanded(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8.0),
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              enabled: state.isConnected,
                              minLines: 1,
                              maxLines: 5,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              style: theme.textTheme.bodyLarge,
                              decoration: InputDecoration(
                                hintText: 'Message',
                                filled: false,
                                fillColor: Colors.transparent,
                                hoverColor: Colors.transparent,
                                focusColor: Colors.transparent,
                                border: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 16.0),
                              ),
                            ),
                          ),
                        ),

                        // Send Button
                        Padding(
                          padding: const EdgeInsets.only(right: 6.0),
                          child: IconButton.filled(
                            onPressed: canSend ? _send : null,
                            style: IconButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: theme.colorScheme.onPrimary,
                              disabledBackgroundColor: theme
                                  .colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.3),
                              disabledForegroundColor: theme
                                  .colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.4),
                              minimumSize: const Size(48, 48),
                            ),
                            icon: Icon(
                              state.editingMessage != null
                                  ? Icons.check_rounded
                                  : Icons.send_rounded,
                              size: 22,
                            ),
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
      ],
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    final files = List<XFile>.from(_pendingFiles);
    final state = ref.read(lanWorkspaceProvider);
    final notifier = ref.read(lanWorkspaceProvider.notifier);

    if (state.editingMessage != null) {
      final List<FileOffer> allOffers = List.from(_editingAttachedFiles);
      if (files.isNotEmpty) {
        for (final file in files) {
          final offer = await notifier.uploadFileOnly(
            fileName: file.name,
            filePath: kIsWeb || file.path.isEmpty ? null : file.path,
            bytes:
                kIsWeb || file.path.isEmpty ? await file.readAsBytes() : null,
          );
          if (offer != null) {
            allOffers.add(offer);
          }
        }
      }
      notifier.editChat(state.editingMessage!.messageId, text,
          fileOffers: allOffers);
      _controller.clear();
      setState(() {
        _editingAttachedFiles.clear();
        _pendingFiles.clear();
      });
      return;
    }

    if (text.isEmpty && files.isEmpty) return;

    _controller.clear();
    setState(() {
      _pendingFiles.clear();
    });

    if (files.isNotEmpty) {
      final List<FileOffer> offers = [];
      for (final file in files) {
        final offer = await notifier.uploadFileOnly(
          fileName: file.name,
          filePath: kIsWeb || file.path.isEmpty ? null : file.path,
          bytes: kIsWeb || file.path.isEmpty ? await file.readAsBytes() : null,
        );
        if (offer != null) {
          offers.add(offer);
        }
      }
      if (offers.isNotEmpty) {
        notifier.sendChat(text, fileOffers: offers);
      }
    } else {
      notifier.sendChat(text);
    }
  }

  Future<void> _attachFile() async {
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultipleMedia();
    if (pickedFiles.isEmpty) return;

    setState(() {
      _pendingFiles.addAll(pickedFiles);
    });
  }
}

class _GlassContainer extends StatelessWidget {
  const _GlassContainer({
    required this.child,
    this.borderRadius,
    this.isHovered = false,
    this.isFocused = false,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final bool isHovered;
  final bool isFocused;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: (isDark ? Colors.black : Colors.white).withValues(
              alpha: isFocused ? 0.15 : (isHovered ? 0.13 : 0.08),
            ),
            borderRadius: borderRadius ?? BorderRadius.circular(24),
            border: Border.all(
              color: isFocused
                  ? theme.colorScheme.primary.withValues(alpha: 0.6)
                  : (isDark ? Colors.white : Colors.black).withValues(
                      alpha: isHovered ? 0.2 : 0.1,
                    ),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: (isFocused ? theme.colorScheme.primary : Colors.black)
                    .withValues(alpha: isFocused ? 0.12 : 0.05),
                blurRadius: isFocused ? 14 : 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _EditMessageBanner extends StatelessWidget {
  const _EditMessageBanner({
    required this.message,
    required this.onCancel,
  });

  final ChatMessage message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.only(left: 16, top: 8, right: 8, bottom: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.edit_rounded, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Edit Message',
                  style: AppTheme.title12.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                Text(
                  message.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _FilesPreviewList extends StatelessWidget {
  const _FilesPreviewList({
    required this.existingFiles,
    required this.newFiles,
    required this.onRemoveExisting,
    required this.onRemoveNew,
    required this.onDeleteExisting,
  });

  final List<FileOffer> existingFiles;
  final List<XFile> newFiles;
  final void Function(int) onRemoveExisting;
  final void Function(int) onRemoveNew;
  final void Function(int) onDeleteExisting;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      margin: const EdgeInsets.only(top: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          ...existingFiles.asMap().entries.map((e) => _FilePreviewItem(
                fileName: e.value.fileName,
                isExisting: true,
                onRemove: () => onRemoveExisting(e.key),
                onDelete: () => onDeleteExisting(e.key),
              )),
          ...newFiles.asMap().entries.map((e) => _FilePreviewItem(
                fileName: e.value.name,
                isExisting: false,
                onRemove: () => onRemoveNew(e.key),
              )),
        ],
      ),
    );
  }
}

class _FilePreviewItem extends StatelessWidget {
  const _FilePreviewItem({
    required this.fileName,
    required this.isExisting,
    required this.onRemove,
    this.onDelete,
  });

  final String fileName;
  final bool isExisting;
  final VoidCallback onRemove;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isExisting
                ? Icons.cloud_done_outlined
                : Icons.insert_drive_file_outlined,
            size: 20,
            color: isExisting ? theme.colorScheme.primary : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (isExisting && onDelete != null)
            IconButton(
              onPressed: () => _showDeleteDialog(context),
              icon: const Icon(Icons.delete_forever_outlined,
                  size: 18, color: Colors.red),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
              tooltip: 'Delete from server',
            ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
            tooltip: 'Detach',
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete from Server?'),
        content: const Text(
            'This will permanently delete the file from the server for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onDelete?.call();
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
