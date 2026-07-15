import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../constants/constants.dart';
import '../../common/local/shared_preferences_provider.dart';
import '../model/mock_auth.dart';
import '../repository/authentication_repository.dart';

part 'auth_provider.g.dart';

@riverpod
Stream<AuthState> authState(Ref ref) {
  return ref.watch(authenticationRepositoryProvider).onAuthStateChange;
}

@riverpod
class IsGuestMode extends _$IsGuestMode {
  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getBool(Constants.isGuestModeKey) ?? false;
  }

  Future<void> setGuestMode(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(Constants.isGuestModeKey, value);
    state = value;
  }
}

@riverpod
bool isLoggedIn(Ref ref) {
  final isGuest = ref.watch(isGuestModeProvider);
  if (isGuest) return true;

  final authState = ref.watch(authStateProvider);
  return authState.maybeWhen(
    data: (state) => state.session != null,
    orElse: () => false,
  );
}
