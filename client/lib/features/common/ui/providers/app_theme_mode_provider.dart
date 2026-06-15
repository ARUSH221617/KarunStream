import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../constants/constants.dart';
import '../../local/shared_preferences_provider.dart';

part 'app_theme_mode_provider.g.dart';

@riverpod
class AppThemeMode extends _$AppThemeMode {
  @override
  Future<ThemeMode> build() async {
    final prefs = ref.watch(sharedPreferencesProvider);
    final currentMode = prefs.getString(Constants.themeModeKey);
    return ThemeMode.values.firstWhere(
      (value) => currentMode == value.name,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> updateMode(ThemeMode mode) async {
    state = AsyncData(mode);
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setString(Constants.themeModeKey, mode.name);
  }
}
