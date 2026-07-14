import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:karunstream/features/common/local/shared_preferences_provider.dart';
import 'package:karunstream/features/common/ui/providers/windows_settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Windows Settings Provider Tests', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('initializes with default values when not set in SharedPreferences', () {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final settings = container.read(windowsSettingsProvider);

      expect(settings.minimizeToTray, isTrue);
      expect(settings.autoConnect, isTrue);
    });

    test('initializes with stored values from SharedPreferences', () async {
      await prefs.setBool('karunstream_minimize_to_tray', false);
      await prefs.setBool('karunstream_auto_connect', false);

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final settings = container.read(windowsSettingsProvider);

      expect(settings.minimizeToTray, isFalse);
      expect(settings.autoConnect, isFalse);
    });

    test('updates minimizeToTray value and stores in SharedPreferences', () async {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      await container.read(windowsSettingsProvider.notifier).setMinimizeToTray(false);

      final settings = container.read(windowsSettingsProvider);
      expect(settings.minimizeToTray, isFalse);
      expect(prefs.getBool('karunstream_minimize_to_tray'), isFalse);
    });

    test('updates autoConnect value and stores in SharedPreferences', () async {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      await container.read(windowsSettingsProvider.notifier).setAutoConnect(false);

      final settings = container.read(windowsSettingsProvider);
      expect(settings.autoConnect, isFalse);
      expect(prefs.getBool('karunstream_auto_connect'), isFalse);
    });
  });
}
