import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:go_router/go_router.dart';

import '../../../extensions/build_context_extension.dart';
import '../../../routing/routes.dart';
import '../../../theme/app_theme.dart';
import '../../common/ui/providers/app_theme_mode_provider.dart';
import '../model/main_tab.dart';

class MainScreen extends ConsumerStatefulWidget {
  final Widget child;
  const MainScreen({super.key, required this.child});

  @override
  ConsumerState createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith(Routes.dashboard)) return 0;
    if (location.startsWith(Routes.connect)) return 1;
    if (location.startsWith(Routes.chat)) return 2;
    if (location.startsWith(Routes.files)) return 3;
    if (location.startsWith(Routes.peers)) return 4;
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go(Routes.dashboard);
        break;
      case 1:
        context.go(Routes.connect);
        break;
      case 2:
        context.go(Routes.chat);
        break;
      case 3:
        context.go(Routes.files);
        break;
      case 4:
        context.go(Routes.peers);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _calculateSelectedIndex(context);
    final themeMode = ref.watch(appThemeModeProvider).maybeWhen(
          data: (mode) => mode,
          orElse: () => ThemeMode.system,
        );
    final isDarkMode = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system && context.isDarkMode);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          leading: Container(
            margin: const EdgeInsets.only(left: 16, right: 8),
            child: Image.asset('assets/images/logo.png', width: 32, height: 32),
          ),
          title: Text(
            'KarunStream',
            style: AppTheme.title24,
          ),
          actions: [
            IconButton(
              icon: Icon(
                isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                size: 24,
              ),
              onPressed: () {
                final nextMode = isDarkMode ? ThemeMode.light : ThemeMode.dark;
                ref.read(appThemeModeProvider.notifier).updateMode(nextMode);
              },
            ),
            IconButton(
              icon: const Icon(Icons.account_circle_outlined, size: 28),
              onPressed: () => context.push(Routes.profile),
            ),
            const SizedBox(width: 8),
          ],
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
        ),
        body: widget.child,
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: CurvedNavigationBar(
            index: selectedIndex,
            items: MainTab.values
                .map((tab) => Icon(tab.iconData, color: Colors.white))
                .toList(),
            onTap: (index) => _onItemTapped(index, context),
            color: isDark ? Colors.grey[850]! : const Color(0xFF0A1034),
            backgroundColor: Colors.transparent,
            buttonBackgroundColor: const Color(0xFF4361EE),
            height: 65,
            animationCurve: Curves.easeInOutCubic,
            animationDuration: const Duration(milliseconds: 400),
          ),
        ),
      ),
    );
  }
}
