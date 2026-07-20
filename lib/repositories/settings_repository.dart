import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_strings.dart';
import '../core/demo/demo_backend.dart';
import '../models/location_sharing_settings.dart';

class SettingsRepository {
  SettingsRepository([this._client]);

  final SupabaseClient? _client;

  Future<LocationSharingSettings> getSettings(String userId) async {
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.getSettings(userId);
    }

    final client = _client!;
    final row = await client
        .from('location_sharing_settings')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (row == null) {
      final created = await client
          .from('location_sharing_settings')
          .insert({
            'user_id': userId,
            'is_sharing_enabled': false,
            'is_paused': false,
            'is_background_sharing_enabled': false,
            'update_interval_seconds': 30,
            'distance_filter_meters': 100,
            'is_battery_saving_mode': false,
            'history_retention_hours': 24,
          })
          .select()
          .single();
      return LocationSharingSettings.fromJson(created);
    }
    return LocationSharingSettings.fromJson(row);
  }

  Future<LocationSharingSettings> setSharingEnabled({
    required String userId,
    required bool isEnabled,
  }) async {
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.setSharingEnabled(userId: userId, isEnabled: isEnabled);
    }

    final client = _client!;
    final updated = await client
        .from('location_sharing_settings')
        .upsert({'user_id': userId, 'is_sharing_enabled': isEnabled}, onConflict: 'user_id')
        .select()
        .single();
    return LocationSharingSettings.fromJson(updated);
  }

  Future<LocationSharingSettings> setPaused({
    required String userId,
    required bool isPaused,
  }) async {
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.setPaused(userId: userId, isPaused: isPaused);
    }

    final client = _client!;
    final updated = await client
        .from('location_sharing_settings')
        .upsert({'user_id': userId, 'is_paused': isPaused}, onConflict: 'user_id')
        .select()
        .single();
    return LocationSharingSettings.fromJson(updated);
  }

  Future<LocationSharingSettings> setBackgroundSharingEnabled({
    required String userId,
    required bool isEnabled,
  }) async {
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.setBackgroundSharingEnabled(userId: userId, isEnabled: isEnabled);
    }

    final client = _client!;
    final updated = await client
        .from('location_sharing_settings')
        .upsert({'user_id': userId, 'is_background_sharing_enabled': isEnabled},
            onConflict: 'user_id')
        .select()
        .single();
    return LocationSharingSettings.fromJson(updated);
  }

  Future<LocationSharingSettings> setUpdateInterval({
    required String userId,
    required int intervalSeconds,
  }) async {
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.setUpdateInterval(
          userId: userId, intervalSeconds: intervalSeconds.clamp(10, 900));
    }

    final interval = intervalSeconds.clamp(10, 900);
    final client = _client!;
    final updated = await client
        .from('location_sharing_settings')
        .upsert({'user_id': userId, 'update_interval_seconds': interval}, onConflict: 'user_id')
        .select()
        .single();
    return LocationSharingSettings.fromJson(updated);
  }

  Future<LocationSharingSettings> setDistanceFilter({
    required String userId,
    required int distanceMeters,
  }) async {
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.setDistanceFilter(
          userId: userId, distanceMeters: distanceMeters.clamp(10, 5000));
    }

    final distance = distanceMeters.clamp(10, 5000);
    final client = _client!;
    final updated = await client
        .from('location_sharing_settings')
        .upsert({'user_id': userId, 'distance_filter_meters': distance}, onConflict: 'user_id')
        .select()
        .single();
    return LocationSharingSettings.fromJson(updated);
  }

  Future<LocationSharingSettings> setBatterySavingMode({
    required String userId,
    required bool enabled,
  }) async {
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.setBatterySavingMode(userId: userId, enabled: enabled);
    }

    final client = _client!;
    final updated = await client
        .from('location_sharing_settings')
        .upsert({'user_id': userId, 'is_battery_saving_mode': enabled},
            onConflict: 'user_id')
        .select()
        .single();
    return LocationSharingSettings.fromJson(updated);
  }

  Future<LocationSharingSettings> setHistoryRetentionHours({
    required String userId,
    required int hours,
  }) async {
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.setHistoryRetentionHours(userId: userId, hours: hours);
    }

    final clamped = hours < 24 ? 24 : (hours > 720 ? 720 : hours);
    final client = _client!;
    final updated = await client
        .from('location_sharing_settings')
        .upsert({'user_id': userId, 'history_retention_hours': clamped}, onConflict: 'user_id')
        .select()
        .single();
    return LocationSharingSettings.fromJson(updated);
  }
}
