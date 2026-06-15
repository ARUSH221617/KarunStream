# Project Gemini Instructions: ALC App (Flutter)

This repository contains the ALC App, a lightweight Flutter application built with a modern tech stack and clean architecture.

## Project Overview

- **Core Framework**: [Flutter](https://flutter.dev/) (Targeting iOS, Android, and potentially Web/Desktop).
- **Architecture**: **MVVM (Model-View-ViewModel)** with feature-based organization.
- **State Management**: [Riverpod](https://riverpod.dev/) (using `riverpod_annotation` for code generation).
- **Backend/Auth**: [Supabase](https://supabase.com/) via `supabase_flutter`.
- **Navigation**: [go_router](https://pub.dev/packages/go_router) for declarative routing.
- **Localization**: [easy_localization](https://pub.dev/packages/easy_localization) for multi-language support (English and Persian).
- **Persistence**: [sqflite](https://pub.dev/packages/sqflite) for local DB and [shared_preferences](https://pub.dev/packages/shared_preferences) for key-value storage.
- **Environment Management**: [envied](https://pub.dev/packages/envied) for secure environment variables.
- **In-App Purchases**: [RevenueCat](https://www.revenuecat.com/) via `purchases_flutter`.

## Project Structure

The project follows a feature-first structure under `lib/`:

- `constants/`: Global constants, asset paths, and database keys.
- `environment/`: Environment configuration (using Envied).
- `extensions/`: Dart extensions for `BuildContext`, `DateTime`, `String`, etc.
- `features/`: Modularized feature implementation.
  - `<feature_name>/`
    - `model/`: Data models (often using `freezed` or `json_serializable`).
    - `repository/`: Data source abstraction (Supabase, Local DB, etc.).
    - `ui/`: Presentation layer.
      - `state/`: Riverpod state classes.
      - `view_model/`: Riverpod `Notifier` classes containing business logic.
      - `widgets/`: Feature-specific reusable widgets.
- `routing/`: `go_router` configuration and route definitions.
- `theme/`: App-wide theme data (Light/Dark) and `AppColors`.
- `utils/`: Common utilities like `DatabaseHelper`, `Validator`, and `GlobalLoading`.

## Development Workflow

### Prerequisites

- Flutter SDK (>=3.4.3)
- Supabase project configured with `url` and `anonKey`.

### Setup

1.  **Install dependencies**:
    ```bash
    flutter pub get
    ```
2.  **Generate code**:
    Many files depend on code generation (Riverpod, Freezed, JSON, Envied). Run:
    ```bash
    dart run build_runner build --delete-conflicting-outputs
    ```
3.  **Generate localization keys**:
    ```bash
    dart run easy_localization:generate -f keys -o locale_keys.g.dart --source-dir assets/translations
    ```

### Running the App

```bash
flutter run
```

### Testing

```bash
flutter test
```

## Conventions & Best Practices

- **Naming**:
  - Files: `snake_case.dart`
  - Classes: `PascalCase`
  - Variables/Functions: `camelCase`
- **UI Design**:
  - Follow **Material 3** design principles.
  - Spacing, padding, and margins should be **multiples of 8** (e.g., `SizedBox(height: 16)`).
  - Use `BuildContext` extensions for theme access: `context.lightTheme`, `context.primaryColor`.
  - Use `AppTheme` for consistent text styles: `style: AppTheme.title12`.
- **State Management**:
  - Use `riverpod_annotation` (`@riverpod`) for defining providers.
  - ViewModels should extend `_$ViewModelName` and manage state through `AsyncValue`.
  - Prefer small, focused widgets that consume specific providers.
- **Localization**:
  - Add new strings to `assets/translations/en.json` and `fa.json`.
  - Access localized strings using `LocaleKeys.keyName.tr()`.
- **Error Handling**:
  - Use `AsyncValue.guard` in ViewModels to handle repository errors gracefully.
  - Use `GlobalLoading` for showing/hiding loading overlays during async operations.
- **Database**:
  - Manage local SQLite operations through `DatabaseHelper`.
  - Define table names and column names in `database_constants.dart`.

## Key Files to Reference

- `lib/main.dart`: App entry point and initialization logic.
- `lib/routing/router.dart`: Centralized routing configuration.
- `lib/theme/app_theme.dart`: Core theme definitions.
- `lib/environment/env.dart`: Environment variable mapping.
- `analysis_options.yaml`: Linting rules.
- `.cursorrules`: Project-specific AI behavior guidelines.
