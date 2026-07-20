class CircleMember {
  const CircleMember({
    required this.id,
    required this.circleId,
    required this.userId,
    required this.role,
    required this.isAccepted,
    required this.invitedAt,
    this.displayName,
    this.avatarUrl,
    this.userProfileId,
  });

  final String id;
  final String circleId;
  final String userId;
  final String role;
  final bool isAccepted;
  final DateTime? invitedAt;
  final String? displayName;
  final String? avatarUrl;
  final String? userProfileId;

  factory CircleMember.fromJson(Map<String, dynamic> json) {
    final user = json['users'];
    return CircleMember(
      id: json['id'] as String,
      circleId: json['circle_id'] as String,
      userId: json['user_id'] as String,
      role: json['role'] as String,
      isAccepted: (json['is_accepted'] as bool?) ?? false,
      invitedAt: json['invited_at'] == null
          ? null
          : DateTime.tryParse(json['invited_at'] as String),
      userProfileId: user is Map<String, dynamic> ? user['id'] as String? : null,
      displayName: user is Map<String, dynamic> ? user['display_name'] as String? : null,
      avatarUrl: user is Map<String, dynamic> ? user['avatar_url'] as String? : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'circle_id': circleId,
      'user_id': userId,
      'role': role,
      'is_accepted': isAccepted,
      'invited_at': invitedAt?.toIso8601String(),
      'users': {
        'id': userProfileId,
        'display_name': displayName,
        'avatar_url': avatarUrl,
      },
    };
  }
}
