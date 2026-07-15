import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../constants/constants.dart';
import '../../../constants/database_constants.dart';
import '../../../utils/database_helper.dart';
import '../../common/local/shared_preferences_provider.dart';
import '../model/mock_auth.dart';

part 'authentication_repository.g.dart';

@riverpod
AuthenticationRepository authenticationRepository(Ref ref) {
  return AuthenticationRepository(ref.watch(sharedPreferencesProvider));
}

class AuthenticationRepository {
  const AuthenticationRepository(this._prefs);

  final SharedPreferences _prefs;

  static final StreamController<AuthState> _authStreamController =
      StreamController<AuthState>.broadcast();

  Stream<AuthState> get onAuthStateChange async* {
    final session = await getCurrentSession();
    yield AuthState(AuthChangeEvent.initialSession, session);
    yield* _authStreamController.stream;
  }

  Future<Session?> getCurrentSession() async {
    final userId = _prefs.getString('logged_in_user_id');
    if (userId == null) return null;

    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      ProfileTable.tableName,
      where: '${ProfileTable.columnId} = ?',
      whereArgs: [userId],
    );

    if (maps.isEmpty) return null;

    final row = maps.first;
    final user = User(
      id: row[ProfileTable.columnId] as String,
      email: row[ProfileTable.columnEmail] as String,
      userMetadata: {'full_name': row[ProfileTable.columnName]},
    );
    return Session(user: user);
  }

  Future<void> signInWithMagicLink(String email) async {
    // Mock magic link: check if user exists, if not we will register them in verifyOtp
    // No-op, verifyOtp will handle the actual login/registration
  }

  Future<AuthResponse> verifyOtp({
    required String email,
    required String token,
    required bool isRegister,
  }) async {
    // ponytail: mock OTP verification. Upgrade path: implement local network-based peer verification or local PIN.
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      ProfileTable.tableName,
      where: '${ProfileTable.columnEmail} = ?',
      whereArgs: [email],
    );

    User user;
    if (maps.isEmpty) {
      if (isRegister) {
        final id = const Uuid().v4();
        final nickname = email.split('@').first;
        await db.insert(
          ProfileTable.tableName,
          {
            ProfileTable.columnId: id,
            ProfileTable.columnEmail: email,
            ProfileTable.columnPassword: '', // No password for OTP/Magic link
            ProfileTable.columnName: nickname,
          },
        );
        user = User(id: id, email: email, userMetadata: {'full_name': nickname});
      } else {
        throw Exception('User not found');
      }
    } else {
      final row = maps.first;
      user = User(
        id: row[ProfileTable.columnId] as String,
        email: row[ProfileTable.columnEmail] as String,
        userMetadata: {'full_name': row[ProfileTable.columnName]},
      );
    }

    final session = Session(user: user);
    final response = AuthResponse(user: user, session: session);

    await _prefs.setString('logged_in_user_id', user.id);
    _authStreamController.add(AuthState(AuthChangeEvent.signedIn, session));

    return response;
  }

  int getFailedAttempts() {
    return _prefs.getInt('auth_failed_attempts') ?? 0;
  }

  Future<void> incrementFailedAttempts() async {
    final current = getFailedAttempts() + 1;
    await _prefs.setInt('auth_failed_attempts', current);

    int lockoutDurationSeconds = 0;
    if (current >= 10) {
      lockoutDurationSeconds = 300; // 5 minutes
    } else if (current >= 5) {
      lockoutDurationSeconds = 60;  // 1 minute
    } else if (current >= 3) {
      lockoutDurationSeconds = 30;  // 30 seconds
    }

    if (lockoutDurationSeconds > 0) {
      final lockoutEndTime = DateTime.now().millisecondsSinceEpoch + (lockoutDurationSeconds * 1000);
      await _prefs.setInt('auth_lockout_timestamp', lockoutEndTime);
    }
  }

  Future<void> clearFailedAttempts() async {
    await _prefs.remove('auth_failed_attempts');
    await _prefs.remove('auth_lockout_timestamp');
  }

  int getLockoutTimeRemaining() {
    final lockoutTimestamp = _prefs.getInt('auth_lockout_timestamp') ?? 0;
    if (lockoutTimestamp == 0) return 0;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now >= lockoutTimestamp) {
      _prefs.remove('auth_lockout_timestamp');
      return 0;
    }

    return ((lockoutTimestamp - now) / 1000).ceil();
  }

  Future<AuthResponse> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final secondsRemaining = getLockoutTimeRemaining();
    if (secondsRemaining > 0) {
      throw Exception('tooManyAttempts'.tr(args: [secondsRemaining.toString()]));
    }

    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      ProfileTable.tableName,
      where: '${ProfileTable.columnEmail} = ? AND ${ProfileTable.columnPassword} = ?',
      whereArgs: [email, password],
    );

    if (maps.isEmpty) {
      await incrementFailedAttempts();
      throw Exception('Invalid email or password');
    }

    final row = maps.first;
    final user = User(
      id: row[ProfileTable.columnId] as String,
      email: row[ProfileTable.columnEmail] as String,
      userMetadata: {'full_name': row[ProfileTable.columnName]},
    );
    final session = Session(user: user);
    final response = AuthResponse(user: user, session: session);

    await clearFailedAttempts();
    await _prefs.setString('logged_in_user_id', user.id);
    _authStreamController.add(AuthState(AuthChangeEvent.signedIn, session));

    return response;
  }

  Future<AuthResponse> signUpWithEmailAndPassword({
    required String email,
    required String password,
    required String nickname,
  }) async {
    final db = await DatabaseHelper.instance.database;

    final List<Map<String, dynamic>> existing = await db.query(
      ProfileTable.tableName,
      where: '${ProfileTable.columnEmail} = ?',
      whereArgs: [email],
    );
    if (existing.isNotEmpty) {
      throw Exception('Email already registered');
    }

    final id = const Uuid().v4();
    await db.insert(
      ProfileTable.tableName,
      {
        ProfileTable.columnId: id,
        ProfileTable.columnEmail: email,
        ProfileTable.columnPassword: password,
        ProfileTable.columnName: nickname,
      },
    );

    final user = User(id: id, email: email, userMetadata: {'full_name': nickname});
    final session = Session(user: user);
    final response = AuthResponse(user: user, session: session);

    await _prefs.setString('logged_in_user_id', id);
    _authStreamController.add(AuthState(AuthChangeEvent.signedIn, session));

    return response;
  }

  Future<void> signOut() async {
    await _prefs.remove('logged_in_user_id');
    _authStreamController.add(AuthState(AuthChangeEvent.signedOut, null));
  }

  Future<bool> isLogin() async {
    final userId = _prefs.getString('logged_in_user_id');
    return userId != null;
  }

  Future<void> setIsLogin(bool value) async {
    await _prefs.setBool(Constants.isLoginKey, value);
  }

  Future<bool> isExistAccount() async {
    return _prefs.getBool(Constants.isExistAccountKey) ?? false;
  }

  Future<void> setIsExistAccount(bool value) async {
    await _prefs.setBool(Constants.isExistAccountKey, value);
  }

  Future<bool> isGuestMode() async {
    return _prefs.getBool(Constants.isGuestModeKey) ?? false;
  }

  Future<void> setIsGuestMode() async {
    await _prefs.setBool(Constants.isGuestModeKey, true);
  }
}
