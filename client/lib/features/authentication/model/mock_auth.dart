class User {
  final String id;
  final String email;
  final Map<String, dynamic>? userMetadata;

  User({required this.id, required this.email, this.userMetadata});

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'user_metadata': userMetadata,
      };

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      userMetadata: json['user_metadata'] as Map<String, dynamic>?,
    );
  }
}

class Session {
  final User user;
  Session({required this.user});

  Map<String, dynamic> toJson() => {
        'user': user.toJson(),
      };

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      user: User.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}

enum AuthChangeEvent {
  signedIn,
  signedOut,
  initialSession,
  mfaChallengeVerified,
  passwordRecovery,
  tokenRefreshed,
  userUpdated,
}

class AuthState {
  final AuthChangeEvent event;
  final Session? session;

  AuthState(this.event, this.session);
}

class AuthResponse {
  final User? user;
  final Session? session;

  AuthResponse({this.user, this.session});

  Map<String, dynamic> toJson() => {
        'user': user?.toJson(),
        'session': session?.toJson(),
      };

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      user: json['user'] == null
          ? null
          : User.fromJson(json['user'] as Map<String, dynamic>),
      session: json['session'] == null
          ? null
          : Session.fromJson(json['session'] as Map<String, dynamic>),
    );
  }
}
