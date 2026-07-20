class SafeZoneEvent {
  const SafeZoneEvent({
    required this.id,
    required this.zoneId,
    required this.userId,
    required this.eventType,
    required this.eventTimestamp,
    required this.createdAt,
  });

  final String id;
  final String zoneId;
  final String userId;
  final String eventType;
  final DateTime eventTimestamp;
  final DateTime createdAt;

  factory SafeZoneEvent.fromJson(Map<String, dynamic> json) {
    return SafeZoneEvent(
      id: json['id'] as String,
      zoneId: json['zone_id'] as String,
      userId: json['user_id'] as String,
      eventType: json['event_type'] as String,
      eventTimestamp: DateTime.parse(json['event_timestamp'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'zone_id': zoneId,
      'user_id': userId,
      'event_type': eventType,
      'event_timestamp': eventTimestamp.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}
