import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../routing/router.dart';
import '../../../theme/app_colors.dart';
import '../../common/ui/providers/app_theme_mode_provider.dart';

class KarunStreamApp extends ConsumerWidget {
  const KarunStreamApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(appThemeModeProvider).maybeWhen(
          data: (mode) => mode,
          orElse: () => ThemeMode.system,
        );

    return MaterialApp.router(
      title: 'KarunStream',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: themeMode,
      routerConfig: router,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
    );
  }

  ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.orange,
      brightness: brightness,
      primary: AppColors.orange,
      secondary: AppColors.slate,
      surface: isDark ? AppColors.navy : Colors.white,
    );

    const defaultFontFamily = 'Vazirmatn';
    const headlineFontFamily = 'Kanit';

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? AppColors.navy : Colors.white,
      fontFamily: defaultFontFamily,
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontFamily: headlineFontFamily),
        displayMedium: TextStyle(fontFamily: headlineFontFamily),
        displaySmall: TextStyle(fontFamily: headlineFontFamily),
        headlineLarge: TextStyle(fontFamily: headlineFontFamily),
        headlineMedium: TextStyle(fontFamily: headlineFontFamily),
        headlineSmall: TextStyle(fontFamily: headlineFontFamily),
        titleLarge: TextStyle(fontFamily: headlineFontFamily),
        titleMedium: TextStyle(fontFamily: headlineFontFamily),
        titleSmall: TextStyle(fontFamily: headlineFontFamily),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: isDark ? Colors.white : AppColors.navy,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: isDark ? AppColors.navy.withValues(alpha: 0.8) : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.orange,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.navy.withValues(alpha: 0.5) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.slate.withValues(alpha: 0.18)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.slate.withValues(alpha: 0.18)),
        ),
      ),
    );
  }
}
