import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../constants/constants.dart';
import '../../../features/profile/model/profile.dart';
import '../../../main.dart';

part 'profile_repository.g.dart';

@Riverpod(keepAlive: true)
ProfileRepository profileRepository(Ref ref) {
  return ProfileRepository();
}

class ProfileRepository {
  const ProfileRepository();

  Future<Profile?> get() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return Profile();

    final data = await supabase
        .from(Constants.supabaseProfileTable)
        .select()
        .eq('id', userId)
        .single();
    return Profile.fromJson(data);
  }

  Future<void> update(Profile profile) async {
    final userId = profile.id;
    if (userId == null) return;
    try {
      await supabase
          .from(Constants.supabaseProfileTable)
          .update({
            if (profile.email != null) 'email': profile.email,
            if (profile.name != null) 'name': profile.name,
            if (profile.job != null) 'job': profile.job,
            if (profile.avatar != null) 'avatar': profile.avatar,
            if (profile.diamond != null) 'diamond': profile.diamond,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId)
          .select();
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> wasShowOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(Constants.wasShowOnboardingKey) ?? false;
  }

  Future<void> setWasShowOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(Constants.wasShowOnboardingKey, true);
  }

  // Premium features removed for KarunStream
  Future<bool> isShowPremium() async {
    return false;
  }

  Future<void> setIsShowPremium() async {}
}
