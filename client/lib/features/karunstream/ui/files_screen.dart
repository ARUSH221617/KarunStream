import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../theme/app_colors.dart';
import '../model/file_transfer.dart';
import '../state/lan_workspace_controller.dart';
import '../widgets/karun_empty_state.dart';

class FilesScreen extends ConsumerWidget {
  const FilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lanWorkspaceProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.folder_copy_outlined),
                    const SizedBox(width: 8),
                    Text(
                      'LAN Files',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Refresh files',
                      onPressed: state.serverUri == null
                          ? null
                          : ref.read(lanWorkspaceProvider.notifier).refreshFiles,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Upload files to the local server and announce them to peers without cloud storage.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                if (state.isTransferring) ...[
                  LinearProgressIndicator(value: state.transferProgress),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 16),
                Expanded(
                  child: state.files.isEmpty
                      ? const KarunEmptyState(
                          icon: Icons.folder_open_outlined,
                          title: 'No Shared Files',
                          subtitle: 'Upload files to share them instantly with active devices on your local network.',
                        )
                      : ListView(
                          children: [
                            for (final file in state.files)
                              _FileTransferTile(file: file),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: state.isConnected && !state.isTransferring
            ? () => _pickAndUpload(ref)
            : null,
        tooltip: 'Share local media',
        backgroundColor: AppColors.orange,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _pickAndUpload(WidgetRef ref) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickMedia();
    if (pickedFile == null) {
      return;
    }
    await ref.read(lanWorkspaceProvider.notifier).uploadAndOfferFile(
          fileName: pickedFile.name,
          filePath: kIsWeb || pickedFile.path.isEmpty ? null : pickedFile.path,
          bytes: kIsWeb || pickedFile.path.isEmpty
              ? await pickedFile.readAsBytes()
              : null,
        );
  }
}

class _FileTransferTile extends ConsumerWidget {
  const _FileTransferTile({required this.file});

  final FileTransfer file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Dismissible(
      key: Key('file_${file.transferId}'),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (_) => _confirmDelete(context, ref, file.transferId),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        color: theme.colorScheme.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: ListTile(
        leading: const Icon(Icons.cloud_done_outlined),
        title: Text(file.fileName),
        subtitle: Text('Uploaded • ${_formatBytes(file.bytes)}'),
        trailing: IconButton(
          tooltip: 'Download',
          onPressed: () => _downloadTransfer(context, ref, file),
          icon: const Icon(Icons.download_outlined),
        ),
      ),
    );
  }
}

Future<void> _downloadTransfer(
  BuildContext context,
  WidgetRef ref,
  FileTransfer file,
) async {
  await _downloadFile(
    context,
    ref,
    transferId: file.transferId,
    fileName: file.fileName,
  );
}

Future<void> _downloadFile(
  BuildContext context,
  WidgetRef ref, {
  required String transferId,
  required String fileName,
}) async {
  if (kIsWeb) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Browser download support is coming next.'),
      ),
    );
    return;
  }

  final directory = await getApplicationDocumentsDirectory();
  final savePath = p.join(directory.path, fileName);
  final didDownload = await ref.read(lanWorkspaceProvider.notifier).downloadFile(
        transferId: transferId,
        savePath: savePath,
      );
  if (context.mounted && didDownload) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved to $savePath')),
    );
  }
}

Future<bool?> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  String transferId,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete file?'),
      content: const Text(
        'Only files uploaded by you can be deleted. This removes the local server copy.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    await ref
        .read(lanWorkspaceProvider.notifier)
        .deleteUploadedFile(transferId);
  }

  return confirmed;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
