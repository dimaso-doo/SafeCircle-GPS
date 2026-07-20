import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/safe_zone.dart';
import '../../../core/constants/app_strings.dart';
import '../../../repositories/safe_zone_repository.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/map/providers/map_provider.dart';
import '../../subscription/providers/subscription_provider.dart';

final safeZoneRepositoryProvider = Provider<SafeZoneRepository>((ref) {
  final client = AppConfig.runInDemoMode ? null : Supabase.instance.client;
  return SafeZoneRepository(client);
});

final safeZonesForActiveCircleProvider = FutureProvider.autoDispose<List<SafeZone>>((ref) async {
  final circleId = ref.watch(activeMapCircleIdProvider);
  if (circleId == null) return const <SafeZone>[];

  final repository = ref.watch(safeZoneRepositoryProvider);
  return repository.getSafeZonesForCircle(circleId);
});

final safeZoneControllerProvider = Provider((ref) => SafeZoneController(ref));

class SafeZoneController {
  SafeZoneController(this.ref);

  final Ref ref;

  Future<void> createZone({
    required String name,
    required double centerLatitude,
    required double centerLongitude,
    required int radiusMeters,
    String? targetUserId,
  }) async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;

    final circleId = ref.read(activeMapCircleIdProvider);
    if (circleId == null) return;

    final repository = ref.read(safeZoneRepositoryProvider);
    final subscription = await ref.read(subscriptionStateProvider.future);
    if (!subscription.canUseSafeZoneFeature()) {
      throw StateError('Safe zones are a Premium feature. Upgrade to continue.');
    }

    await repository.createSafeZone(
      circleId: circleId,
      name: name,
      centerLatitude: centerLatitude,
      centerLongitude: centerLongitude,
      radiusMeters: radiusMeters,
      targetUserId: targetUserId,
    );

    ref.invalidate(safeZonesForActiveCircleProvider);
  }

  Future<void> updateZone({
    required String zoneId,
    required String name,
    required double centerLatitude,
    required double centerLongitude,
    required int radiusMeters,
    String? targetUserId,
    bool? isActive,
    bool? clearTargetUser,
  }) async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;

    final repository = ref.read(safeZoneRepositoryProvider);
    final subscription = await ref.read(subscriptionStateProvider.future);
    if (!subscription.canUseSafeZoneFeature()) {
      throw StateError('Safe zones are a Premium feature. Upgrade to continue.');
    }

    final circleId = ref.read(activeMapCircleIdProvider);
    if (circleId == null) {
      throw StateError('Select a circle to update a safe zone.');
    }

    await repository.updateSafeZone(
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

    ref.invalidate(safeZonesForActiveCircleProvider);
  }

  Future<void> deleteZone(String zoneId) async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;

    final repository = ref.read(safeZoneRepositoryProvider);
    final subscription = await ref.read(subscriptionStateProvider.future);
    if (!subscription.canUseSafeZoneFeature()) {
      throw StateError('Safe zones are a Premium feature. Upgrade to continue.');
    }

    await repository.deleteSafeZone(zoneId);
    ref.invalidate(safeZonesForActiveCircleProvider);
  }

  Future<void> logZoneEvent({
    required String zoneId,
    required String eventType,
    required String userId,
    DateTime? eventTimestamp,
  }) async {
    final user = ref.read(authControllerProvider).user;
    if (user == null || user.id != userId) return;

    final repository = ref.read(safeZoneRepositoryProvider);
    await repository.logEvent(
      zoneId: zoneId,
      userId: user.id,
      eventType: eventType,
      eventTimestamp: eventTimestamp,
    );
  }
}
