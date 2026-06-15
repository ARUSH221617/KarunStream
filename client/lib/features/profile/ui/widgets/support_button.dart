import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../../constants/constants.dart';
import '../../../../extensions/build_context_extension.dart';
import '../../../../generated/locale_keys.g.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_theme.dart';
import '../../../common/ui/widgets/material_ink_well.dart';

class SupportButton extends StatelessWidget {
  const SupportButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.premiumBackground,
        borderRadius: BorderRadius.circular(24),
      ),
      child: MaterialInkWell(
        onTap: () => context.tryLaunchUrl(Constants.telegramSupport),
        radius: 24,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedTelegram,
                color: AppColors.mono0,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                LocaleKeys.support.tr(),
                style: AppTheme.title16.copyWith(color: AppColors.mono0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
