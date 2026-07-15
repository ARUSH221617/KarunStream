import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../constants/constants.dart';
import '../../../constants/database_constants.dart';
import '../../../features/profile/model/profile.dart';
import '../../../utils/database_helper.dart';
import '../../common/local/shared_preferences_provider.dart';

part 'profile_repository.g.dart';

@Riverpod(keepAlive: true)
ProfileRepository profileRepository(Ref ref) {
  return ProfileRepository(ref.watch(sharedPreferencesProvider));
}

class ProfileRepository {
  const ProfileRepository(this._prefs);

  final SharedPreferences _prefs;

  Future<Profile?> get() async {
    final userId = _prefs.getString('logged_in_user_id');
    if (userId == null) return Profile();

    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      ProfileTable.tableName,
      where: '${ProfileTable.columnId} = ?',
      whereArgs: [userId],
    );

    if (maps.isEmpty) return Profile();

    final row = maps.first;
    return Profile(
      id: row[ProfileTable.columnId] as String?,
      email: row[ProfileTable.columnEmail] as String?,
      name: row[ProfileTable.columnName] as String?,
      job: row[ProfileTable.columnJob] as String?,
      avatar: row[ProfileTable.columnAvatar] as String?,
      diamond: row[ProfileTable.columnDiamond] as int?,
      expiryDatePremium: row[ProfileTable.columnExpiryDatePremium] != null
          ? DateTime.tryParse(row[ProfileTable.columnExpiryDatePremium] as String)
          : null,
      isLifetimePremium: row[ProfileTable.columnIsLifetimePremium] == 1,
    );
  }

  Future<void> update(Profile profile) async {
    final userId = profile.id;
    if (userId == null) return;

    final db = await DatabaseHelper.instance.database;
    final values = {
      if (profile.email != null) ProfileTable.columnEmail: profile.email,
      if (profile.name != null) ProfileTable.columnName: profile.name,
      if (profile.job != null) ProfileTable.columnJob: profile.job,
      if (profile.avatar != null) ProfileTable.columnAvatar: profile.avatar,
      if (profile.diamond != null) ProfileTable.columnDiamond: profile.diamond,
      if (profile.expiryDatePremium != null)
        ProfileTable.columnExpiryDatePremium: profile.expiryDatePremium!.toIso8601String(),
      if (profile.isLifetimePremium != null)
        ProfileTable.columnIsLifetimePremium: profile.isLifetimePremium! ? 1 : 0,
    };

    if (values.isNotEmpty) {
      await db.update(
        ProfileTable.tableName,
        values,
        where: '${ProfileTable.columnId} = ?',
        whereArgs: [userId],
      );
    }
  }

  Future<bool> wasShowOnboarding() async {
    return _prefs.getBool(Constants.wasShowOnboardingKey) ?? false;
  }

  Future<void> setWasShowOnboarding() async {
    await _prefs.setBool(Constants.wasShowOnboardingKey, true);
  }

  // Premium features removed for KarunStream
  Future<bool> isShowPremium() async {
    return false;
  }

  Future<void> setIsShowPremium() async {}
}
