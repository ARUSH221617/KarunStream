import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'dart:developer' as developer;

import '../../../theme/app_colors.dart';
import '../../../utils/utils.dart';
import '../../../generated/locale_keys.g.dart';
import '../model/file_transfer.dart';
import '../model/shared_folder.dart';
import '../state/lan_workspace_controller.dart';
import '../widgets/karun_empty_state.dart';

class FilesScreen extends ConsumerWidget {
  const FilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lanWorkspaceProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DefaultTabController(
        length: 2,
        child: Padding(
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
                        'LAN Sharing',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Refresh',
                        onPressed: state.serverUri == null
                            ? null
                            : () {
                                ref.read(lanWorkspaceProvider.notifier).refreshFiles();
                                ref.read(lanWorkspaceProvider.notifier).refreshShares();
                              },
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TabBar(
                    labelColor: AppColors.orange,
                    unselectedLabelColor: AppColors.slate,
                    indicatorColor: AppColors.orange,
                    tabs: [
                      Tab(text: context.tr(LocaleKeys.filesTab)),
                      Tab(text: context.tr(LocaleKeys.foldersTab)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (state.isTransferring) ...[
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: state.transferProgress > 0 ? state.transferProgress : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          state.transferSpeed,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  Expanded(
                    child: TabBarView(
                      children: [
                        _FilesView(state: state),
                        _FoldersView(state: state),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: state.isConnected && !state.isTransferring
            ? () => _showShareBottomSheet(context, ref)
            : null,
        tooltip: 'Share content',
        backgroundColor: AppColors.orange,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Share'),
      ),
    );
  }

  void _showShareBottomSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.file_present_outlined, color: AppColors.orange),
                title: const Text('Share Any File'),
                subtitle: const Text('Upload zip, rar, video, doc, etc.'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUpload(ref);
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder_shared_outlined, color: AppColors.orange),
                title: const Text('Share Local Folder'),
                subtitle: const Text('Allow peers to download files from a folder.'),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(lanWorkspaceProvider.notifier).shareFolder();
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndUpload(WidgetRef ref) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }
      final pickedFile = result.files.first;
      await ref.read(lanWorkspaceProvider.notifier).uploadAndOfferFile(
            fileName: pickedFile.name,
            filePath: kIsWeb || pickedFile.path == null ? null : pickedFile.path,
            bytes: kIsWeb || pickedFile.path == null ? pickedFile.bytes : null,
          );
    } catch (e) {
      developer.log('File pick error: $e');
    }
  }
}

class _FilesView extends StatelessWidget {
  const _FilesView({required this.state});
  final LanWorkspaceState state;

  @override
  Widget build(BuildContext context) {
    if (state.files.isEmpty) {
      return const KarunEmptyState(
        icon: Icons.folder_open_outlined,
        title: 'No Shared Files',
        subtitle: 'Upload files to share them instantly with active devices on your local network.',
      );
    }
    return ListView.builder(
      itemCount: state.files.length,
      itemBuilder: (context, index) {
        return _FileTransferTile(file: state.files[index]);
      },
    );
  }
}

class _FoldersView extends ConsumerWidget {
  const _FoldersView({required this.state});
  final LanWorkspaceState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.sharedFolders.isEmpty) {
      return KarunEmptyState(
        icon: Icons.folder_shared_outlined,
        title: context.tr(LocaleKeys.noSharedFolders),
        subtitle: context.tr(LocaleKeys.foldersSubtitle),
      );
    }
    return ListView.builder(
      itemCount: state.sharedFolders.length,
      itemBuilder: (context, index) {
        final folder = state.sharedFolders[index];
        final isMine = folder.peerId == state.peerId;
        return _FolderShareTile(folder: folder, isMine: isMine);
      },
    );
  }
}

class _FolderShareTile extends ConsumerWidget {
  const _FolderShareTile({required this.folder, required this.isMine});
  final SharedFolder folder;
  final bool isMine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Icon(
          isMine ? Icons.folder_shared_rounded : Icons.folder_zip_rounded,
          color: AppColors.orange,
          size: 32,
        ),
        title: Text(
          folder.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          isMine
              ? '${context.tr(LocaleKeys.localFolder)} • ${folder.files.length} files'
              : 'Shared by ${folder.peerNickname} • ${folder.files.length} files',
        ),
        trailing: isMine
            ? TextButton.icon(
                label: Text(context.tr(LocaleKeys.unshare)),
                icon: const Icon(Icons.stop_screen_share_outlined, size: 18),
                onPressed: () => ref.read(lanWorkspaceProvider.notifier).unshareFolder(folder.shareId),
              )
            : const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () => _showFolderContentDialog(context, ref, folder),
      ),
    );
  }

  void _showFolderContentDialog(BuildContext context, WidgetRef ref, SharedFolder folder) {
    showDialog<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.folder_open, color: AppColors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      folder.name,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Shared by ${folder.peerNickname}',
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.slate),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: folder.files.isEmpty
                ? const Center(
                    child: Text('This folder is empty.'),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: folder.files.length,
                    itemBuilder: (context, index) {
                      final file = folder.files[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.file_present_outlined, size: 20),
                        title: Text(
                          file.fileName,
                          style: const TextStyle(fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          Utils.formatBytes(file.fileSize),
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: isMine
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.download, size: 18),
                                onPressed: () async {
                                  Navigator.pop(context);
                                  final didDownload = await ref.read(lanWorkspaceProvider.notifier).downloadFolderFile(
                                        shareId: folder.shareId,
                                        relativePath: file.relativePath,
                                        fileName: file.fileName,
                                      );
                                  if (context.mounted && didDownload) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Download complete!')),
                                    );
                                  }
                                },
                              ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
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
        subtitle: Text('Uploaded • ${Utils.formatBytes(file.bytes)}'),
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
