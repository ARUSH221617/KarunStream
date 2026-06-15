import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../extensions/build_context_extension.dart';
import '../../../generated/locale_keys.g.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';

class SmartDashboardScreen extends ConsumerWidget {
  const SmartDashboardScreen({super.key});

  String _getGreeting() {
    final currentHour = DateTime.now().hour;
    if (currentHour >= 5 && currentHour < 12) return LocaleKeys.goodMorning;
    if (currentHour >= 12 && currentHour < 18) return LocaleKeys.goodAfternoon;
    return LocaleKeys.goodEvening;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              value: '0',
              isAvailable: true,
            ),
            _DashboardCard(
              title: context.tr(LocaleKeys.totalTransfers),
              icon: Icons.swap_horiz_outlined,
              accentColor: AppColors.cempedak100,
              value: '0',
              isAvailable: true,
            ),
            _DashboardCard(
              title: context.tr(LocaleKeys.transferSpeed),
              icon: Icons.speed_outlined,
              accentColor: AppColors.watermelon100,
              value: '0 MB/s',
              isAvailable: true,
            ),
            _DashboardCard(
              title: context.tr(LocaleKeys.storageUsed),
              icon: Icons.storage_outlined,
              accentColor: AppColors.rambutan100,
              value: '0 GB',
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
    required this.value,
    this.isAvailable = false,
  });

  final String title;
  final IconData icon;
  final Color accentColor;
  final String value;
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
            Text(
              value,
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
