import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_strings.dart';
import '../core/demo/demo_backend.dart';
import '../models/subscription_plan.dart';
import '../models/user_subscription.dart';

class SubscriptionRepository {
  SubscriptionRepository([this._client]);

  final SupabaseClient? _client;

  Future<UserSubscriptionState> getCurrentSubscription(String userId) async {
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.getSubscription(userId);
    }

    final client = _client!;
    final rows = await client
        .from('user_subscriptions')
        .select('id,status,started_at,expires_at,plan_id,subscription_plans(*)')
        .eq('user_id', userId)
        .order('started_at', ascending: false)
        .limit(1);

    final row = _findActiveSubscriptionRow(rows);
    if (row != null) {
      return UserSubscriptionState.fromJson({
        ...row,
        'user_id': userId,
      });
    }

    final fallbackPlan = await _fallbackPlan();
    return UserSubscriptionState.fromJson({
      'id': '',
      'user_id': userId,
      'status': 'active',
      'plan': fallbackPlan.toJson(),
      'max_circles': fallbackPlan.maxCircles,
      'max_members_per_circle': fallbackPlan.maxMembersPerCircle,
      'max_history_retention_hours': fallbackPlan.maxHistoryRetentionHours,
      'allow_safe_zones': fallbackPlan.allowSafeZones,
      'allow_sos': fallbackPlan.allowSos,
      'allow_priority_updates': fallbackPlan.allowPriorityUpdates,
    });
  }

  Future<UserSubscriptionState> _fallbackPlan() async {
    final planRow = await _fallbackPlanClient();
    return UserSubscriptionState.fromJson({
      'id': '',
      'user_id': '',
      'status': 'active',
      'plan': planRow.toJson(),
      'max_circles': planRow.maxCircles,
      'max_members_per_circle': planRow.maxMembersPerCircle,
      'max_history_retention_hours': planRow.maxHistoryRetentionHours,
      'allow_safe_zones': planRow.allowSafeZones,
      'allow_sos': planRow.allowSos,
      'allow_priority_updates': planRow.allowPriorityUpdates,
    });
  }

  Future<SubscriptionPlan> _fallbackPlanClient() async {
    final client = _client!;
    final planRow = await client.from('subscription_plans').select().eq('slug', 'free').single();
    if (planRow is! Map<String, dynamic>) {
      throw StateError('Missing free subscription plan in backend.');
    }
    return SubscriptionPlan.fromJson(planRow);
  }

  Map<String, dynamic>? _findActiveSubscriptionRow(List<dynamic> rows) {
    final now = DateTime.now().toUtc();

    for (final dynamic raw in rows) {
      if (raw is! Map<String, dynamic>) continue;

      final status = raw['status'] as String?;
      final expiresRaw = raw['expires_at'];
      final expiresAt = expiresRaw == null ? null : DateTime.tryParse(expiresRaw as String);
      final isActive = status == 'active' || status == 'trialing';
      final notExpired = expiresAt == null || expiresAt.isAfter(now);
      final hasPlan = raw['subscription_plans'] is Map<String, dynamic>;

      if (isActive && notExpired && hasPlan) {
        final planJson = raw['subscription_plans'] as Map<String, dynamic>;
        return {
          ...raw,
          'plan': planJson,
          'max_circles': planJson['max_circles'],
          'max_members_per_circle': planJson['max_members_per_circle'],
          'max_history_retention_hours': planJson['max_history_retention_hours'],
          'allow_safe_zones': planJson['allow_safe_zones'],
          'allow_sos': planJson['allow_sos'],
          'allow_priority_updates': planJson['allow_priority_updates'],
        };
      }
    }

    return null;
  }
}
