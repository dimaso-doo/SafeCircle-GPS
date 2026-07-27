import 'dart:async';
import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../models/app_user.dart';
import '../../models/circle.dart';
import '../../models/circle_member.dart';
import '../../models/location_sharing_settings.dart';
import '../../models/location_update.dart';
import '../../models/notification_settings.dart';
import '../../models/safe_zone.dart';
import '../../models/sos_event.dart';
import '../../models/subscription_plan.dart';
import '../../models/user_profile.dart';
import '../../models/user_subscription.dart';

class DemoBackend {
  DemoBackend._() {
    _ensureDemoSeedAccount();
  }

  static final DemoBackend shared = DemoBackend._();

  final Uuid _uuid = const Uuid();
  final StreamController<AppUser?> _authStreamController =
      StreamController<AppUser?>.broadcast();

  AppUser? _activeUser;
  final Map<String, String> _credentialsByEmail = {};
  final Map<String, String> _passwordByUserId = {};
  final Map<String, UserProfile> _profilesById = {};
  final Map<String, CircleModel> _circlesById = {};
  final Map<String, String> _inviteByCircleId = {};
  final Map<String, String> _circleIdByInviteCode = {};
  final Map<String, Set<String>> _membershipCircleIdsByUser = {};
  final Map<String, List<String>> _memberIdsByCircle = {};
  final Map<String, List<LocationUpdate>> _locationUpdatesByUser = {};
  final Map<String, LocationSharingSettings> _settingsByUser = {};
  final Map<String, List<SafeZone>> _zonesByCircle = {};
  final Map<String, List<_LocationSeed>> _safeZoneEventsByCircle = {};
  final Map<String, NotificationSettings> _notificationSettingsByUser = {};
  final Map<String, UserSubscriptionState> _subscriptionByUser = {};
  final Map<String, SosEvent> _latestSosByUser = {};
  final Map<String, Set<String>> _demoCircleMembershipUsers = {};

  final Map<String, int> _markerTicksByUser = {};
  final Map<String, double> _markerOffsetLatByUser = {};
  final Map<String, double> _markerOffsetLonByUser = {};

  static const String _demoEmail = 'demo@safe-circle.local';
  static const String _demoPassword = 'demo1234';
  static const String _demoDisplayName = 'Demo User';

  Stream<AppUser?> authStateStream() => _authStreamController.stream;

  AppUser? get activeUser => _activeUser;

  List<String> getCircleIdsForUser(String userId) {
    return List<String>.from(
        _membershipCircleIdsByUser[userId] ?? const <String>[]);
  }

  String? getCircleIdForSafeZone(String zoneId) {
    return _findCircleIdForZone(zoneId);
  }

  Future<void> signOut() async {
    _activeUser = null;
    _authStreamController.add(null);
  }

  Future<void> deleteCurrentAccount() async {
    await signOut();
  }

  Future<bool> hasUser() async {
    return _activeUser != null;
  }

