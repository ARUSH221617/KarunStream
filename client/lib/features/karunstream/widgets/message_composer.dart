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
  bool _isTextEmpty = true;
  final List<XFile> _pendingFiles = [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleTextChange);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(lanWorkspaceProvider);

    ref.listen(lanWorkspaceProvider.select((s) => s.editingMessage), (prev, next) {
      if (next != null && prev?.messageId != next.messageId) {
        _controller.text = next.body;
      } else if (next == null && prev != null) {
        _controller.clear();
      }
    });

    final canAttach = state.isConnected && !state.isTransferring && state.editingMessage == null;
    final canSend =
        state.isConnected && (!_isTextEmpty || _pendingFiles.isNotEmpty);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_pendingFiles.isNotEmpty)
          _FilesPreviewList(
            files: _pendingFiles,
            onRemove: (index) => setState(() => _pendingFiles.removeAt(index)),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Main input container
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withOpacity(0.5),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withOpacity(0.5),
                    ),
                  ),
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
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Attachment Button
                          Padding(
                            padding: const EdgeInsets.only(left: 4.0, bottom: 4.0),
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
                                      color: canAttach ? null : theme.disabledColor,
                                    ),
                            ),
                          ),

                          // Text Field
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              child: TextField(
                                controller: _controller,
                                enabled: state.isConnected,
                                minLines: 1,
                                maxLines: 5,
                                keyboardType: TextInputType.multiline,
                                textInputAction: TextInputAction.newline,
                                style: theme.textTheme.bodyLarge,
                                decoration: InputDecoration(
                                  hintText: state.editingMessage != null
                                      ? 'Edit message...'
                                      : 'Send a message...',
                                  fillColor: Colors.transparent,
                                  border: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 12.0),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Send Button
              Padding(
                padding: const EdgeInsets.only(bottom: 2.0),
                child: IconButton.filled(
                  onPressed: canSend ? _send : null,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    backgroundColor: canSend
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    disabledBackgroundColor: theme
                        .colorScheme.surfaceContainerHighest
                        .withOpacity(0.3),
                  ),
                  icon: Icon(
                    state.editingMessage != null
                        ? Icons.check_rounded
                        : Icons.send_rounded,
                    color: canSend
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                  ),
                ),
              ),
            ],
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
      if (text.isNotEmpty && text != state.editingMessage!.body) {
        notifier.editChat(state.editingMessage!.messageId, text);
      } else {
        notifier.cancelEditing();
      }
      _controller.clear();
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
            color: theme.colorScheme.outlineVariant.withOpacity(0.3),
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
    required this.files,
    required this.onRemove,
  });

  final List<XFile> files;
  final void Function(int) onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      margin: const EdgeInsets.only(top: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: files.length,
        itemBuilder: (context, index) {
          return _FilePreviewItem(
            file: files[index],
            onRemove: () => onRemove(index),
          );
        },
      ),
    );
  }
}

class _FilePreviewItem extends StatelessWidget {
  const _FilePreviewItem({
    required this.file,
    required this.onRemove,
  });

  final XFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 180,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file_outlined, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
