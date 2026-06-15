import 'dart:developer' as developer;

import 'package:easy_localization/easy_localization.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../constants/constants.dart';
import '../../../environment/env.dart';
import '../../../generated/locale_keys.g.dart';
import '../../../main.dart';
import '../../common/local/shared_preferences_provider.dart';

part 'authentication_repository.g.dart';

@riverpod
AuthenticationRepository authenticationRepository(Ref ref) {
  return AuthenticationRepository(ref.watch(sharedPreferencesProvider));
}

class AuthenticationRepository {
  const AuthenticationRepository(this._prefs);

  final SharedPreferences _prefs;

  static Future<void>? _googleInitializeFuture;

  Future<void> signInWithMagicLink(String email) async {
    try {
      await supabase.auth.signInWithOtp(
        email: email,
        emailRedirectTo: Constants.supabaseLoginCallback,
      );
    } on AuthException catch (error) {
      throw Exception(error.message);
    } catch (error) {
      throw Exception(LocaleKeys.unexpectedErrorOccurred.tr());
    }
  }

  Future<AuthResponse> verifyOtp({
    required String email,
    required String token,
    required bool isRegister,
  }) async {
    try {
      final result = await supabase.auth.verifyOTP(
        email: email,
        token: token,
        type: isRegister ? OtpType.signup : OtpType.magiclink,
      );
      return result;
    } on AuthException catch (error) {
      throw Exception(error.message);
    } catch (error) {
      throw Exception(LocaleKeys.unexpectedErrorOccurred.tr());
    }
  }

  Future<AuthResponse> signInWithGoogle() async {
    try {
      developer.log('${Constants.tag} [AuthRepo] Starting signInWithGoogle');
      const List<String> scopes = <String>[
        Constants.googleEmailScope,
        Constants.googleUserInfoScope,
      ];

      developer.log('${Constants.tag} [AuthRepo] Initializing GoogleSignIn');
      _googleInitializeFuture ??= GoogleSignIn.instance.initialize(
        clientId: Env.googleClientId,
        serverClientId: Env.googleServerClientId,
      );
      await _googleInitializeFuture;

      developer.log('${Constants.tag} [AuthRepo] Authenticating user');
      final googleUser = await GoogleSignIn.instance.authenticate(
        scopeHint: scopes,
      );

      developer
          .log('${Constants.tag} [AuthRepo] Getting authentication tokens');
      final googleAuth = googleUser.authentication;

      developer
          .log('${Constants.tag} [AuthRepo] Getting authorization for scopes');
      final googleAuthorization =
          await googleUser.authorizationClient.authorizationForScopes(scopes) ??
              await googleUser.authorizationClient.authorizeScopes(scopes);

      final accessToken = googleAuthorization.accessToken;
      final idToken = googleAuth.idToken;

      developer.log(
          '${Constants.tag} [AuthRepo] idToken: ${idToken != null ? "FOUND" : "NULL"}');
      developer.log('${Constants.tag} [AuthRepo] accessToken: FOUND');

      if (idToken == null) {
        throw Exception(LocaleKeys.idTokenNotFound.tr());
      }

      developer.log('${Constants.tag} [AuthRepo] Signing into Supabase');
      final result = await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      developer.log('${Constants.tag} [AuthRepo] Supabase sign in successful');
      return result;
    } on AuthException catch (error) {
      developer
          .log('${Constants.tag} [AuthRepo] AuthException: ${error.message}');
      throw Exception(error.message);
    } catch (error, stackTrace) {
      developer.log('${Constants.tag} [AuthRepo] Unexpected error: $error',
          error: error, stackTrace: stackTrace);
      throw Exception(LocaleKeys.unexpectedErrorOccurred.tr());
    }
  }

  Future<void> signOut() async {
    try {
      await supabase.auth.signOut();
    } on AuthException catch (error) {
      throw Exception(error.message);
    } catch (error) {
      throw Exception(LocaleKeys.unexpectedErrorOccurred.tr());
    }
  }

  Future<bool> isLogin() async {
    return supabase.auth.currentUser != null;
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
