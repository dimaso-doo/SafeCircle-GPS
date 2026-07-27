class LocationSharingSettings {
  const LocationSharingSettings({
    required this.id,
    required this.userId,
    required this.isSharingEnabled,
    required this.isPaused,
    required this.isBackgroundSharingEnabled,
    required this.updateIntervalSeconds,
    required this.distanceFilterMeters,
    required this.isBatterySavingMode,
    required this.historyRetentionHours,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final bool isSharingEnabled;
  final bool isPaused;
  final bool isBackgroundSharingEnabled;
  final int updateIntervalSeconds;
  final int distanceFilterMeters;
  final bool isBatterySavingMode;
  final int historyRetentionHours;
  final DateTime updatedAt;

  bool get canShare => isSharingEnabled && !isPaused;
  bool get isTrackingInBackgroundAllowed => isSharingEnabled && isBackgroundSharingEnabled;

  int get effectiveUpdateIntervalSeconds =>
      isBatterySavingMode ? (updateIntervalSeconds < 60 ? 60 : updateIntervalSeconds) : updateIntervalSeconds;

  int get effectiveDistanceFilterMeters =>
      isBatterySavingMode ? (distanceFilterMeters < 100 ? 100 : distanceFilterMeters) : distanceFilterMeters;

  int get defaultRetentionHours => 24;

  factory LocationSharingSettings.fromJson(Map<String, dynamic> json) {
    final rawInterval = (json['update_interval_seconds'] as num?)?.toInt();
    final rawDistanceFilter = (json['distance_filter_meters'] as num?)?.toInt();
    final rawHistoryRetention = (json['history_retention_hours'] as num?)?.toInt();

    return LocationSharingSettings(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      isSharingEnabled: json['is_sharing_enabled'] as bool,
      isPaused: json['is_paused'] as bool,
      isBackgroundSharingEnabled: json['is_background_sharing_enabled'] as bool? ?? false,
      updateIntervalSeconds: rawInterval == null ? 10 : rawInterval,
      distanceFilterMeters: rawDistanceFilter == null ? 10 : rawDistanceFilter,
      isBatterySavingMode: json['is_battery_saving_mode'] as bool? ?? false,
      historyRetentionHours: rawHistoryRetention == null ? 24 : rawHistoryRetention,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'is_sharing_enabled': isSharingEnabled,
        'is_paused': isPaused,
        'is_background_sharing_enabled': isBackgroundSharingEnabled,
        'update_interval_seconds': updateIntervalSeconds,
        'distance_filter_meters': distanceFilterMeters,
        'is_battery_saving_mode': isBatterySavingMode,
        'history_retention_hours': historyRetentionHours,
        'updated_at': updatedAt.toIso8601String(),
      };
}
