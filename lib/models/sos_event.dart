class SosEvent {
  const SosEvent({
    required this.id,
    required this.circleId,
    required this.userId,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.accuracyMeters,
    this.speedMps,
    this.headingDegrees,
    this.batteryLevel,
  });

  final String id;
  final String circleId;
  final String userId;
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final double? speedMps;
  final double? headingDegrees;
  final double? batteryLevel;
  final DateTime createdAt;

  factory SosEvent.fromJson(Map<String, dynamic> json) {
    return SosEvent(
      id: json['id'] as String,
      circleId: json['circle_id'] as String,
      userId: json['user_id'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracyMeters: (json['accuracy_meters'] as num?)?.toDouble(),
      speedMps: (json['speed_mps'] as num?)?.toDouble(),
      headingDegrees: (json['heading_degrees'] as num?)?.toDouble(),
      batteryLevel: (json['battery_level'] as num?)?.toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
