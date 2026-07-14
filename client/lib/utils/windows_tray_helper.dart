import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

import '../features/common/ui/providers/windows_settings_provider.dart';
import '../features/karunstream/state/lan_workspace_controller.dart';

class WindowsTrayManager extends WindowListener {
  static final WindowsTrayManager _instance = WindowsTrayManager._internal();
  factory WindowsTrayManager() => _instance;
  WindowsTrayManager._internal();

  late final ProviderContainer _container;
  final SystemTray _systemTray = SystemTray();
  bool _initialized = false;

  Future<void> init(ProviderContainer container) async {
    if (kIsWeb || !Platform.isWindows) return;
    if (_initialized) return;
    _initialized = true;
    _container = container;

    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);

    // Initialize system tray icon
    await _systemTray.initSystemTray(
      title: "KarunStream",
      iconPath: 'assets/images/logo.ico',
      toolTip: "KarunStream: LAN Chat & File Sharing",
    );

    // Handle tray events
    _systemTray.registerSystemTrayEventHandler((eventName) {
      if (eventName == "leftMouseUp") {
        windowManager.show();
        windowManager.focus();
      } else if (eventName == "rightMouseUp") {
        _systemTray.popUpContextMenu();
      }
    });

    // Initial menu setup
    await _updateMenu();

    // Listen to connection state changes to update the menu dynamically
    _container.listen(
      lanWorkspaceProvider,
      (previous, next) {
        _updateMenu();
      },
    );

    // Listen to settings state changes to update the menu dynamically
    _container.listen(
      windowsSettingsProvider,
      (previous, next) {
        _updateMenu();
      },
    );
  }

  Future<void> _updateMenu() async {
    if (kIsWeb || !Platform.isWindows) return;

    final settings = _container.read(windowsSettingsProvider);
    final workspaceState = _container.read(lanWorkspaceProvider);
    
    final bool isConnected = workspaceState.isConnected;
    final String serverInfo = isConnected 
        ? "Connected to: ${workspaceState.serverUri?.host ?? 'LAN Server'}" 
        : "Disconnected";

    final String minimizeBox = settings.minimizeToTray ? "☑ " : "☐ ";
    final String autoConnectBox = settings.autoConnect ? "☑ " : "☐ ";

    final List<MenuItemBase> menu = [
      MenuItem(
        label: 'KarunStream ($serverInfo)',
        enabled: false,
      ),
      MenuSeparator(),
      MenuItem(
        label: 'Show App',
        onClicked: () async {
          await windowManager.show();
          await windowManager.focus();
        },
      ),
      MenuSeparator(),
      MenuItem(
        label: '$minimizeBox Minimize to Tray on Close',
        onClicked: () {
          _container.read(windowsSettingsProvider.notifier).setMinimizeToTray(!settings.minimizeToTray);
        },
      ),
      MenuItem(
        label: '$autoConnectBox Auto Connect on Startup',
        onClicked: () {
          _container.read(windowsSettingsProvider.notifier).setAutoConnect(!settings.autoConnect);
        },
      ),
      MenuSeparator(),
      if (isConnected)
        MenuItem(
          label: 'Disconnect',
          onClicked: () {
            _container.read(lanWorkspaceProvider.notifier).disconnect();
          },
        )
      else
        MenuItem(
          label: 'Auto Connect Now',
          onClicked: () {
            _container.read(lanWorkspaceProvider.notifier).autoDiscoverAndConnect();
          },
        ),
      MenuSeparator(),
      MenuItem(
        label: 'Exit',
        onClicked: () async {
          windowManager.removeListener(this);
          await windowManager.destroy();
          exit(0);
        },
      ),
    ];

    await _systemTray.setContextMenu(menu);
  }

  @override
  void onWindowClose() async {
    final settings = _container.read(windowsSettingsProvider);
    if (settings.minimizeToTray) {
      await windowManager.hide();
    } else {
      windowManager.removeListener(this);
      await windowManager.destroy();
      exit(0);
    }
  }
}
