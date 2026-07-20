class SubscriptionPlan {
  const SubscriptionPlan({
    required this.id,
    required this.slug,
    required this.name,
    required this.maxCircles,
    required this.maxMembersPerCircle,
    required this.maxHistoryRetentionHours,
    required this.allowSafeZones,
    required this.allowSos,
    required this.allowPriorityUpdates,
  });

  final String id;
  final String slug;
  final String name;
  final int maxCircles;
  final int maxMembersPerCircle;
  final int maxHistoryRetentionHours;
  final bool allowSafeZones;
  final bool allowSos;
  final bool allowPriorityUpdates;

  bool get isPremium => slug == 'premium';

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      id: json['id'] as String,
      slug: json['slug'] as String,
      name: json['name'] as String? ?? 'Unknown',
      maxCircles: (json['max_circles'] as num?)?.toInt() ?? 1,
      maxMembersPerCircle: (json['max_members_per_circle'] as num?)?.toInt() ?? 1,
      maxHistoryRetentionHours: (json['max_history_retention_hours'] as num?)?.toInt() ?? 24,
      allowSafeZones: json['allow_safe_zones'] as bool? ?? false,
      allowSos: json['allow_sos'] as bool? ?? false,
      allowPriorityUpdates: json['allow_priority_updates'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'slug': slug,
      'name': name,
      'max_circles': maxCircles,
      'max_members_per_circle': maxMembersPerCircle,
      'max_history_retention_hours': maxHistoryRetentionHours,
      'allow_safe_zones': allowSafeZones,
      'allow_sos': allowSos,
      'allow_priority_updates': allowPriorityUpdates,
    };
  }
}
