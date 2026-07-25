import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/constants/app_strings.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../core/demo/demo_backend.dart';
import '../../../repositories/location_repository.dart';
import '../../../repositories/circle_repository.dart';
import '../../../services/location/location_service.dart';
import '../../../features/circles/models/circle_member.dart';
import '../../../features/circles/providers/circle_providers.dart';

final locationServiceProvider = Provider<LocationService>((_) => LocationService());

final mapLocationRepositoryProvider = Provider<LocationRepository>((ref) {
  final client = AppConfig.runInDemoMode ? null : Supabase.instance.client;
  return LocationRepository(client);
});

final permissionStateProvider = FutureProvider((ref) {
  if (AppConfig.runInDemoMode) {
    return LocationPermissionState.granted;
  }
  return ref.watch(locationServiceProvider).checkPermission();
});

final backgroundPermissionGrantedProvider = FutureProvider<bool>((ref) async {
  if (AppConfig.runInDemoMode) return true;
  final permission = await ref.watch(locationServiceProvider).checkRawPermission();
  return permission == LocationPermission.always;
});

final currentPositionProvider = FutureProvider.autoDispose<Position>((ref) async {
  if (AppConfig.runInDemoMode) {
    final user = ref.watch(authControllerProvider).user;
    if (user == null) {
      throw StateError('Sign in required.');
    }
    DemoBackend.shared.seedLatestForUser(user.id);
    return DemoBackend.shared.latestPositionFor(user.id);
  }

  return ref.watch(locationServiceProvider).currentLocation();
});

final activeMapCircleIdProvider = Provider<String?>((ref) {
  final explicitCircleId = ref.watch(selectedCircleIdProvider);
  if (explicitCircleId != null) {
    return explicitCircleId;
  }

  final circlesState = ref.watch(circlesProvider);
  final circles = circlesState.valueOrNull;
  if (circles == null || circles.isEmpty) {
    return null;
  }

  return circles.first.id;
});

final activeMapMembersProvider = FutureProvider.autoDispose<List<CircleMember>>((ref) async {
  final circleId = ref.watch(activeMapCircleIdProvider);
  if (circleId == null) return const <CircleMember>[];
  final repository = ref.watch(circleRepositoryProvider);

  final members = await repository.getMembersForCircle(circleId);
  return members.where((member) => member.isAccepted).toList(growable: false);
});

final canShareLocationProvider = FutureProvider.autoDispose<bool>((ref) async {
  final user = ref.watch(authControllerProvider).user;
  if (user == null) return false;
  final members = await ref.watch(activeMapMembersProvider.future);
  return members.any(
    (member) => member.userId == user.id && member.isAccepted,
  );
});
