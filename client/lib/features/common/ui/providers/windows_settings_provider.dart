import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../local/shared_preferences_provider.dart';

class WindowsSettingsState {
  final bool minimizeToTray;
  final bool autoConnect;

  WindowsSettingsState({
    required this.minimizeToTray,
    required this.autoConnect,
  });

  WindowsSettingsState copyWith({
    bool? minimizeToTray,
    bool? autoConnect,
  }) {
    return WindowsSettingsState(
      minimizeToTray: minimizeToTray ?? this.minimizeToTray,
      autoConnect: autoConnect ?? this.autoConnect,
    );
  }
}

class WindowsSettingsNotifier extends Notifier<WindowsSettingsState> {
  @override
  WindowsSettingsState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final minimizeToTray = prefs.getBool('karunstream_minimize_to_tray') ?? true;
    final autoConnect = prefs.getBool('karunstream_auto_connect') ?? true;
    return WindowsSettingsState(
      minimizeToTray: minimizeToTray,
      autoConnect: autoConnect,
    );
  }

  Future<void> setMinimizeToTray(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool('karunstream_minimize_to_tray', value);
    state = state.copyWith(minimizeToTray: value);
  }

  Future<void> setAutoConnect(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool('karunstream_auto_connect', value);
    state = state.copyWith(autoConnect: value);
  }
}

final windowsSettingsProvider =
    NotifierProvider<WindowsSettingsNotifier, WindowsSettingsState>(
  WindowsSettingsNotifier.new,
);
