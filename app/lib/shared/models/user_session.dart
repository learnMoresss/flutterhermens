class UserSession {
  const UserSession({
    this.token,
    this.expiresAt,
    this.username,
  });

  final String? token;
  final DateTime? expiresAt;
  final String? username;

  bool get isLoggedIn => token != null && token!.isNotEmpty;

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  static const empty = UserSession();

  UserSession copyWith({
    String? token,
    DateTime? expiresAt,
    String? username,
    bool clearToken = false,
  }) {
    return UserSession(
      token: clearToken ? null : (token ?? this.token),
      expiresAt: clearToken ? null : (expiresAt ?? this.expiresAt),
      username: clearToken ? null : (username ?? this.username),
    );
  }

  Map<String, dynamic> toJson() => {
        'token': token,
        'expiresAt': expiresAt?.toIso8601String(),
        'username': username,
      };

  factory UserSession.fromJson(Map<String, dynamic> json) {
    return UserSession(
      token: json['token'] as String?,
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'].toString())
          : null,
      username: json['username'] as String?,
    );
  }
}
