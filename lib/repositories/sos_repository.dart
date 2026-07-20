import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_strings.dart';
import '../core/demo/demo_backend.dart';
import '../models/sos_event.dart';

class SosRepository {
  SosRepository([this._client]);

  final SupabaseClient? _client;

  Future<SosEvent> createSosEvent({
    required String circleId,
    required String userId,
    required Position position,
    double? batteryLevel,
  }) async {
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.createSosEvent(
        circleId: circleId,
        userId: userId,
        position: position,
        batteryLevel: batteryLevel,
      );
    }

    final client = _client!;
    final row = await client
        .from('sos_events')
        .insert({
          'circle_id': circleId,
          'user_id': userId,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy_meters': position.accuracy,
          'speed_mps': position.speed,
          'heading_degrees': position.heading,
          'battery_level': batteryLevel,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select()
        .single();

    return SosEvent.fromJson(row);
  }
}
