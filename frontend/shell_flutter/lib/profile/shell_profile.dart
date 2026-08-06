/// Shared player identity for Table Games (durable across games).
class ShellProfile {
  final String nickname;
  final String avatarId;
  final DateTime updatedAt;

  const ShellProfile({
    required this.nickname,
    required this.avatarId,
    required this.updatedAt,
  });

  static const maxNicknameLength = 24;

  static String? validateNickname(String raw) {
    final nick = raw.trim();
    if (nick.isEmpty) return 'Pick a nickname';
    if (nick.length > maxNicknameLength) {
      return 'Nickname must be $maxNicknameLength characters or fewer';
    }
    return null;
  }

  ShellProfile copyWith({
    String? nickname,
    String? avatarId,
    DateTime? updatedAt,
  }) {
    return ShellProfile(
      nickname: nickname ?? this.nickname,
      avatarId: avatarId ?? this.avatarId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'nickname': nickname,
        'avatar_id': avatarId,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory ShellProfile.fromJson(Map<String, dynamic> json) {
    return ShellProfile(
      nickname: (json['nickname'] as String).trim(),
      avatarId: (json['avatar_id'] as String?) ?? 'face_01',
      updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
    );
  }
}
