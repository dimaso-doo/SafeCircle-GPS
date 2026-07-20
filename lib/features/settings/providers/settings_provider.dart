import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_strings.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/subscription/providers/subscription_provider.dart';
import '../../../repositories/settings_repository.dart';
import '../../../models/location_sharing_settings.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final client = AppConfig.runInDemoMode ? null : Supabase.instance.client;
  return SettingsRepository(client);
});

final mapLocationSettingsProvider = FutureProvider<LocationSharingSettings>((ref) async {
  final user = ref.watch(authControllerProvider).user;
  if (user == null) {
    throw StateError('Not signed in');
  }
  final repo = ref.watch(settingsRepositoryProvider);
  return repo.getSettings(user.id);
});

class SettingsController {
  SettingsController(this.ref);

  final Ref ref;

  Future<void> setSharingEnabled(bool value) async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;
    final repo = ref.read(settingsRepositoryProvider);
    await repo.setSharingEnabled(userId: user.id, isEnabled: value);
    ref.invalidate(mapLocationSettingsProvider);
  }

  Future<void> setPaused(bool value) async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;
    final repo = ref.read(settingsRepositoryProvider);
    await repo.setPaused(userId: user.id, isPaused: value);
    ref.invalidate(mapLocationSettingsProvider);
  }

  Future<void> setBackgroundSharingEnabled(bool value) async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;
    final repo = ref.read(settingsRepositoryProvider);
    await repo.setBackgroundSharingEnabled(userId: user.id, isEnabled: value);
    ref.invalidate(mapLocationSettingsProvider);
  }

  Future<void> setUpdateInterval(int intervalSeconds) async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;
    final subscription = await ref.read(subscriptionStateProvider.future);
    if (!subscription.canUsePriorityInterval(intervalSeconds)) {
      throw StateError('Upgrade to Premium for priority update intervals under 30 seconds.');
    }

    final repo = ref.read(settingsRepositoryProvider);
    await repo.setUpdateInterval(userId: user.id, intervalSeconds: intervalSeconds);
    ref.invalidate(mapLocationSettingsProvider);
  }

  Future<void> setDistanceFilter(int distanceMeters) async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;
    final subscription = await ref.read(subscriptionStateProvider.future);
    if (!subscription.canUsePriorityDistance(distanceMeters)) {
      throw StateError('Upgrade to Premium for tighter movement distance than ${subscription.minFreeDistanceFilterMeters}m.');
    }

    final repo = ref.read(settingsRepositoryProvider);
    await repo.setDistanceFilter(userId: user.id, distanceMeters: distanceMeters);
    ref.invalidate(mapLocationSettingsProvider);
  }

  Future<void> setBatterySavingMode(bool enabled) async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;
    final repo = ref.read(settingsRepositoryProvider);
    await repo.setBatterySavingMode(userId: user.id, enabled: enabled);
    ref.invalidate(mapLocationSettingsProvider);
  }

  Future<void> setHistoryRetentionHours(int hours) async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;
    final subscription = await ref.read(subscriptionStateProvider.future);
    if (!subscription.canKeepHistoryHours(hours)) {
      throw StateError('Premium required for history retention above ${subscription.maxHistoryRetentionHours} hours.');
    }

    final repo = ref.read(settingsRepositoryProvider);
    await repo.setHistoryRetentionHours(userId: user.id, hours: hours);
    ref.invalidate(mapLocationSettingsProvider);
  }
}

final settingsControllerProvider = Provider((ref) => SettingsController(ref));
