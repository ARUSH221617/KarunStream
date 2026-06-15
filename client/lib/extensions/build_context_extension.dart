import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../features/common/ui/widgets/custom_snack_bar.dart';
import '../theme/app_colors.dart';

extension ThemeModeExtension on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  Color get primaryBackgroundColor =>
      isDarkMode ? AppColors.navy : AppColors.whiteBg;

  Color get secondaryBackgroundColor =>
      isDarkMode ? AppColors.navy : AppColors.whiteBg;

  Color get secondaryWidgetColor =>
      isDarkMode ? AppColors.slate : AppColors.mono20;

  Color get primaryTextColor =>
      isDarkMode ? AppColors.mono0 : AppColors.navy;

  Color get secondaryTextColor =>
      isDarkMode ? AppColors.mono40 : AppColors.slate;

  Color get dividerColor => isDarkMode ? AppColors.mono90 : AppColors.mono20;

  void showSuccessSnackBar(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(this).showSnackBar(
      CustomSnackBar.success(text: text, action: action),
    );
  }

  void showInfoSnackBar(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(this).showSnackBar(
      CustomSnackBar.info(text: text, action: action),
    );
  }

  void showWarningSnackBar(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(this).showSnackBar(
      CustomSnackBar.warning(text: text, action: action),
    );
  }

  void showErrorSnackBar(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(this).showSnackBar(
      CustomSnackBar.error(text: text, action: action),
    );
  }

  void hideKeyboard() {
    FocusScope.of(this).unfocus();
  }

  void tryLaunchUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url));
    } catch (e) {
      if (mounted) {
        showErrorSnackBar('Can not open url: $url');
      }
    }
  }
}
