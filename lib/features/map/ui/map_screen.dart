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
import '../../../models/location_update.dart';
import '../../../models/location_sharing_settings.dart';
import '../../../services/location/location_service.dart';
import '../../../features/settings/providers/settings_provider.dart';
import '../../../features/notifications/providers/notification_provider.dart';
import '../providers/map_provider.dart';
import 'location_permission_gate.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key, required this.onOpenFamily});

  final VoidCallback onOpenFamily;

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
  bool _isStartingLocationStream = false;
  bool _isShareActionRunning = false;
  DateTime? _lastUploadAt;

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

    if (!permissionState.hasValue ||
        permissionState.valueOrNull != LocationPermissionState.granted) {
      return Scaffold(
        appBar: AppBar(title: const Text('Map')),
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

    return Scaffold(
      appBar: AppBar(title: const Text('Map')),
      body: membersState.when(
        data: (members) => _mapBody(
          positionState,
          settingsState,
          canShareMembership,
          members,
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
        if (!mounted) return;
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
    if (_isTrackingSessionActive || _isStartingLocationStream) {
      return;
    }

    _isStartingLocationStream = true;
    try {
      final user = ref.read(authControllerProvider).user;
      if (user == null) return;

      final settings = await ref.read(mapLocationSettingsProvider.future);
      if (!settings.canShare) {
        throw StateError('Location sharing is disabled.');
      }

      final repository = ref.read(mapLocationRepositoryProvider);
      final service = ref.read(locationServiceProvider);
      final effectiveInterval =
          Duration(seconds: settings.effectiveUpdateIntervalSeconds);
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
        if (mounted) {
          setState(() {
            _memberLocations[user.id] = _mapMemberLocation(
              userId: user.id,
              position: position,
            );
          });
        }

        if (_lastUploadAt != null &&
            now.difference(_lastUploadAt!).inSeconds <
                settings.effectiveUpdateIntervalSeconds) {
          return;
        }
        _lastUploadAt = now;

        try {
          final currentSettings =
              await ref.read(mapLocationSettingsProvider.future);
          if (!mounted || !currentSettings.canShare) {
            await _stopTrackingStream();
            return;
          }

          final batteryLevel = await service.batteryLevel();
          if (mounted) {
          }
          await repository.uploadLocationUpdate(
            userId: user.id,
            position: position,
            batteryLevel: batteryLevel,
          );
          ref.invalidate(historyProvider);
        } catch (error) {
          if (!mounted) return;
          _showSnack(context, 'Location update failed: ${error.toString()}');
        }
      }, onError: (error) {
        _isTrackingSessionActive = false;
        if (mounted) {
          setState(() {});
          _showSnack(context, 'Location update failed: ${error.toString()}');
        }
      }, onDone: () {
        _isTrackingSessionActive = false;
        if (mounted) {
          setState(() {});
        }
      });
    } finally {
      _isStartingLocationStream = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _startDemoLocationStream({
    required String userId,
    required dynamic repository,
    required Duration interval,
    required int distanceFilterMeters,
  }) async {
    final _ = distanceFilterMeters;
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
  ) {
    if (positionState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (positionState.hasError) {
      return ErrorState(message: positionState.error.toString());
    }
    final settings = settingsState.valueOrNull;
    final canShare = canShareMembership.valueOrNull ?? false;
    final membershipResolved = canShareMembership.hasValue;
    final position = positionState.asData?.value;
    final pendingSharingIntent = ref.watch(pendingSharingIntentProvider);

    if (canShare &&
        pendingSharingIntent &&
        settings?.canShare != true &&
        !_isShareActionRunning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !ref.read(pendingSharingIntentProvider) ||
            _isShareActionRunning) {
          return;
        }
        ref.read(pendingSharingIntentProvider.notifier).state = false;
        _startSharing();
      });
    }

    if (membershipResolved &&
        canShare &&
        settings?.canShare == true &&
        !_isTrackingSessionActive &&
        !_isStartingLocationStream &&
        !_isShareActionRunning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _isTrackingSessionActive ||
            _isStartingLocationStream ||
            _isShareActionRunning) {
          return;
        }
        unawaited(_startLocationStream());
      });
    }

    if (membershipResolved &&
        !canShare &&
        settings?.canShare == true &&
        !_isShareActionRunning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isShareActionRunning) return;
        unawaited(_stopSharing());
      });
    }

    return Column(
      children: [
        if (canShare)
          _sharingControls(settings)
        else
          _sharingSetupControls(pendingSharingIntent),
        Expanded(child: _memberMap(position, members)),
      ],
    );
  }

  Widget _sharingSetupControls(bool pendingSharingIntent) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.location_off_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Location sharing is off',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pendingSharingIntent
                            ? 'Create or join a family to finish setup.'
                            : 'You choose when your family can see you.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                ref.read(pendingSharingIntentProvider.notifier).state = true;
                widget.onOpenFamily();
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start sharing'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sharingControls(LocationSharingSettings? settings) {
    final isSharing =
        settings?.isSharingEnabled == true && settings?.isPaused != true;
    final canToggle = !_isShareActionRunning &&
        _activeCircleId != null &&
        _memberIds.isNotEmpty;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  isSharing ? Icons.location_on : Icons.location_off_outlined,
                  color: isSharing ? Colors.green.shade700 : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isSharing
                            ? 'Location sharing is active'
                            : 'Location sharing is off',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isSharing
                            ? 'Accepted family members can see your live location.'
                            : 'Press Start sharing when you want family to see you.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: canToggle
                  ? () {
                      if (isSharing) {
                        _stopSharing();
                      } else {
                        _startSharing();
                      }
                    }
                  : null,
              icon: _isShareActionRunning
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(isSharing ? Icons.stop_circle_outlined : Icons.play_arrow),
              label: Text(isSharing ? 'Stop sharing' : 'Start sharing'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberMap(
    Position? currentPosition,
    List<CircleMember> members,
  ) {
    if (!AppConfig.hasGoogleMapsConfig) {
      return _mapPreviewWithoutApiKey(currentPosition, members);
    }

    final markers = _buildMarkers(currentPosition, members);
    final currentUserId = ref.read(authControllerProvider).user?.id;
    final currentMarkerId =
        currentUserId != null && _memberLocations.containsKey(currentUserId)
            ? currentUserId
            : 'current_user';
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
        unawaited(
          controller.showMarkerInfoWindow(MarkerId(currentMarkerId)),
        );
      },
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      markers: markers,
    );
  }

  Widget _mapPreviewWithoutApiKey(
    Position? currentPosition,
    List<CircleMember> members,
  ) {
    final memberById = {for (final member in members) member.userId: member};
    final locations = _memberLocations.entries.toList(growable: false);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primaryContainer,
            Theme.of(context).colorScheme.surface,
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(
                        Icons.map_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Live map preview is active. Google map tiles will appear after the platform API key is connected.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withOpacity(0.72),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: locations.isEmpty && currentPosition == null
                      ? const Center(
                          child: EmptyState(
                            message: 'Waiting for shared member locations.',
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: locations.isNotEmpty ? locations.length : 1,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            if (locations.isEmpty) {
                              return _locationPreviewTile(
                                name: _currentUserDisplayName(),
                                latitude: currentPosition!.latitude,
                                longitude: currentPosition.longitude,
                                isCurrentUser: true,
                              );
                            }

                            final entry = locations[index];
                            final member = memberById[entry.key];
                            final currentUserId = ref.read(authControllerProvider).user?.id;
                            final isCurrentUser = entry.key == currentUserId;
                            final name = isCurrentUser
                                ? _currentUserDisplayName()
                                : member?.displayName?.trim().isNotEmpty == true
                                    ? member!.displayName!.trim()
                                    : 'Circle member';
                            return _locationPreviewTile(
                              name: name,
                              latitude: entry.value.latitude,
                              longitude: entry.value.longitude,
                              isCurrentUser: isCurrentUser,
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _locationPreviewTile({
    required String name,
    required double latitude,
    required double longitude,
    required bool isCurrentUser,
  }) {
    return ListTile(
      tileColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: CircleAvatar(
        child: Icon(isCurrentUser ? Icons.my_location : Icons.location_on),
      ),
      title: Text(name),
      subtitle: Text(
        '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
      ),
      trailing: const Icon(Icons.circle, size: 12, color: Colors.green),
    );
  }

  Set<Marker> _buildMarkers(Position? currentPosition, List<CircleMember> members) {
    final markers = <Marker>{};
    final memberById = {for (final member in members) member.userId: member};
    final currentUserId = ref.read(authControllerProvider).user?.id;
    final currentUserName = _currentUserDisplayName();

    for (final entry in _memberLocations.entries) {
      final member = memberById[entry.key];
      final isCurrentUser = entry.key == currentUserId;
      final title = isCurrentUser
          ? currentUserName
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
          infoWindow: InfoWindow(title: currentUserName),
        ),
      );
    }

    return markers;
  }

  String _currentUserDisplayName() {
    final name = ref.read(authControllerProvider).user?.displayName?.trim();
    return name?.isNotEmpty == true ? name! : 'You';
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
