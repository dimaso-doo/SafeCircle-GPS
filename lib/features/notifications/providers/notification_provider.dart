import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/demo/demo_backend.dart';
import '../../../repositories/notification_repository.dart';
import '../../../repositories/sos_repository.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/subscription/providers/subscription_provider.dart';
import '../../../models/notification_settings.dart' as app_notification_settings;

enum SafeCircleNotificationType {
  sosAlert,
  safeZoneEnter,
  safeZoneExit,
  sharingPaused,
}

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  final client = AppConfig.runInDemoMode ? null : Supabase.instance.client;
  return NotificationRepository(client);
});

final sosRepositoryProvider = Provider<SosRepository>((ref) {
  final client = AppConfig.runInDemoMode ? null : Supabase.instance.client;
  return SosRepository(client);
});

final notificationSettingsProvider =
    FutureProvider<app_notification_settings.NotificationSettings>((ref) async {
  final user = ref.watch(authControllerProvider).user;
  if (user == null) return throw StateError('Not signed in');
  final repository = ref.watch(notificationRepositoryProvider);
  return repository.getSettings(user.id);
});

final safeCircleNotificationControllerProvider =
    Provider((ref) => SafeCircleNotificationController(ref));

class SafeCircleNotificationController {
  SafeCircleNotificationController(this.ref);

  final Ref ref;

  Future<void> ensureNotificationsReady() async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;
    if (AppConfig.runInDemoMode) return;

    final permission = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (permission.authorizationStatus != AuthorizationStatus.authorized &&
        permission.authorizationStatus != AuthorizationStatus.provisional) {
      return;
    }

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;

    final repository = ref.read(notificationRepositoryProvider);
    await repository.upsertDeviceToken(
      userId: user.id,
      token: token,
      platform: Platform.isIOS ? 'ios' : 'android',
      appVersion: null,
    );

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      await repository.upsertDeviceToken(
        userId: user.id,
        token: newToken,
        platform: Platform.isIOS ? 'ios' : 'android',
        appVersion: null,
      );
    }).onError((_) {});

    FirebaseMessaging.instance.setAutoInitEnabled(true);
  }

  Future<void> sendNotificationEvent({
    required SafeCircleNotificationType type,
    required String circleId,
    String? zoneId,
    String? zoneName,
    double? latitude,
    double? longitude,
    String? actorName,
  }) async {
    final settings = await ref.read(notificationSettingsProvider.future);
    if (!settings.pushEnabled) return;

    switch (type) {
      case SafeCircleNotificationType.sosAlert:
        if (!settings.notifySos) return;
        break;
      case SafeCircleNotificationType.safeZoneEnter:
        if (!settings.notifySafeZoneEnter) return;
        break;
      case SafeCircleNotificationType.safeZoneExit:
        if (!settings.notifySafeZoneExit) return;
        break;
      case SafeCircleNotificationType.sharingPaused:
        if (!settings.notifySharingPaused) return;
        break;
    }

    final user = ref.read(authControllerProvider).user;
    if (user == null) return;

    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.notifyDevice(type.name, user.id);
    }

    await Supabase.instance.client.functions.invoke(
      'safe-circle-notify',
      body: {
        'type': type.name,
        'circle_id': circleId,
        'actor_user_id': user.id,
        if (actorName != null) 'actor_name': actorName,
        if (zoneId != null) 'zone_id': zoneId,
        if (zoneName != null) 'zone_name': zoneName,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      },
    );
  }

  Future<void> notifySafeZoneTransition({
    required String circleId,
    required String zoneId,
    required String zoneName,
    required bool isEnter,
    required double latitude,
    required double longitude,
  }) async {
    final type = isEnter
        ? SafeCircleNotificationType.safeZoneEnter
        : SafeCircleNotificationType.safeZoneExit;

    await sendNotificationEvent(
      type: type,
      circleId: circleId,
      zoneId: zoneId,
      zoneName: zoneName,
      latitude: latitude,
      longitude: longitude,
    );
  }

  Future<void> notifySharingPaused({
    required String circleId,
    required double latitude,
    required double longitude,
  }) async {
    await sendNotificationEvent(
      type: SafeCircleNotificationType.sharingPaused,
      circleId: circleId,
      latitude: latitude,
      longitude: longitude,
    );
  }

  Future<void> saveSosEventAndNotify({
    required String circleId,
    required String userId,
    required Position position,
    double? batteryLevel,
  }) async {
    final subscription = await ref.read(subscriptionStateProvider.future);
    if (!subscription.canUseSosFeature()) {
      throw StateError('SOS alerts are available in Premium.');
    }

    final repository = ref.read(sosRepositoryProvider);
    await repository.createSosEvent(
      circleId: circleId,
      userId: userId,
      position: position,
      batteryLevel: batteryLevel,
    );

    await sendNotificationEvent(
      type: SafeCircleNotificationType.sosAlert,
      circleId: circleId,
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }

  Future<void> setPushEnabled(bool value) async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;
    final repository = ref.read(notificationRepositoryProvider);
    await repository.updateSettings(userId: user.id, pushEnabled: value);
    ref.invalidate(notificationSettingsProvider);
  }

  Future<void> setNotifySos(bool value) async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;
    final repository = ref.read(notificationRepositoryProvider);
    await repository.updateSettings(userId: user.id, notifySos: value);
    ref.invalidate(notificationSettingsProvider);
  }

  Future<void> setNotifySafeZoneEnter(bool value) async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;
    final repository = ref.read(notificationRepositoryProvider);
    await repository.updateSettings(userId: user.id, notifySafeZoneEnter: value);
    ref.invalidate(notificationSettingsProvider);
  }

  Future<void> setNotifySafeZoneExit(bool value) async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;
    final repository = ref.read(notificationRepositoryProvider);
    await repository.updateSettings(userId: user.id, notifySafeZoneExit: value);
    ref.invalidate(notificationSettingsProvider);
  }

  Future<void> setNotifySharingPaused(bool value) async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;
    final repository = ref.read(notificationRepositoryProvider);
    await repository.updateSettings(userId: user.id, notifySharingPaused: value);
    ref.invalidate(notificationSettingsProvider);
  }
}
