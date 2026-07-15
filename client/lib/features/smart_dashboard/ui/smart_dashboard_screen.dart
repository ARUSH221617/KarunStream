import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../extensions/build_context_extension.dart';
import '../../../generated/locale_keys.g.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/utils.dart';
import '../../karunstream/state/lan_workspace_controller.dart';
import '../../karunstream/model/file_transfer.dart';

class SmartDashboardScreen extends ConsumerWidget {
  const SmartDashboardScreen({super.key});

  String _getGreeting() {
    final currentHour = DateTime.now().hour;
    if (currentHour >= 5 && currentHour < 12) return LocaleKeys.goodMorning;
    if (currentHour >= 12 && currentHour < 18) return LocaleKeys.goodAfternoon;
    return LocaleKeys.goodEvening;
  }

  String _getHistoricalAverageSpeed(List<FileTransfer> files) {
    double totalBytes = 0;
    double totalSeconds = 0;
    for (final file in files) {
      if (file.durationSeconds > 0) {
        totalBytes += file.bytes.toDouble();
        totalSeconds += file.durationSeconds;
      }
    }
    if (totalSeconds == 0) return '0 B/s';
    final avgSpeedBytesPerSec = totalBytes / totalSeconds;
    return Utils.formatSpeed(avgSpeedBytesPerSec);
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

    try {
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
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to download: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lanWorkspaceProvider);

    final totalBytes = state.isConnected
        ? state.files.fold<int>(0, (sum, file) => sum + file.bytes)
        : 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 128),
      children: [
        Text(
          context.tr(_getGreeting()),
          style: AppTheme.title24.copyWith(color: context.primaryTextColor),
        ),
        const SizedBox(height: 8),
        Text(
          context.tr(LocaleKeys.dashboardDescription),
          style: AppTheme.body16.copyWith(color: context.secondaryTextColor),
        ),
        if (state.isTransferring) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: state.transferProgress,
                    backgroundColor: context.dividerColor,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.watermelon100),
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.stop_circle_outlined, color: AppColors.watermelon100),
                onPressed: () {
                  ref.read(lanWorkspaceProvider.notifier).cancelDownload();
                },
                tooltip: 'Cancel Transfer',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.92,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _DashboardCard(
              title: context.tr(LocaleKeys.activePeers),
              icon: Icons.people_outline,
              accentColor: AppColors.blueberry100,
              value: state.isConnected ? state.peers.length.toString() : '0',
              isAvailable: true,
            ),
            _DashboardCard(
              title: context.tr(LocaleKeys.totalTransfers),
              icon: Icons.swap_horiz_outlined,
              accentColor: AppColors.cempedak100,
              value: state.isConnected ? state.files.length.toString() : '0',
              isAvailable: true,
            ),
            _DashboardCard(
              title: context.tr(LocaleKeys.transferSpeed),
              icon: Icons.speed_outlined,
              accentColor: AppColors.watermelon100,
              isAvailable: true,
              valueWidget: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text('Live: ', style: AppTheme.body12.copyWith(color: context.secondaryTextColor)),
                      Expanded(
                        child: Text(
                          state.isConnected && state.isTransferring ? state.transferSpeed : '0 B/s',
                          style: AppTheme.title16.copyWith(color: context.primaryTextColor, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('Avg: ', style: AppTheme.body12.copyWith(color: context.secondaryTextColor)),
                      Expanded(
                        child: Text(
                          state.isConnected && state.isTransferring
                              ? state.transferAverageSpeed
                              : _getHistoricalAverageSpeed(state.files),
                          style: AppTheme.title16.copyWith(color: context.primaryTextColor, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _DashboardCard(
              title: context.tr(LocaleKeys.storageUsed),
              icon: Icons.storage_outlined,
              accentColor: AppColors.rambutan100,
              value: Utils.formatBytes(totalBytes),
              isAvailable: true,
            ),
          ],
        ),
        const SizedBox(height: 32),
        Text(
          context.tr(LocaleKeys.recentTransfers),
          style: AppTheme.title20.copyWith(color: context.primaryTextColor),
        ),
        const SizedBox(height: 16),
        if (!state.isConnected || state.files.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: context.secondaryWidgetColor,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.history_outlined,
                  size: 48,
                  color: AppColors.mono40,
                ),
                const SizedBox(height: 16),
                Text(
                  context.tr(LocaleKeys.noRecentTransfers),
                  style: AppTheme.body14
                      .copyWith(color: context.secondaryTextColor),
                ),
              ],
            ),
          )
        else
          Column(
            children: state.files.take(3).map((file) {
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: context.secondaryWidgetColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: context.dividerColor,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.blueberry100.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.cloud_done_outlined,
                        color: AppColors.blueberry100,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.fileName,
                            style: AppTheme.body16.copyWith(
                              color: context.primaryTextColor,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${context.tr(LocaleKeys.lanSharing)} • ${Utils.formatBytes(file.bytes)}',
                            style: AppTheme.body12.copyWith(
                              color: context.secondaryTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Download',
                      onPressed: () => _downloadFile(context, ref, transferId: file.transferId, fileName: file.fileName),
                      icon: const Icon(
                        Icons.download_outlined,
                        color: AppColors.blueberry100,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({
    required this.title,
    required this.icon,
    required this.accentColor,
    this.value,
    this.valueWidget,
    this.isAvailable = false,
  });

  final String title;
  final IconData icon;
  final Color accentColor;
  final String? value;
  final Widget? valueWidget;
  final bool isAvailable;

  @override
  Widget build(BuildContext context) {
    return Ink(
      decoration: BoxDecoration(
        color: context.secondaryWidgetColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isAvailable
              ? accentColor.withValues(alpha: 0.35)
              : context.dividerColor,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.gradient10,
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: accentColor, size: 30),
            ),
            const Spacer(),
            if (valueWidget != null)
              valueWidget!
            else
              Text(
                value ?? '',
                style: AppTheme.title20.copyWith(
                  color: context.primaryTextColor,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              title,
              style: AppTheme.body12.copyWith(
                color: context.secondaryTextColor,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
