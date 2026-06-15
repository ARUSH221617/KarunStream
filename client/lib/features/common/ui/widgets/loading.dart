import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '/constants/assets.dart';
import '/theme/app_colors.dart';

class Loading extends StatelessWidget {
  final bool isOverlay;
  final Color? backgroundColor;
  final double width;
  final double height;

  const Loading({
    super.key,
    this.isOverlay = true,
    this.backgroundColor,
    this.width = 120,
    this.height = 120,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Center(
      child: Lottie.asset(
        Assets.loading,
        width: width,
        height: height,
      ),
    );

    if (isOverlay) {
      return Container(
        constraints: const BoxConstraints.expand(),
        color: backgroundColor ?? AppColors.mono100.withValues(alpha: 0.68),
        child: content,
      );
    }

    return content;
  }
}
