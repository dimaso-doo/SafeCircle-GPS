import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/demo/demo_backend.dart';
import '../../../core/widgets/empty_states.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/circles/models/circle_member.dart';
import '../../../features/history/providers/history_provider.dart';
import '../../../features/safe_zones/providers/safe_zone_provider.dart';
import '../../../models/location_update.dart';
import '../../../models/location_sharing_settings.dart';
import '../../../models/safe_zone.dart';
import '../../../services/location/location_service.dart';
import '../../../features/settings/providers/settings_provider.dart';
import '../../../features/notifications/providers/notification_provider.dart';
import '../../../features/paywall/ui/paywall_screen.dart';
import '../../../features/subscription/providers/subscription_provider.dart';
import '../providers/map_provider.dart';
import 'location_permission_gate.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final Completer<GoogleMapController> _mapController = Completer();
  final Map<String, LocationUpdate> _memberLocations = {};

  Set<String> _memberIds = <String>{};
  String? _activeCircleId;
  String? _activeMembersSignature;
  bool _isTrackingSessionActive = false;
  bool _isShareActionRunning = false;
  bool _isSosActionRunning = false;
  bool _isNotificationInitialized = false;
  DateTime? _lastUploadAt;
  List<SafeZone> _safeZones = const <SafeZone>[];

  final Map<String, _SafeZoneRuntimeState> _safeZoneStates = {};
  static const Duration _safeZoneDebounce = Duration(seconds: 20);
  static const Duration _safeZoneEventCooldown = Duration(minutes: 2);

  StreamSubscription<Position>? _shareSubscription;
  Timer? _demoShareTimer;
  Timer? _demoRealtimeTimer;
  dynamic _locationRealtimeSubscription;

  @override
  void dispose() {
    _stopTrackingStream();
    _stopRealtimeSubscription();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    if (authState.user == null) {
      return const SizedBox.shrink();
    }

    final permissionState = ref.watch(permissionStateProvider);
    final positionState = ref.watch(currentPositionProvider);
    final settingsState = ref.watch(mapLocationSettingsProvider);
    final canShareMembership = ref.watch(canShareLocationProvider);
    final activeCircleId = ref.watch(activeMapCircleIdProvider);
    final membersState = ref.watch(activeMapMembersProvider);
    final safeZonesState = ref.watch(safeZonesForActiveCircleProvider);

    if (!permissionState.hasValue ||
        permissionState.valueOrNull != LocationPermissionState.granted) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Map'),
          actions: [
            IconButton(
              onPressed: _isSosActionRunning ? null : _sendSos,
              icon: const Icon(Icons.warning_amber_rounded),
              color: Theme.of(context).colorScheme.error,
              tooltip: 'Send SOS',
            ),
          ],
        ),
        body: LocationPermissionGate(
          onPermissionStateChanged: () {
            ref.invalidate(permissionStateProvider);
            ref.invalidate(currentPositionProvider);
            setState(() {});
          },
        ),
      );
    }

    membersState.whenData((members) {
      _syncCircleContext(activeCircleId, members);
    });

    safeZonesState.whenData((zones) {
      _safeZones = zones.where((zone) => zone.isActive).toList(growable: false);
      final zoneIds = _safeZones.map((zone) => zone.id).toSet();
      _safeZoneStates.removeWhere((zoneId, _) => !zoneIds.contains(zoneId));
    });

    if (!_isNotificationInitialized) {
      _isNotificationInitialized = true;
      ref.read(safeCircleNotificationControllerProvider).ensureNotificationsReady();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Map'),
        actions: [
          IconButton(
            onPressed: _isSosActionRunning ? null : _sendSos,
            icon: const Icon(Icons.warning_amber_rounded),
            color: Theme.of(context).colorScheme.error,
            tooltip: 'Send SOS',
          ),
        ],
      ),
      body: membersState.when(
        data: (members) => _mapBody(
          positionState,
          settingsState,
          canShareMembership,
          members,
          safeZonesState.valueOrNull ?? const <SafeZone>[],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorState(message: error.toString()),
      ),
    );
  }

  void _syncCircleContext(String? circleId, List<CircleMember> members) {
    final acceptedMembers = members.where((member) => member.isAccepted).toList(growable: false);
    final nextMemberIds = acceptedMembers.map((member) => member.userId).toSet();
    final nextSignature = nextMemberIds.toList()..sort();
    final nextSignatureText = '${circleId ?? 'no-circle'}|${nextSignature.join(",")}';

    if (_activeCircleId == circleId && _activeMembersSignature == nextSignatureText) {
      return;
    }

    _activeCircleId = circleId;
    _activeMembersSignature = nextSignatureText;
    _memberIds = nextMemberIds;
    if (circleId == null || nextMemberIds.isEmpty) {
      _stopRealtimeSubscription();
      setState(() {
        _memberLocations.clear();
      });
      _safeZoneStates.clear();
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshCircleMembers(circleId);
    });
  }

  void _refreshCircleMembers(String circleId) {
    _loadLatestMemberLocations();
    _subscribeToCircleLocationUpdates(circleId);
  }

  Future<void> _loadLatestMemberLocations() async {
    final ids = _memberIds.toList();
    if (ids.isEmpty) {
      return;
    }

    try {
      final repository = ref.read(mapLocationRepositoryProvider);
      final latestByUser = await repository.fetchLatestLocationByUsers(ids);
      if (!mounted) return;
      setState(() {
        _memberLocations
          ..removeWhere((userId, _) => !_memberIds.contains(userId))
          ..addAll(latestByUser);
      });
    } catch (error) {
      _showSnack(context, 'Unable to load circle locations: ${error.toString()}');
    }
  }

  Future<void> _subscribeToCircleLocationUpdates(String circleId) async {
    await _stopRealtimeSubscription();

    if (AppConfig.runInDemoMode) {
      _demoRealtimeTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
        await _loadLatestMemberLocations();
      });
      return;
    }

    final channel = Supabase.instance.client.channel('realtime:circle-locations-$circleId');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'location_updates',
      callback: (dynamic payload) {
        final record = payload.newRecord as Map<String, dynamic>?;
        if (record == null) return;

        final userId = record['user_id'] as String?;
        if (userId == null || !_memberIds.contains(userId)) return;

        try {
          final update = LocationUpdate.fromJson(Map<String, dynamic>.from(record));
          setState(() {
            _memberLocations[userId] = update;
          });
        } catch (_) {}
      },
    );

    await channel.subscribe();
    if (!mounted) return;
    _locationRealtimeSubscription = channel;
  }

  Future<void> _stopRealtimeSubscription() async {
    _demoRealtimeTimer?.cancel();
    _demoRealtimeTimer = null;

    if (_locationRealtimeSubscription == null) {
      return;
    }

    try {
      await Supabase.instance.client.removeChannel(_locationRealtimeSubscription);
    } catch (_) {}
    _locationRealtimeSubscription = null;
  }

  Future<void> _startSharing() async {
    if (_isShareActionRunning) return;
    if (_activeCircleId == null || _memberIds.isEmpty) {
      _showSnack(context, 'Join and accept a circle before starting sharing.');
      return;
    }

    final canShare = await ref.read(canShareLocationProvider.future);
    if (!canShare) {
      _showSnack(context, 'Join a circle first. Membership must be accepted before sharing.');
      return;
    }

    setState(() {
      _isShareActionRunning = true;
    });

    try {
      if (!AppConfig.runInDemoMode) {
        final settings = await ref.read(mapLocationSettingsProvider.future);
        if (settings.isBackgroundSharingEnabled) {
          final permission = await ref.read(locationServiceProvider).checkRawPermission();
          final hasBackgroundPermission =
              ref.read(locationServiceProvider).hasBackgroundPermission(permission);

          if (!hasBackgroundPermission) {
            final requested = await ref.read(locationServiceProvider).requestRawPermission();
            final finalPermission =
                ref.read(locationServiceProvider).hasBackgroundPermission(requested);
            if (!finalPermission) {
              _showSnack(
                context,
                'Background location permission is off. We can still share in foreground after you tap Start again.',
              );
              return;
            }
          }
        }

        final permission = await ref.read(permissionStateProvider.future);
        if (permission != LocationPermissionState.granted) {
          _showSnack(context, 'Location permission is required to start sharing.');
          return;
        }
      }

      await ref.read(settingsControllerProvider).setSharingEnabled(true);
      await ref.read(settingsControllerProvider).setPaused(false);
      ref.invalidate(mapLocationSettingsProvider);
      await _startLocationStream();
      _showSnack(context, 'Location sharing started.');
      ref.invalidate(historyProvider);
    } catch (error) {
      _showSnack(context, 'Unable to start sharing: ${error.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isShareActionRunning = false;
        });
      }
    }
  }

  Future<void> _pauseSharing() async {
    setState(() {
      _isShareActionRunning = true;
    });

    try {
      await _stopTrackingStream();
      await ref.read(settingsControllerProvider).setPaused(true);
      ref.invalidate(mapLocationSettingsProvider);
      final user = ref.read(authControllerProvider).user;
      if (_activeCircleId != null && user != null) {
        Position? position;
        if (AppConfig.runInDemoMode) {
          position = _latestDemoPosition(user.id);
        } else {
          position = await ref.read(locationServiceProvider).currentLocation();
        }

        if (position != null) {
          await ref.read(safeCircleNotificationControllerProvider).notifySharingPaused(
                circleId: _activeCircleId!,
                latitude: position.latitude,
                longitude: position.longitude,
              );
        }
      }
      _showSnack(context, 'Location sharing paused.');
    } catch (error) {
      _showSnack(context, 'Unable to pause: ${error.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isShareActionRunning = false;
        });
      }
    }
  }

  Future<void> _sendSos() async {
    final user = ref.read(authControllerProvider).user;
    if (user == null || _activeCircleId == null) {
      _showSnack(context, 'Join a family circle before sending SOS.');
      return;
    }

    final isMember = await ref.read(canShareLocationProvider.future);
    if (!isMember) {
      _showSnack(context, 'You must be an accepted circle member to send SOS.');
      return;
    }

    final subscription = await ref.read(subscriptionStateProvider.future);
    if (!subscription.canUseSosFeature()) {
      _showSnack(context, 'SOS is a Premium feature.');
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PaywallScreen()),
        );
      }
      return;
    }

    setState(() {
      _isSosActionRunning = true;
    });

    try {
      final service = ref.read(locationServiceProvider);
      final userId = user.id;
      final position = AppConfig.runInDemoMode
          ? _latestDemoPosition(userId)
          : await service.currentLocation();

      if (position == null) {
        throw StateError('No location available for SOS. Start sharing first.');
      }

      final battery = AppConfig.runInDemoMode
          ? DemoBackend.shared.latestLocationFor(userId)?.batteryLevel
          : await service.batteryLevel();

      await ref.read(safeCircleNotificationControllerProvider).saveSosEventAndNotify(
            circleId: _activeCircleId!,
            userId: user.id,
            position: position,
            batteryLevel: battery,
          );

      _showSnack(context, 'SOS alert sent to your circle.');
    } catch (error) {
      _showSnack(context, 'Unable to send SOS: ${error.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isSosActionRunning = false;
        });
      }
    }
  }

  Future<void> _stopSharing() async {
    setState(() {
      _isShareActionRunning = true;
    });

    try {
      await _stopTrackingStream();
      await ref.read(settingsControllerProvider).setSharingEnabled(false);
      await ref.read(settingsControllerProvider).setPaused(false);
      ref.invalidate(mapLocationSettingsProvider);
      _showSnack(context, 'Location sharing stopped.');
    } catch (error) {
      _showSnack(context, 'Unable to stop: ${error.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isShareActionRunning = false;
        });
      }
    }
  }

  Future<void> _startLocationStream() async {
    if (_isTrackingSessionActive) {
      return;
    }

    final user = ref.read(authControllerProvider).user;
    if (user == null) return;

    final settings = await ref.read(mapLocationSettingsProvider.future);
    if (!settings.canShare) {
      throw StateError('Location sharing is disabled.');
    }

    final repository = ref.read(mapLocationRepositoryProvider);
    final service = ref.read(locationServiceProvider);
    final effectiveInterval = Duration(seconds: settings.effectiveUpdateIntervalSeconds);
    final effectiveDistanceFilter = settings.effectiveDistanceFilterMeters;
    _lastUploadAt = null;

    if (AppConfig.runInDemoMode) {
      await _startDemoLocationStream(
        userId: user.id,
        repository: repository,
        interval: effectiveInterval,
        distanceFilterMeters: effectiveDistanceFilter,
      );
      return;
    }

    await _stopTrackingStream();
    _isTrackingSessionActive = true;
    if (mounted) {
      setState(() {});
    }

    _shareSubscription = service
        .locationUpdates(
          backgroundEnabled: settings.isTrackingInBackgroundAllowed,
          distanceFilterMeters: effectiveDistanceFilter,
          updateInterval: effectiveInterval,
          batterySavingMode: settings.isBatterySavingMode,
        )
        .listen((position) async {
      final now = DateTime.now().toUtc();
      if (_lastUploadAt != null &&
          now.difference(_lastUploadAt!).inSeconds <
              settings.effectiveUpdateIntervalSeconds) {
        return;
      }
      _lastUploadAt = now;

      try {
        final currentSettings = await ref.read(mapLocationSettingsProvider.future);
        if (!mounted || !currentSettings.canShare) {
          await _stopTrackingStream();
          return;
        }

        final batteryLevel = await service.batteryLevel();
        if (mounted) {
          await _handleSafeZoneTransitions(
            user.id,
            position,
            eventTime: now,
          );
        }
        await repository.uploadLocationUpdate(
          userId: user.id,
          position: position,
          batteryLevel: batteryLevel,
        );

        final now = DateTime.now().toUtc();
        if (mounted) {
          setState(() {
            _memberLocations[user.id] = LocationUpdate(
              id: now.microsecondsSinceEpoch.toString(),
              userId: user.id,
              latitude: position.latitude,
              longitude: position.longitude,
              altitude: position.altitude,
              batteryLevel: batteryLevel,
              accuracy: position.accuracy,
              speed: position.speed,
              heading: position.heading,
              createdAt: now,
            );
          });
        }

        ref.invalidate(historyProvider);
      } catch (error) {
        if (!mounted) return;
        _showSnack(context, 'Location update failed: ${error.toString()}');
        return;
      }
        }, onError: (error) {
      if (mounted) {
        _showSnack(context, 'Location update failed: ${error.toString()}');
      }
    });
  }

  Future<void> _startDemoLocationStream({
    required String userId,
    required dynamic repository,
    required Duration interval,
    required int _distanceFilterMeters,
  }) async {
    await _stopTrackingStream();
    _isTrackingSessionActive = true;
    if (mounted) {
      setState(() {});
    }

    _lastUploadAt = null;
    DemoBackend.shared.seedLatestForUser(userId);

    _demoShareTimer = Timer.periodic(interval, (_) async {
      final now = DateTime.now().toUtc();
      if (_lastUploadAt != null && now.difference(_lastUploadAt!).inSeconds < interval.inSeconds) {
        return;
      }
      _lastUploadAt = now;

      try {
        DemoBackend.shared.seedLatestForUser(userId);
        DemoBackend.shared.seedDemoLocationsForMembers(ref.read(activeMapCircleIdProvider) ?? '');
        final latest = DemoBackend.shared.latestLocationFor(userId);
        final position = latest == null ? null : DemoBackend.shared.latestPositionFor(userId);
        if (position == null) {
          return;
        }

        final currentSettings = await ref.read(mapLocationSettingsProvider.future);
        if (!mounted || !currentSettings.canShare) {
          await _stopTrackingStream();
          return;
        }

        await _handleSafeZoneTransitions(userId, position, eventTime: now);

        await repository.uploadLocationUpdate(
          userId: userId,
          position: position,
          batteryLevel: latest?.batteryLevel,
        );

        if (mounted) {
          setState(() {
            _memberLocations[userId] = _mapMemberLocation(
              userId: userId,
              position: position,
              batteryLevel: latest?.batteryLevel,
            );
          });
        }

        ref.invalidate(historyProvider);
      } catch (_) {}
    });
  }

  LocationUpdate _mapMemberLocation({
    required String userId,
    required Position position,
    double? batteryLevel,
  }) {
    final now = DateTime.now().toUtc();
    return LocationUpdate(
      id: now.microsecondsSinceEpoch.toString(),
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
  }

  Position? _latestDemoPosition(String userId) {
    try {
      return DemoBackend.shared.latestLocationFor(userId) != null
          ? DemoBackend.shared.latestPositionFor(userId)
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleSafeZoneTransitions(
    String userId,
    Position position, {
    required DateTime eventTime,
  }) async {
    if (_activeCircleId == null) return;

    final relevantZones = _safeZones
        .where((zone) => zone.appliesToAllMembers || zone.targetUserId == userId)
        .toList(growable: false);
    if (relevantZones.isEmpty) return;

    for (final zone in relevantZones) {
      final distanceMeters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        zone.centerLatitude,
        zone.centerLongitude,
      );
      final isInside = distanceMeters <= zone.radiusMeters;
      final state = _safeZoneStates.putIfAbsent(zone.id, _SafeZoneRuntimeState.new);

      if (state.lastKnownInside == null) {
        state.lastKnownInside = isInside;
        continue;
      }

      if (state.lastKnownInside == isInside) {
        state.pendingInside = null;
        state.pendingSince = null;
        continue;
      }

      if (state.pendingInside != isInside) {
        state.pendingInside = isInside;
        state.pendingSince = eventTime;
        continue;
      }

      if (eventTime.difference(state.pendingSince ?? eventTime) < _safeZoneDebounce) {
        continue;
      }

      if (state.lastEventAt != null &&
          eventTime.difference(state.lastEventAt!) < _safeZoneEventCooldown) {
        continue;
      }

      final eventType = isInside ? 'enter' : 'exit';
      state.lastKnownInside = isInside;
      state.pendingInside = null;
      state.pendingSince = null;
      state.lastEventAt = eventTime;

      try {
        await ref.read(safeZoneControllerProvider).logZoneEvent(
          zoneId: zone.id,
          userId: userId,
          eventType: eventType,
          eventTimestamp: eventTime,
        );
        await ref.read(safeCircleNotificationControllerProvider).notifySafeZoneTransition(
              circleId: _activeCircleId!,
              zoneId: zone.id,
              zoneName: zone.name,
              isEnter: isInside,
              latitude: position.latitude,
              longitude: position.longitude,
            );
      } catch (_) {}

      if (mounted) {
        _showSnack(
          context,
          _zoneMessage(zone.name, eventType),
        );
      }
    }
  }

  Future<void> _stopTrackingStream() async {
    _demoShareTimer?.cancel();
    _demoShareTimer = null;

    if (_shareSubscription == null) {
      _isTrackingSessionActive = false;
      _lastUploadAt = null;
      return;
    }

    await _shareSubscription!.cancel();
    _shareSubscription = null;
    _isTrackingSessionActive = false;
    _lastUploadAt = null;
    if (mounted) {
      setState(() {});
    }
  }

  Widget _mapBody(
    AsyncValue<dynamic> positionState,
    AsyncValue<LocationSharingSettings> settingsState,
    AsyncValue<bool> canShareMembership,
    List<CircleMember> members,
    List<SafeZone> safeZones,
  ) {
    if (positionState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (positionState.hasError) {
      return ErrorState(message: positionState.error.toString());
    }
    if (canShareMembership.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (canShareMembership.hasError) {
      return ErrorState(message: canShareMembership.error.toString());
    }

    final settings = settingsState.valueOrNull;
    final canShare = canShareMembership.valueOrNull ?? false;

    if (!canShare || _memberIds.isEmpty) {
      return const EmptyState(
        message:
            'You are not in an accepted circle yet. Join via invite code first, then share your location.',
      );
    }

    final position = positionState.asData?.value;

    return Column(
      children: [
        _sharingStatusBar(settings),
        _sharingControls(settings),
        Expanded(child: _memberMap(position, members, safeZones)),
      ],
    );
  }

  Widget _sharingStatusBar(LocationSharingSettings? settings) {
    final backgroundText = settings?.isBackgroundSharingEnabled == true ? ' · background on' : ' · foreground only';
    final status = _isTrackingSessionActive
        ? 'Location sharing is active$backgroundText'
        : settings?.isSharingEnabled == true && settings?.isPaused == true
            ? 'Location sharing is paused'
            : 'Location sharing is stopped';

    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.primaryContainer,
      padding: const EdgeInsets.all(12),
      child: Text(status, style: Theme.of(context).textTheme.titleSmall),
    );
  }

  Widget _sharingControls(LocationSharingSettings? settings) {
    final canStart = !_isShareActionRunning &&
        !_isTrackingSessionActive &&
        _activeCircleId != null &&
        _memberIds.isNotEmpty;

    final canPause = !_isShareActionRunning && _isTrackingSessionActive;

    final canStop =
        !_isShareActionRunning && (_isTrackingSessionActive || settings?.isSharingEnabled == true);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: FilledButton(
              onPressed: canStart ? _startSharing : null,
              child: const Text('Start sharing'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: canPause ? _pauseSharing : null,
              child: const Text('Pause sharing'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: canStop ? _stopSharing : null,
              child: const Text('Stop sharing'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _memberMap(
    Position? currentPosition,
    List<CircleMember> members,
    List<SafeZone> safeZones,
  ) {
    final markers = _buildMarkers(currentPosition, members);
    final safeZoneCircles = _buildSafeZoneCircles(safeZones);
    LatLng start;

    if (markers.isNotEmpty) {
      final first = markers.first.position;
      start = first;
    } else if (currentPosition != null) {
      start = LatLng(currentPosition.latitude, currentPosition.longitude);
    } else {
      return const Center(child: EmptyState(message: 'Waiting for shared locations.'));
    }

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: start, zoom: 14),
      onMapCreated: (controller) {
        if (!_mapController.isCompleted) {
          _mapController.complete(controller);
        }
      },
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      markers: markers,
      circles: safeZoneCircles,
    );
  }

  Set<Circle> _buildSafeZoneCircles(List<SafeZone> safeZones) {
    final currentUserId = ref.read(authControllerProvider).user?.id;

    return safeZones
        .where((zone) => zone.isActive)
        .where((zone) => zone.radiusMeters > 0)
        .map(
          (zone) => Circle(
            circleId: CircleId(zone.id),
            center: LatLng(zone.centerLatitude, zone.centerLongitude),
            radius: zone.radiusMeters.toDouble(),
            strokeWidth: 2,
            strokeColor: (zone.appliesToAllMembers ||
                    (currentUserId != null && zone.targetUserId == currentUserId))
                ? Colors.green
                : Colors.orange,
            fillColor: (zone.appliesToAllMembers ||
                    (currentUserId != null && zone.targetUserId == currentUserId))
                ? Colors.green.withOpacity(0.10)
                : Colors.orange.withOpacity(0.10),
            consumeTapEvents: true,
          ),
        )
        .toSet();
  }

  Set<Marker> _buildMarkers(Position? currentPosition, List<CircleMember> members) {
    final markers = <Marker>{};
    final memberById = {for (final member in members) member.userId: member};
    final currentUserId = ref.read(authControllerProvider).user?.id;

    for (final entry in _memberLocations.entries) {
      final member = memberById[entry.key];
      final isCurrentUser = entry.key == currentUserId;
      final title = isCurrentUser
          ? 'You'
          : (member?.displayName?.trim().isNotEmpty == true
              ? member!.displayName!.trim()
              : 'Member ${entry.key.substring(0, entry.key.length < 4 ? entry.key.length : 4)}');

      markers.add(
        Marker(
          markerId: MarkerId(entry.key),
          position: LatLng(entry.value.latitude, entry.value.longitude),
          icon: isCurrentUser
              ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure)
              : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose),
          infoWindow: InfoWindow(
            title: title,
            snippet: 'Accuracy ${entry.value.accuracy?.toStringAsFixed(1) ?? 'n/a'} m',
          ),
        ),
      );

    }

    if (currentUserId != null &&
        currentPosition != null &&
        !_memberLocations.containsKey(currentUserId)) {
      markers.add(
        Marker(
          markerId: const MarkerId('current_user'),
          position: LatLng(currentPosition.latitude, currentPosition.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'You'),
        ),
      );
    }

    return markers;
  }

  String _zoneMessage(String zoneName, String eventType) {
    final label = zoneName.trim().isNotEmpty ? zoneName : 'safe zone';
    return eventType == 'enter'
        ? 'Entered $label'
        : 'Exited $label';
  }

  void _showSnack(BuildContext context, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SafeZoneRuntimeState {
  bool? lastKnownInside;
  bool? pendingInside;
  DateTime? pendingSince;
  DateTime? lastEventAt;
}
