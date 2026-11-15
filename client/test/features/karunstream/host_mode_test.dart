import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karunstream/features/common/local/shared_preferences_provider.dart';
import 'package:karunstream/features/karunstream/state/lan_workspace_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LanWorkspaceController Host Mode Integration', () {
    late ProviderContainer container;

    setUp(() async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({
        'karunstream_auto_connect': false,
      });
      final prefs = await SharedPreferences.getInstance();

      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('starts and stops embedded host mode properly', () async {
      final controller = container.read(lanWorkspaceProvider.notifier);

      expect(controller.isHostMode, isFalse);
      expect(controller.embeddedServer, isNull);

      // Start Host Mode
      await controller.startHostMode(port: 0);

      expect(controller.isHostMode, isTrue);
      expect(controller.embeddedServer, isNotNull);
      expect(controller.embeddedServer!.isRunning, isTrue);
      expect(controller.embeddedServer!.port, greaterThan(0));

      // Wait a moment for loopback WebSocket connect to settle
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final state = container.read(lanWorkspaceProvider);
      expect(state.isHostMode, isTrue);
      expect(state.isConnected, isTrue);
      expect(state.serverUri?.port, equals(controller.embeddedServer!.port));

      // Stop Host Mode
      await controller.stopHostMode();

      expect(controller.isHostMode, isFalse);
      expect(controller.embeddedServer, isNull);
      final finalState = container.read(lanWorkspaceProvider);
      expect(finalState.isHostMode, isFalse);
      expect(finalState.isConnected, isFalse);
    });
  });
}
