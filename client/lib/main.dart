import 'dart:developer' as developer;
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'features/common/local/shared_preferences_provider.dart';
import 'features/karunstream/ui/karunstream_app.dart';
import 'utils/windows_tray_helper.dart';

void main() async {
  developer.log('Starting main()...');
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  developer.log('WidgetsFlutterBinding initialized.');

  try {
    await EasyLocalization.ensureInitialized();
    developer.log('EasyLocalization initialized.');
  } catch (e) {
    developer.log('EasyLocalization initialization failed: $e');
  }

  try {
    final prefs = await SharedPreferences.getInstance();
    developer.log('SharedPreferences initialized.');

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );

    if (!kIsWeb && Platform.isWindows) {
      await WindowsTrayManager().init(container);
    }

    runApp(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('fa')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        child: UncontrolledProviderScope(
          container: container,
          child: const KarunStreamApp(),
        ),
      ),
    );
    developer.log('runApp() called.');
  } catch (e, stack) {
    developer.log('Initialization error: $e', error: e, stackTrace: stack);
  }
}
