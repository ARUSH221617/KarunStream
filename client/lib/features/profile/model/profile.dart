// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'profile.freezed.dart';

part 'profile.g.dart';

@freezed
abstract class Profile with _$Profile {
  const factory Profile({
    String? id,
    String? email,
    String? name,
    String? job,
    String? avatar,
    int? diamond,
    @JsonKey(name: 'expiry_date_premium') DateTime? expiryDatePremium,
    @JsonKey(name: 'is_lifetime_premium') bool? isLifetimePremium,
  }) = _Profile;

  factory Profile.fromJson(Map<String, Object?> json) =>
      _$ProfileFromJson(json);
}
