class NotificationSettings {
  const NotificationSettings({
    required this.id,
    required this.userId,
    required this.pushEnabled,
    required this.notifySos,
    required this.notifySafeZoneEnter,
    required this.notifySafeZoneExit,
    required this.notifySharingPaused,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final bool pushEnabled;
  final bool notifySos;
  final bool notifySafeZoneEnter;
  final bool notifySafeZoneExit;
  final bool notifySharingPaused;
  final DateTime updatedAt;

  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    return NotificationSettings(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      pushEnabled: json['push_enabled'] as bool? ?? true,
      notifySos: json['notify_sos'] as bool? ?? true,
      notifySafeZoneEnter: json['notify_safe_zone_enter'] as bool? ?? true,
      notifySafeZoneExit: json['notify_safe_zone_exit'] as bool? ?? true,
      notifySharingPaused: json['notify_sharing_paused'] as bool? ?? true,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'push_enabled': pushEnabled,
        'notify_sos': notifySos,
        'notify_safe_zone_enter': notifySafeZoneEnter,
        'notify_safe_zone_exit': notifySafeZoneExit,
        'notify_sharing_paused': notifySharingPaused,
        'updated_at': updatedAt.toIso8601String(),
      };
}

