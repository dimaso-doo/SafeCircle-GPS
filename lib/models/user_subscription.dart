import '../core/config/release_access.dart';
import 'subscription_plan.dart';

class UserSubscriptionState {
  const UserSubscriptionState({
    required this.userId,
    required this.plan,
    required this.status,
    required this.subscriptionId,
    this.expiresAt,
    required this.maxHistoryRetentionHours,
    required this.maxCircles,
    required this.maxMembersPerCircle,
    required this.canUseSafeZones,
    required this.canUseSos,
    required this.canUsePriorityUpdates,
  });

  final String userId;
  final SubscriptionPlan plan;
  final String status;
  final String subscriptionId;
  final DateTime? expiresAt;
  final int maxHistoryRetentionHours;
  final int maxCircles;
  final int maxMembersPerCircle;
  final bool canUseSafeZones;
  final bool canUseSos;
  final bool canUsePriorityUpdates;

  bool get isPremium => plan.isPremium || ReleaseAccess.closedTestFullAccess;
  bool get isActive =>
      status == 'active' ||
      status == 'trialing' ||
      (status != 'expired' && status != 'canceled' && expiresAt == null);

  String get planName => plan.name;
  String get planSlug => plan.slug;
  int get minFreeUpdateIntervalSeconds => 10;
  int get minFreeDistanceFilterMeters => 10;
  int get freeHistoryRetentionHours => 24;

  bool canCreateOrJoinCircle(int currentCircleCount) {
    return currentCircleCount <
        (ReleaseAccess.closedTestFullAccess ? 100 : maxCircles);
  }

  bool canAddMemberInCircle(int currentMembers) {
    return currentMembers <
        (ReleaseAccess.closedTestFullAccess ? 100 : maxMembersPerCircle);
  }

  bool canKeepHistoryHours(int requestedHours) {
    return requestedHours <=
        (ReleaseAccess.closedTestFullAccess ? 720 : maxHistoryRetentionHours);
  }

  bool canSelectHistoryHours(int requestedHours) {
    return requestedHours <=
            (ReleaseAccess.closedTestFullAccess
                ? 720
                : maxHistoryRetentionHours) &&
        requestedHours >= freeHistoryRetentionHours;
  }

  bool canUsePriorityInterval(int seconds) {
    if (isPremium || canUsePriorityUpdates) return true;
    return seconds >= minFreeUpdateIntervalSeconds;
  }

  bool canUsePriorityDistance(int meters) {
    if (isPremium || canUsePriorityUpdates) return true;
    return meters >= minFreeDistanceFilterMeters;
  }

  bool canUseSafeZoneFeature() {
    return isPremium || canUseSafeZones;
  }

  bool canUseSosFeature() {
    return isPremium || canUseSos;
  }

  String planDescription() {
    if (ReleaseAccess.closedTestFullAccess) return 'Closed test access';
    if (isPremium) return 'Family+';
    return 'Free';
  }

  factory UserSubscriptionState.fromJson(Map<String, dynamic> json) {
    final planJson = json['plan'] is Map<String, dynamic> ? json['plan'] as Map<String, dynamic> : null;
    final expiresAtRaw = json['expires_at'];
    final rawPlan = planJson ??
        {
          'id': '',
          'slug': 'free',
          'name': 'Free',
          'max_circles': 1,
          'max_members_per_circle': 3,
          'max_history_retention_hours': 24,
          'allow_safe_zones': false,
          'allow_sos': false,
          'allow_priority_updates': true,
        };
    final plan = SubscriptionPlan.fromJson(rawPlan);

    return UserSubscriptionState(
      userId: json['user_id'] as String,
      plan: SubscriptionPlan.fromJson(rawPlan),
      status: json['status'] as String? ?? 'active',
      subscriptionId: json['id'] as String? ?? '',
      expiresAt: expiresAtRaw == null ? null : DateTime.tryParse(expiresAtRaw as String),
      maxHistoryRetentionHours:
          (json['max_history_retention_hours'] as num?)?.toInt() ??
              planFromMaxHistoryRetention(plan),
      maxCircles: (json['max_circles'] as num?)?.toInt() ?? (rawPlan['max_circles'] as num?)?.toInt() ?? 1,
      maxMembersPerCircle:
          (json['max_members_per_circle'] as num?)?.toInt() ??
          (rawPlan['max_members_per_circle'] as num?)?.toInt() ??
          3,
      canUseSafeZones: json['allow_safe_zones'] as bool? ?? plan.allowSafeZones,
      canUseSos: json['allow_sos'] as bool? ?? plan.allowSos,
      canUsePriorityUpdates: json['allow_priority_updates'] as bool? ?? plan.allowPriorityUpdates,
    );
  }

  static int planFromMaxHistoryRetention(SubscriptionPlan plan) => plan.maxHistoryRetentionHours;
}
