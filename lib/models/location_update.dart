class LocationUpdate {
  const LocationUpdate({
    required this.id,
    required this.userId,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.altitude,
    this.batteryLevel,
    this.accuracy,
    this.speed,
    this.heading,
  });

  final String id;
  final String userId;
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? batteryLevel;
  final double? accuracy;
  final double? speed;
  final double? heading;
  final DateTime createdAt;

  factory LocationUpdate.fromJson(Map<String, dynamic> json) {
    return LocationUpdate(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble(),
      batteryLevel: (json['battery_level'] as num?)?.toDouble(),
      accuracy: (json['accuracy_meters'] as num?)?.toDouble(),
      speed: (json['speed_mps'] as num?)?.toDouble(),
      heading: (json['heading_degrees'] as num?)?.toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
      'id': id,
      'user_id': userId,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'battery_level': batteryLevel,
      'accuracy_meters': accuracy,
      'speed_mps': speed,
      'heading_degrees': heading,
      'created_at': createdAt.toIso8601String(),
      };
}
