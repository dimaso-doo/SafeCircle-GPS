import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_strings.dart';
import '../core/demo/demo_backend.dart';
import '../models/notification_settings.dart';

class NotificationRepository {
  NotificationRepository([this._client]);

  final SupabaseClient? _client;

  Future<NotificationSettings> getSettings(String userId) async {
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.getNotificationSettings(userId);
    }

    final client = _client!;
    final row = await client
        .from('notification_settings')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (row == null) {
      final created = await client
          .from('notification_settings')
          .upsert({'user_id': userId}, onConflict: 'user_id')
          .select()
          .single();
      return NotificationSettings.fromJson(created);
    }

    return NotificationSettings.fromJson(row);
  }

  Future<NotificationSettings> updateSettings({
    required String userId,
    bool? pushEnabled,
    bool? notifySos,
    bool? notifySafeZoneEnter,
    bool? notifySafeZoneExit,
    bool? notifySharingPaused,
  }) async {
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.upsertNotificationSettings(
        userId: userId,
        pushEnabled: pushEnabled,
        notifySos: notifySos,
        notifySafeZoneEnter: notifySafeZoneEnter,
        notifySafeZoneExit: notifySafeZoneExit,
        notifySharingPaused: notifySharingPaused,
      );
    }

    final client = _client!;
    final updated = await client
        .from('notification_settings')
        .upsert(
          {
            'user_id': userId,
            if (pushEnabled != null) 'push_enabled': pushEnabled,
            if (notifySos != null) 'notify_sos': notifySos,
            if (notifySafeZoneEnter != null) 'notify_safe_zone_enter': notifySafeZoneEnter,
            if (notifySafeZoneExit != null) 'notify_safe_zone_exit': notifySafeZoneExit,
            if (notifySharingPaused != null) 'notify_sharing_paused': notifySharingPaused,
          },
          onConflict: 'user_id',
        )
        .select()
        .single();

    return NotificationSettings.fromJson(updated);
  }

  Future<void> upsertDeviceToken({
    required String userId,
    required String token,
    required String platform,
    required String? appVersion,
    bool isActive = true,
  }) async {
    if (AppConfig.runInDemoMode) {
      return;
    }
    final client = _client!;
    await client.from('notification_tokens').upsert(
      {
        'user_id': userId,
        'token': token,
        'platform': platform,
        'app_version': appVersion,
        'is_active': isActive,
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'user_id,token',
    );
  }

  Future<void> deactivateDeviceToken(String token, {String? userId}) async {
    if (AppConfig.runInDemoMode) {
      return;
    }
    final client = _client!;
    if (userId == null) {
      await client
          .from('notification_tokens')
          .update({'is_active': false, 'updated_at': DateTime.now().toUtc().toIso8601String()})
          .eq('token', token);
      return;
    }

    await client
        .from('notification_tokens')
        .update({'is_active': false, 'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('user_id', userId)
        .eq('token', token);
  }
}
