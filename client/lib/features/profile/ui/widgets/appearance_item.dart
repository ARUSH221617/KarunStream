import 'package:flutter/material.dart';

import '../../../../extensions/build_context_extension.dart';
import '../../../../features/profile/ui/widgets/common_rounded_item.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_theme.dart';

class AppearanceItem extends StatelessWidget {
  final Widget icon;
  final String text;
  final ThemeMode value;
  final bool isFirst;
  final bool isLast;

  const AppearanceItem({
    super.key,
    required this.icon,
    required this.text,
    required this.value,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return CommonRoundedItem(
      isFirst: isFirst,
      isLast: isLast,
      child: Container(
        height: 56,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: isLast
                ? BorderSide.none
                : BorderSide(color: context.dividerColor),
          ),
        ),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                height: 60,
                alignment: Alignment.centerLeft,
                child: Text(
                  text,
                  style: AppTheme.body16,
                ),
              ),
            ),
            Radio<ThemeMode>(
              value: value,
              fillColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? AppColors.blueberry100
                    : context.secondaryTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
