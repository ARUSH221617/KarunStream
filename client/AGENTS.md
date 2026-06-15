# Repository Guidelines

## Project Structure & Module Organization
This is a Flutter app using MVVM-style feature modules and Riverpod state management. App source lives in `lib/`. Feature code is grouped under `lib/features/<feature>/` with typical subfolders such as `model/`, `repository/`, `ui/`, `state/`, `view_model/`, and `widgets/`. Shared UI, local storage, and remote client utilities are under `lib/features/common/`. Routing is in `lib/routing/`, theme files are in `lib/theme/`, constants are in `lib/constants/`, and generated localization keys are in `lib/generated/`. Assets are declared in `pubspec.yaml` and stored in `assets/animations/`, `assets/images/`, `assets/google_fonts/`, and `assets/translations/`. Tests currently live in `test/`.

## Build, Test, and Development Commands
- `flutter pub get` installs dependencies from `pubspec.yaml`.
- `flutter run` launches the app on a connected device or emulator.
- `flutter analyze` runs the Dart analyzer and configured Flutter lints.
- `flutter test` runs unit and widget tests in `test/`.
- `dart run build_runner build --delete-conflicting-outputs` regenerates Riverpod, Freezed, JSON, and Envied outputs after changing annotated files.
- `dart format lib test` formats Dart source.

## Coding Style & Naming Conventions
Use standard Dart formatting with 2-space indentation. Follow `package:flutter_lints/flutter.yaml` from `analysis_options.yaml`. Prefer feature-local files and keep widgets small. Name Dart files with `snake_case.dart`; classes, widgets, models, and providers use `PascalCase`/`camelCase` according to Dart conventions. Keep generated files (`*.g.dart`, `*.freezed.dart`) in sync with source annotations. User-facing strings should use Easy Localization keys (`LocaleKeys.*` plus `context.tr(...)`) and translation JSON files.

## Testing Guidelines
Use `flutter_test` for widget/unit tests and `test` for pure Dart tests. Add tests beside existing tests under `test/`, using descriptive names such as `profile_view_model_test.dart` or `smart_dashboard_screen_test.dart`. Run `flutter test` before opening a PR. Add regression tests when fixing bugs or changing view-model logic.

## Commit & Pull Request Guidelines
Recent history uses short imperative messages, for example `Add smart dashboard controls` and `Fix Flutter analyzer issues`. Keep commits focused and descriptive. Pull requests should include a concise summary, testing notes, linked issues when applicable, and screenshots or screen recordings for UI changes.

## Security & Configuration Tips
Do not commit secrets. Treat `.env`, platform signing files, and API keys as sensitive. When adding assets or localization files, update `pubspec.yaml` or all translation JSONs as needed.
