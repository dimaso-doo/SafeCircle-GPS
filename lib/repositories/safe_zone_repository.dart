import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_strings.dart';
import '../core/demo/demo_backend.dart';
import '../models/safe_zone.dart';

class SafeZoneRepository {
  SafeZoneRepository([this._client]);

  final SupabaseClient? _client;

  Future<List<SafeZone>> getSafeZonesForCircle(String circleId) async {
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.getSafeZonesForCircle(circleId);
    }
    final client = _client!;
    final rows = await client
        .from('safe_zones')
        .select()
        .eq('circle_id', circleId)
        .order('created_at', ascending: false);
    return rows.map((row) => SafeZone.fromJson(row)).toList();
  }

  Future<SafeZone> createSafeZone({
    required String circleId,
    required String name,
    required double centerLatitude,
    required double centerLongitude,
    required int radiusMeters,
    String? targetUserId,
  }) async {
    final activeUser = _activeUserOrThrow();
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.createSafeZone(
        circleId: circleId,
        name: name,
        centerLatitude: centerLatitude,
        centerLongitude: centerLongitude,
        radiusMeters: radiusMeters,
        targetUserId: targetUserId,
        createdBy: activeUser,
      );
    }
    final client = _client!;
    final row = await client
        .from('safe_zones')
        .insert({
          'circle_id': circleId,
          'name': name,
          'center_latitude': centerLatitude,
          'center_longitude': centerLongitude,
          'radius_meters': radiusMeters,
          'target_user_id': targetUserId,
        })
        .select()
        .single();
    return SafeZone.fromJson(row);
  }

  Future<SafeZone> updateSafeZone({
    required String zoneId,
    String? name,
    double? centerLatitude,
    double? centerLongitude,
    int? radiusMeters,
    String? targetUserId,
    bool? isActive,
    bool? clearTargetUser,
    required String circleId,
  }) async {
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.updateSafeZone(
        zoneId: zoneId,
        name: name,
        centerLatitude: centerLatitude,
        centerLongitude: centerLongitude,
        radiusMeters: radiusMeters,
        targetUserId: targetUserId,
        isActive: isActive,
        clearTargetUser: clearTargetUser,
        circleId: circleId,
      );
    }

    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (centerLatitude != null) updates['center_latitude'] = centerLatitude;
    if (centerLongitude != null) updates['center_longitude'] = centerLongitude;
    if (radiusMeters != null) updates['radius_meters'] = radiusMeters;
    if (clearTargetUser == true || targetUserId != null) {
      updates['target_user_id'] = targetUserId;
    }
    if (isActive != null) updates['is_active'] = isActive;

    final client = _client!;
    final row = await client
        .from('safe_zones')
        .update(updates)
        .eq('id', zoneId)
        .select()
        .single();
    return SafeZone.fromJson(row);
  }

  Future<void> deleteSafeZone(String zoneId) async {
    if (AppConfig.runInDemoMode) {
      final circleId = DemoBackend.shared.getCircleIdForSafeZone(zoneId);
      if (circleId == null) return;
      await DemoBackend.shared.deleteSafeZone(zoneId: zoneId, circleId: circleId);
      return;
    }

    final client = _client!;
    await client.from('safe_zones').delete().eq('id', zoneId);
  }

  Future<void> logEvent({
    required String zoneId,
    required String userId,
    required String eventType,
    DateTime? eventTimestamp,
  }) async {
    if (AppConfig.runInDemoMode) {
      await DemoBackend.shared.logSafeZoneEvent(
        zoneId: zoneId,
        userId: userId,
        eventType: eventType,
        eventTimestamp: eventTimestamp,
      );
      return;
    }
    final client = _client!;
    await client.from('safe_zone_events').insert({
      'zone_id': zoneId,
      'user_id': userId,
      'event_type': eventType,
      'event_timestamp': (eventTimestamp ?? DateTime.now()).toUtc().toIso8601String(),
    });
  }

  String _activeUserOrThrow() {
    final active = DemoBackend.shared.activeUser?.id;
    if (active == null) {
      throw StateError('Sign in required.');
    }
    return active;
  }
}
