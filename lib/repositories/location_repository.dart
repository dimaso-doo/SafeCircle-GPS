import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_strings.dart';
import '../core/demo/demo_backend.dart';
import '../models/location_update.dart';

class LocationRepository {
  LocationRepository([this._client]);

  final SupabaseClient? _client;

  Future<void> uploadLocationUpdate({
    required String userId,
    required Position position,
    double? batteryLevel,
  }) async {
    if (AppConfig.runInDemoMode) {
      await DemoBackend.shared.uploadLocationUpdate(
        userId: userId,
        position: position,
        batteryLevel: batteryLevel,
      );
      final circleIds = DemoBackend.shared.getCircleIdsForUser(userId);
      for (final circleId in circleIds) {
        DemoBackend.shared.seedDemoLocationsForMembers(circleId);
      }
      return;
    }

    final client = _client!;
    await client.from('location_updates').insert({
      'user_id': userId,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'altitude': position.altitude,
      'battery_level': batteryLevel,
      'accuracy_meters': position.accuracy,
      'speed_mps': position.speed,
      'heading_degrees': position.heading,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<LocationUpdate>> fetchHistory(String userId, {int limit = 100}) async {
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.fetchHistory(userId, limit: limit);
    }

    final client = _client!;
    final rows = await client
        .from('location_updates')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map((row) => LocationUpdate.fromJson(row)).toList();
  }

  Future<List<LocationUpdate>> fetchHistoryForMember({
    required String userId,
    required DateTime from,
    DateTime? to,
    int limit = 200,
  }) async {
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.fetchHistoryForMember(
        userId: userId,
        from: from,
        to: to,
        limit: limit,
      );
    }

    final client = _client!;
    final query = client
        .from('location_updates')
        .select(
          'id, user_id, latitude, longitude, altitude, accuracy_meters, speed_mps, heading_degrees, battery_level, created_at',
        )
        .eq('user_id', userId)
        .gte('created_at', from.toUtc().toIso8601String())
        .order('created_at', ascending: false)
        .limit(limit);

    final withTo = to == null ? query : query.lte('created_at', to.toUtc().toIso8601String());
    final rows = await withTo;
    return rows.map((row) => LocationUpdate.fromJson(row)).toList();
  }

  Future<Map<String, LocationUpdate>> fetchLatestLocationByUsers(List<String> userIds) async {
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.fetchLatestLocationByUsers(userIds);
    }

    if (userIds.isEmpty) {
      return {};
    }

    final client = _client!;
    final rows = await client
        .from('location_updates')
        .select(
          'id, user_id, latitude, longitude, altitude, accuracy_meters, speed_mps, heading_degrees, battery_level, created_at',
        )
        .inFilter('user_id', userIds)
        .order('created_at', ascending: false);

    final latest = <String, LocationUpdate>{};
    for (final row in rows) {
      final userId = row['user_id'] as String;
      if (!latest.containsKey(userId)) {
        latest[userId] = LocationUpdate.fromJson(row);
      }
    }

    return latest;
  }

}
