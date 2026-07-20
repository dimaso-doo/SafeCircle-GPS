class SafeZone {
  const SafeZone({
    required this.id,
    required this.circleId,
    required this.createdBy,
    this.targetUserId,
    required this.name,
    required this.centerLatitude,
    required this.centerLongitude,
    required this.radiusMeters,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String circleId;
  final String createdBy;
  final String? targetUserId;
  final String name;
  final double centerLatitude;
  final double centerLongitude;
  final int radiusMeters;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get appliesToAllMembers => targetUserId == null;

  factory SafeZone.fromJson(Map<String, dynamic> json) {
    return SafeZone(
      id: json['id'] as String,
      circleId: json['circle_id'] as String,
      createdBy: json['created_by'] as String,
      targetUserId: json['target_user_id'] as String?,
      name: json['name'] as String,
      centerLatitude: (json['center_latitude'] as num).toDouble(),
      centerLongitude: (json['center_longitude'] as num).toDouble(),
      radiusMeters: (json['radius_meters'] as num).toInt(),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'circle_id': circleId,
      'created_by': createdBy,
      'target_user_id': targetUserId,
      'name': name,
      'center_latitude': centerLatitude,
      'center_longitude': centerLongitude,
      'radius_meters': radiusMeters,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