  Future<void> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      throw StateError('Email is required.');
    }
    if (password.length < 6) {
      throw StateError('Password must be at least 6 characters.');
    }
    if (_credentialsByEmail.containsKey(normalizedEmail)) {
      throw StateError('This email is already registered in demo mode.');
    }

    final id = _uuid.v4();
    _credentialsByEmail[normalizedEmail] = id;
    _passwordByUserId[id] = password;

    final user = AppUser(
      id: id,
      email: normalizedEmail,
      displayName:
          displayName?.trim().isNotEmpty == true ? displayName!.trim() : null,
    );
    _activeUser = user;
    _profilesById[id] = UserProfile(id: id, displayName: displayName?.trim());
    _seedDefaultSettings(id);
    _seedDefaultNotificationSettings(id);
    _seedDefaultSubscription(id);
    _ensureSeedPositions(id);
    _authStreamController.add(user);
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    _ensureDemoSeedAccount();
    final normalizedEmail = email.trim().toLowerCase();
    final userId = _credentialsByEmail[normalizedEmail];
    if (userId == null || _passwordByUserId[userId] != password) {
      throw StateError('Invalid demo credentials.');
    }

    final profile = _profilesById[userId];
    final user = AppUser(
      id: userId,
      email: normalizedEmail,
      displayName: profile?.displayName,
    );
    _activeUser = user;
    _seedDefaultSettings(userId);
    _seedDefaultNotificationSettings(userId);
    _seedDefaultSubscription(userId);
    _authStreamController.add(user);
  }

  void setDisplayName(String userId, String displayName) {
    final existing = _profilesById[userId];
    _profilesById[userId] = UserProfile(
      id: userId,
      displayName: displayName,
      avatarUrl: existing?.avatarUrl,
      createdAt: existing?.createdAt,
      updatedAt: DateTime.now(),
    );
    final current = _activeUser;
    if (current != null && current.id == userId) {
      _activeUser = AppUser(
          id: current.id, email: current.email, displayName: displayName);
      _authStreamController.add(_activeUser);
    }
  }

  Future<String> createCircle({
    required String ownerId,
    required String name,
  }) async {
    final id = _uuid.v4();
    final circle = CircleModel(
      id: id,
      name: name.trim().isEmpty ? 'My Family' : name.trim(),
      ownerId: ownerId,
      inviteCode: _newInviteCode(),
    );
    _circlesById[id] = circle;
    _inviteByCircleId[id] = circle.inviteCode;
    _circleIdByInviteCode[circle.inviteCode] = id;
    _memberIdsByCircle[id] = <String>[];
    _zonesByCircle[id] = <SafeZone>[];
    _safeZoneEventsByCircle[id] = <_LocationSeed>[];

    addMemberToCircle(
        circleId: id, userId: ownerId, role: 'owner', isAccepted: true);
    return id;
  }

  Future<String> getInviteCode(String circleId) async {
    return _inviteByCircleId[circleId] ?? '';
  }

  Future<String> rotateInviteCode(String circleId) async {
    final circle = _circlesById[circleId];
    if (circle == null) {
      throw StateError('Circle not found.');
    }
    final oldCode = circle.inviteCode;
    final newCode = _newInviteCode();
    final updated = CircleModel(
      id: circle.id,
      name: circle.name,
      ownerId: circle.ownerId,
      inviteCode: newCode,
      createdAt: circle.createdAt,
    );
    _circlesById[circleId] = updated;
    _inviteByCircleId[circleId] = newCode;
    _circleIdByInviteCode.remove(oldCode);
    _circleIdByInviteCode[newCode] = circleId;
    return newCode;
  }

  Future<void> joinCircleByInviteCode({
    required String inviteCode,
    required String userId,
  }) async {
    final circleId = _circleIdByInviteCode[inviteCode.trim().toUpperCase()];
    if (circleId == null) {
      throw StateError('Invalid invite code.');
    }
    addMemberToCircle(
        circleId: circleId, userId: userId, role: 'member', isAccepted: true);
  }

  Future<void> deleteCircle({
    required String circleId,
    required String requesterId,
  }) async {
    final circle = _circlesById[circleId];
    if (circle == null) {
      throw StateError('Family not found.');
    }
    if (circle.ownerId != requesterId) {
      throw StateError('Only the family owner can delete it.');
    }

    final members = List<String>.from(
      _memberIdsByCircle[circleId] ?? const <String>[],
    );
    for (final userId in members) {
      _membershipCircleIdsByUser[userId]?.remove(circleId);
    }

    _circleIdByInviteCode.remove(circle.inviteCode);
    _inviteByCircleId.remove(circleId);
    _memberIdsByCircle.remove(circleId);
    _demoCircleMembershipUsers.remove(circleId);
    _zonesByCircle.remove(circleId);
    _safeZoneEventsByCircle.remove(circleId);
    _circlesById.remove(circleId);
  }

  Future<void> leaveCircle({
    required String circleId,
    required String userId,
  }) async {
    final circle = _circlesById[circleId];
    if (circle == null) {
      throw StateError('Family not found.');
    }
    if (circle.ownerId == userId) {
      throw StateError('The owner must delete the family instead.');
    }
    _removeMemberFromCircle(circleId: circleId, userId: userId);
  }

  Future<void> removeCircleMember({
    required String circleId,
    required String memberUserId,
    required String requesterId,
  }) async {
    final circle = _circlesById[circleId];
    if (circle == null) {
      throw StateError('Family not found.');
    }
    if (circle.ownerId != requesterId) {
      throw StateError('Only the family owner can remove members.');
    }
    if (circle.ownerId == memberUserId) {
      throw StateError('The owner cannot be removed.');
    }
    _removeMemberFromCircle(circleId: circleId, userId: memberUserId);
  }

  void addMemberToCircle({
    required String circleId,
    required String userId,
    required String role,
    required bool isAccepted,
  }) {
    final members = _memberIdsByCircle.putIfAbsent(circleId, () => <String>[]);
    if (members.contains(userId)) {
      return;
    }
    members.add(userId);
    _membershipCircleIdsByUser
        .putIfAbsent(userId, () => <String>{})
        .add(circleId);
    _demoCircleMembershipUsers
        .putIfAbsent(circleId, () => <String>{})
        .add(userId);
    if (_circlesById.containsKey(circleId) &&
        _zonesByCircle[circleId] == null) {
      _zonesByCircle[circleId] = <SafeZone>[];
    }
    _ensureSeedPositions(userId);
  }

  void _removeMemberFromCircle({
    required String circleId,
    required String userId,
  }) {
    _memberIdsByCircle[circleId]?.remove(userId);
    _membershipCircleIdsByUser[userId]?.remove(circleId);
    _demoCircleMembershipUsers[circleId]?.remove(userId);

    if (_membershipCircleIdsByUser[userId]?.isEmpty == true) {
      final current = _settingsByUser[userId];
      if (current != null) {
        _settingsByUser[userId] = _updatedSettings(
          userId: userId,
          isSharingEnabled: false,
          isPaused: false,
          isBackgroundSharingEnabled: null,
          updateIntervalSeconds: null,
          distanceFilterMeters: null,
          isBatterySavingMode: null,
          historyRetentionHours: null,
        );
      }
    }
  }

  Future<List<CircleModel>> getCirclesForUser(String userId) async {
    final ids = _membershipCircleIdsByUser[userId] ?? const <String>{};
    return ids
        .map((id) => _circlesById[id])
        .whereType<CircleModel>()
        .toList(growable: false);
  }

  Future<bool> currentUserCanShare(String userId) async {
    final ids = _membershipCircleIdsByUser[userId];
    return ids != null && ids.isNotEmpty;
  }

  Future<List<CircleMember>> getMembersForCircle(String circleId) async {
    final members = _memberIdsByCircle[circleId] ?? const [];
    return members
        .map((userId) {
          final userProfile = _profilesById[userId];
          final circle = _circlesById[circleId];
          if (circle == null) return null;
          return CircleMember(
            id: '${circleId}_$userId',
            circleId: circleId,
            userId: userId,
            role: userId == circle.ownerId ? 'owner' : 'member',
            isAccepted: true,
            invitedAt: DateTime.now(),
            displayName: userProfile?.displayName ?? 'Member',
            avatarUrl: userProfile?.avatarUrl,
            userProfileId: userId,
          );
        })
        .whereType<CircleMember>()
        .toList(growable: false);
  }

  Future<CircleModel> getCircle(String circleId) async {
    final circle = _circlesById[circleId];
    if (circle == null) {
      throw StateError('Circle not found.');
    }
    return circle;
  }

  Future<LocationSharingSettings> getSettings(String userId) async {
    _seedDefaultSettings(userId);
    return _settingsByUser[userId]!;
  }

  Future<LocationSharingSettings> upsertSettings(
      String userId, LocationSharingSettings next) async {
    _settingsByUser[userId] = next;
    return next;
  }

  Future<LocationSharingSettings> setSharingEnabled({
    required String userId,
    required bool isEnabled,
  }) async {
    return upsertSettings(
      userId,
      _updatedSettings(
        userId: userId,
        isSharingEnabled: isEnabled,
        isPaused: false,
        isBackgroundSharingEnabled: null,
        updateIntervalSeconds: null,
        distanceFilterMeters: null,
        isBatterySavingMode: null,
        historyRetentionHours: null,
      ),
    );
  }

  Future<LocationSharingSettings> setPaused({
    required String userId,
    required bool isPaused,
  }) async {
    return upsertSettings(
      userId,
      _updatedSettings(
        userId: userId,
        isSharingEnabled: null,
        isPaused: isPaused,
        isBackgroundSharingEnabled: null,
        updateIntervalSeconds: null,
        distanceFilterMeters: null,
        isBatterySavingMode: null,
        historyRetentionHours: null,
      ),
    );
  }

  Future<LocationSharingSettings> setBackgroundSharingEnabled({
    required String userId,
    required bool isEnabled,
  }) async {
    return upsertSettings(
      userId,
      _updatedSettings(
        userId: userId,
        isSharingEnabled: null,
        isPaused: null,
        isBackgroundSharingEnabled: isEnabled,
        updateIntervalSeconds: null,
        distanceFilterMeters: null,
        isBatterySavingMode: null,
        historyRetentionHours: null,
      ),
    );
  }

  Future<LocationSharingSettings> setUpdateInterval({
    required String userId,
    required int intervalSeconds,
  }) async {
    return upsertSettings(
      userId,
      _updatedSettings(
        userId: userId,
        isSharingEnabled: null,
        isPaused: null,
        isBackgroundSharingEnabled: null,
        updateIntervalSeconds: intervalSeconds,
        distanceFilterMeters: null,
        isBatterySavingMode: null,
        historyRetentionHours: null,
      ),
    );
  }

  Future<LocationSharingSettings> setDistanceFilter({
    required String userId,
    required int distanceMeters,
  }) async {
    return upsertSettings(
      userId,
      _updatedSettings(
        userId: userId,
        isSharingEnabled: null,
        isPaused: null,
        isBackgroundSharingEnabled: null,
        updateIntervalSeconds: null,
        distanceFilterMeters: distanceMeters,
        isBatterySavingMode: null,
        historyRetentionHours: null,
      ),
    );
  }

  Future<LocationSharingSettings> setBatterySavingMode({
    required String userId,
    required bool enabled,
  }) async {
    return upsertSettings(
      userId,
      _updatedSettings(
        userId: userId,
        isSharingEnabled: null,
        isPaused: null,
        isBackgroundSharingEnabled: null,
        updateIntervalSeconds: null,
        distanceFilterMeters: null,
        isBatterySavingMode: enabled,
        historyRetentionHours: null,
      ),
    );
  }

  Future<LocationSharingSettings> setHistoryRetentionHours({
    required String userId,
    required int hours,
  }) async {
    return upsertSettings(
      userId,
      _updatedSettings(
        userId: userId,
        isSharingEnabled: null,
        isPaused: null,
        isBackgroundSharingEnabled: null,
        updateIntervalSeconds: null,
        distanceFilterMeters: null,
        isBatterySavingMode: null,
        historyRetentionHours: hours,
      ),
    );
  }

  Future<void> uploadLocationUpdate({
    required String userId,
    required Position position,
    double? batteryLevel,
  }) async {
    final now = DateTime.now().toUtc();
    final entry = LocationUpdate(
      id: _uuid.v4(),
      userId: userId,
      latitude: position.latitude,
      longitude: position.longitude,
      altitude: position.altitude,
      batteryLevel: batteryLevel,
      accuracy: position.accuracy,
      speed: position.speed,
      heading: position.heading,
      createdAt: now,
    );
    final history =
        _locationUpdatesByUser.putIfAbsent(userId, () => <LocationUpdate>[]);
    history.insert(0, entry);
    if (history.length > 400) {
      history.removeRange(400, history.length);
    }
  }

  Future<List<LocationUpdate>> fetchHistory(String userId,
      {int limit = 100}) async {
    final history = _locationUpdatesByUser[userId] ?? const <LocationUpdate>[];
    final size = history.length.clamp(0, limit);
    return history.take(size).toList(growable: false);
  }

  Future<List<LocationUpdate>> fetchHistoryForMember({
    required String userId,
    required DateTime from,
    DateTime? to,
    int limit = 200,
  }) async {
    final history = _locationUpdatesByUser[userId] ?? const <LocationUpdate>[];
    final upper = to ?? DateTime.now();
    final filtered = history.where((row) {
      return !row.createdAt.isBefore(from.toUtc()) &&
          !row.createdAt.isAfter(upper.toUtc());
    }).toList(growable: false);
    final max = limit.clamp(0, filtered.length);
    return filtered.take(max).toList(growable: false);
  }

  Future<Map<String, LocationUpdate>> fetchLatestLocationByUsers(
      List<String> userIds) async {
    final result = <String, LocationUpdate>{};
    for (final userId in userIds) {
      if (result.containsKey(userId)) continue;
      final latest = _latestForUser(userId);
      if (latest == null) continue;
      result[userId] = latest;
    }
    return result;
  }

  Future<List<SafeZone>> getSafeZonesForCircle(String circleId) async {
    return List<SafeZone>.from(_zonesByCircle[circleId] ?? const <SafeZone>[]);
  }

  Future<SafeZone> createSafeZone({
    required String circleId,
    required String name,
    required double centerLatitude,
    required double centerLongitude,
    required int radiusMeters,
    String? targetUserId,
    required String createdBy,
  }) async {
    final zone = SafeZone(
      id: _uuid.v4(),
      circleId: circleId,
      createdBy: createdBy,
      targetUserId: targetUserId,
      name: name.trim().isEmpty ? 'Zone' : name.trim(),
      centerLatitude: centerLatitude,
      centerLongitude: centerLongitude,
      radiusMeters: radiusMeters,
      isActive: true,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    final zones = _zonesByCircle.putIfAbsent(circleId, () => <SafeZone>[]);
    zones.insert(0, zone);
    return zone;
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
    final zones = _zonesByCircle[circleId];
    if (zones == null) throw StateError('Zone not found.');
    final index = zones.indexWhere((zone) => zone.id == zoneId);
    if (index < 0) throw StateError('Zone not found.');

    final original = zones[index];
    final updated = SafeZone(
      id: original.id,
      circleId: original.circleId,
      createdBy: original.createdBy,
      targetUserId: clearTargetUser == true
          ? null
          : (targetUserId ?? original.targetUserId),
      name: name?.trim().isEmpty == false ? name!.trim() : original.name,
      centerLatitude: centerLatitude ?? original.centerLatitude,
      centerLongitude: centerLongitude ?? original.centerLongitude,
      radiusMeters: radiusMeters ?? original.radiusMeters,
      isActive: isActive ?? original.isActive,
      createdAt: original.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
    zones[index] = updated;
    return updated;
  }

  Future<void> deleteSafeZone({
    required String zoneId,
    required String circleId,
  }) async {
    final zones = _zonesByCircle[circleId];
    zones?.removeWhere((zone) => zone.id == zoneId);
  }

  Future<void> logSafeZoneEvent({
    required String zoneId,
    required String userId,
    required String eventType,
    DateTime? eventTimestamp,
  }) async {
    final record = _LocationSeed(
      zoneId: zoneId,
      userId: userId,
      eventType: eventType,
      at: eventTimestamp ?? DateTime.now().toUtc(),
    );
    final circleId = _findCircleIdForZone(zoneId);
    if (circleId == null) return;
    _safeZoneEventsByCircle
        .putIfAbsent(circleId, () => <_LocationSeed>[])
        .add(record);
  }

  Future<UserSubscriptionState> getSubscription(String userId) async {
    _seedDefaultSubscription(userId);
    return _subscriptionByUser[userId]!;
  }

  Future<NotificationSettings> getNotificationSettings(String userId) async {
    _seedDefaultNotificationSettings(userId);
    return _notificationSettingsByUser[userId]!;
  }

  Future<NotificationSettings> upsertNotificationSettings({
    required String userId,
    bool? pushEnabled,
    bool? notifySos,
    bool? notifySafeZoneEnter,
    bool? notifySafeZoneExit,
    bool? notifySharingPaused,
  }) async {
    final existing = await getNotificationSettings(userId);
    final next = NotificationSettings(
      id: existing.id,
      userId: existing.userId,
      pushEnabled: pushEnabled ?? existing.pushEnabled,
      notifySos: notifySos ?? existing.notifySos,
      notifySafeZoneEnter: notifySafeZoneEnter ?? existing.notifySafeZoneEnter,
      notifySafeZoneExit: notifySafeZoneExit ?? existing.notifySafeZoneExit,
      notifySharingPaused: notifySharingPaused ?? existing.notifySharingPaused,
      updatedAt: DateTime.now().toUtc(),
    );
    _notificationSettingsByUser[userId] = next;
    return next;
  }

  Future<SosEvent> createSosEvent({
    required String circleId,
    required String userId,
    required Position position,
    double? batteryLevel,
  }) async {
    final event = SosEvent(
      id: _uuid.v4(),
      circleId: circleId,
      userId: userId,
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      speedMps: position.speed,
      headingDegrees: position.heading,
      batteryLevel: batteryLevel,
      createdAt: DateTime.now().toUtc(),
    );
    _latestSosByUser[userId] = event;
    return event;
  }

  Future<void> notifyDevice(String type, String userId) async {
    // Demo mode does not push remote notifications.
    await Future<void>.value();
  }

  void seedDemoLocationsForMembers(String circleId) {
    final members = _memberIdsByCircle[circleId] ?? const <String>[];
    for (final userId in members) {
      _ensureSeedPositions(userId);
      uploadLocationUpdate(
              userId: userId, position: _nextDemoPositionFor(userId))
          .catchError((_) {});
    }
  }

  void seedLatestForUser(String userId) {
    _ensureSeedPositions(userId);
    uploadLocationUpdate(userId: userId, position: _nextDemoPositionFor(userId))
        .catchError((_) {});
  }

  LocationUpdate? latestLocationFor(String userId) {
    return _latestForUser(userId);
  }

  Position latestPositionFor(String userId) {
    final latest = latestLocationFor(userId);
    if (latest == null) {
      throw StateError('No demo location available yet.');
    }

    return Position(
      latitude: latest.latitude,
      longitude: latest.longitude,
      timestamp: latest.createdAt,
      altitude: latest.altitude ?? 20,
      altitudeAccuracy: 10,
      accuracy: latest.accuracy ?? 10,
      heading: latest.heading ?? 0,
      headingAccuracy: 20,
      speed: latest.speed ?? 0,
      speedAccuracy: 1,
    );
  }

  List<String> getMemberIds(String circleId) {
    return List<String>.from(_memberIdsByCircle[circleId] ?? const <String>[]);
  }

  void seedDemoStateIfNeeded() {
    if (_profilesById.isNotEmpty) {
      return;
    }
  }

  void _ensureDemoSeedAccount() {
    if (_credentialsByEmail.containsKey(_demoEmail)) {
      return;
    }

    final id = _uuid.v4();
    _credentialsByEmail[_demoEmail] = id;
    _passwordByUserId[id] = _demoPassword;
    _profilesById[id] = UserProfile(id: id, displayName: _demoDisplayName);
    _seedDefaultSettings(id);
    _seedDefaultNotificationSettings(id);
    _seedDefaultSubscription(id);
    _ensureSeedPositions(id);
  }

  String _newInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    String code;
    do {
      code =
          List.generate(7, (_) => chars[random.nextInt(chars.length)]).join();
    } while (_circleIdByInviteCode.containsKey(code));
    return code;
  }

  void _seedDefaultSettings(String userId) {
    _settingsByUser.putIfAbsent(
      userId,
      () => LocationSharingSettings(
        id: _uuid.v4(),
        userId: userId,
        isSharingEnabled: false,
        isPaused: false,
        isBackgroundSharingEnabled: false,
        updateIntervalSeconds: 10,
        distanceFilterMeters: 10,
        isBatterySavingMode: false,
        historyRetentionHours: 24,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  LocationSharingSettings _updatedSettings({
    required String userId,
    required bool? isSharingEnabled,
    required bool? isPaused,
    required bool? isBackgroundSharingEnabled,
    required int? updateIntervalSeconds,
    required int? distanceFilterMeters,
    required bool? isBatterySavingMode,
    required int? historyRetentionHours,
  }) {
    final current = _settingsByUser[userId] ??
        LocationSharingSettings(
          id: _uuid.v4(),
          userId: userId,
          isSharingEnabled: false,
          isPaused: false,
          isBackgroundSharingEnabled: false,
          updateIntervalSeconds: 10,
          distanceFilterMeters: 10,
          isBatterySavingMode: false,
          historyRetentionHours: 24,
          updatedAt: DateTime.now().toUtc(),
        );
    return LocationSharingSettings(
      id: current.id,
      userId: userId,
      isSharingEnabled: isSharingEnabled ?? current.isSharingEnabled,
      isPaused: isPaused ?? current.isPaused,
      isBackgroundSharingEnabled:
          isBackgroundSharingEnabled ?? current.isBackgroundSharingEnabled,
      updateIntervalSeconds:
          updateIntervalSeconds ?? current.updateIntervalSeconds,
      distanceFilterMeters:
          distanceFilterMeters ?? current.distanceFilterMeters,
      isBatterySavingMode: isBatterySavingMode ?? current.isBatterySavingMode,
      historyRetentionHours:
          historyRetentionHours ?? current.historyRetentionHours,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  void _seedDefaultNotificationSettings(String userId) {
    _notificationSettingsByUser.putIfAbsent(
      userId,
      () => NotificationSettings(
        id: _uuid.v4(),
        userId: userId,
        pushEnabled: true,
        notifySos: true,
        notifySafeZoneEnter: true,
        notifySafeZoneExit: true,
        notifySharingPaused: true,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  void _seedDefaultSubscription(String userId) {
    if (_subscriptionByUser.containsKey(userId)) {
      return;
    }
    final plan = SubscriptionPlan(
      id: 'free-plan-demo',
      slug: 'free',
      name: 'Free',
      maxCircles: 1,
      maxMembersPerCircle: 2,
      maxHistoryRetentionHours: 24,
      allowSafeZones: false,
      allowSos: false,
      allowPriorityUpdates: false,
    );
    _subscriptionByUser[userId] = UserSubscriptionState.fromJson({
      'id': 'sub-demo-${userId}',
      'user_id': userId,
      'status': 'active',
      'plan': plan.toJson(),
      'max_circles': plan.maxCircles,
      'max_members_per_circle': plan.maxMembersPerCircle,
      'max_history_retention_hours': plan.maxHistoryRetentionHours,
      'allow_safe_zones': plan.allowSafeZones,
      'allow_sos': plan.allowSos,
      'allow_priority_updates': plan.allowPriorityUpdates,
    });
  }

  void _ensureSeedPositions(String userId) {
    _markerTicksByUser.putIfAbsent(userId, () => 0);
    _markerOffsetLatByUser.putIfAbsent(userId, () => 0);
    _markerOffsetLonByUser.putIfAbsent(userId, () => 0);
  }

  Position _nextDemoPositionFor(String userId) {
    _ensureSeedPositions(userId);
    final ticks = _markerTicksByUser[userId] ?? 0;
    final baseLat = 51.5074 + (ticks * 0.001);
    final baseLon = -0.1278 + (ticks * 0.0012);
    final jitter = (ticks % 3) * 0.0002;
    _markerTicksByUser[userId] = ticks + 1;

    return Position(
      latitude: baseLat + jitter,
      longitude: baseLon - jitter,
      timestamp: DateTime.now().toUtc(),
      accuracy: 10 + (ticks % 4),
      altitude: 20,
      altitudeAccuracy: 10,
      heading: (ticks * 45).toDouble() % 360,
      headingAccuracy: 20,
      speed: 1.1 + (ticks % 6) * 0.2,
      speedAccuracy: 1,
    );
  }

  LocationUpdate? _latestForUser(String userId) {
    final history = _locationUpdatesByUser[userId];
    if (history == null || history.isEmpty) {
      seedLatestForUser(userId);
      return _locationUpdatesByUser[userId]?.first;
    }
    return history.first;
  }

  String? _findCircleIdForZone(String zoneId) {
    final entries = _zonesByCircle.entries;
    for (final entry in entries) {
      final hasMatch = entry.value.any((zone) => zone.id == zoneId);
      if (hasMatch) {
        return entry.key;
      }
    }
    return null;
  }
}

class _LocationSeed {
  const _LocationSeed({
    required this.zoneId,
    required this.userId,
    required this.eventType,
    required this.at,
  });

  final String zoneId;
  final String userId;
  final String eventType;
  final DateTime at;
}
