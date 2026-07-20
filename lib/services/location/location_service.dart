import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';

enum LocationPermissionState {
  unknown,
  granted,
  denied,
  deniedForever,
}

class LocationService {
  LocationService() : _battery = Battery();

  final Battery _battery;

  Future<LocationPermissionState> checkPermission() async {
    return _map(await Geolocator.checkPermission());
  }

  Future<LocationPermission> checkRawPermission() async {
    return Geolocator.checkPermission();
  }

  Future<LocationPermission> requestRawPermission() async {
    return Geolocator.requestPermission();
  }

  bool hasForegroundPermission(LocationPermission permission) {
    return permission == LocationPermission.whileInUse || permission == LocationPermission.always;
  }

  bool hasBackgroundPermission(LocationPermission permission) {
    return permission == LocationPermission.always;
  }

  Future<LocationPermissionState> requestPermission() async {
    final permission = await requestRawPermission();
    return _map(permission);
  }

  Future<Position> currentLocation() {
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 15),
    );
  }

  Future<bool> openSettings() => Geolocator.openAppSettings();

  Stream<Position> locationUpdates({
    required bool backgroundEnabled,
    required int distanceFilterMeters,
    required Duration updateInterval,
    required bool batterySavingMode,
  }) {
    final distanceFilter = distanceFilterMeters < 10
        ? 10
        : (distanceFilterMeters > 5000 ? 5000 : distanceFilterMeters);
    final interval = updateInterval < const Duration(seconds: 5)
        ? const Duration(seconds: 5)
        : updateInterval;

    final settings = _settingsForBackground(
      backgroundEnabled: backgroundEnabled,
      distanceFilter: distanceFilter,
      interval: interval,
      batterySavingMode: batterySavingMode,
    );

    return Geolocator.getPositionStream(locationSettings: settings);
  }

  LocationSettings _settingsForBackground({
    required bool backgroundEnabled,
    required int distanceFilter,
    required Duration interval,
    required bool batterySavingMode,
  }) {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: distanceFilter,
        intervalDuration: interval,
        timeLimit: const Duration(seconds: 20),
        foregroundNotificationConfig: backgroundEnabled
            ? const ForegroundNotificationConfig(
                notificationTitle: 'SafeCircle GPS is tracking',
                notificationText: 'Family location sharing is active in background.',
                notificationChannelName: 'SafeCircle GPS Background',
                setOngoing: true,
              )
            : null,
        useMSLAltitude: false,
      );
    }

    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: batterySavingMode ? LocationAccuracy.medium : LocationAccuracy.best,
        distanceFilter: distanceFilter,
        pauseLocationUpdatesAutomatically: batterySavingMode,
        showBackgroundLocationIndicator: backgroundEnabled,
        allowBackgroundLocationUpdates: backgroundEnabled,
      );
    }

    return LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: distanceFilter,
      timeLimit: const Duration(seconds: 20),
    );
  }

  Future<double?> batteryLevel() async {
    final level = await _battery.batteryLevel;
    if (level < 0) return null;
    return level.toDouble();
  }

  LocationPermissionState _map(LocationPermission permission) {
    switch (permission) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationPermissionState.granted;
      case LocationPermission.denied:
        return LocationPermissionState.denied;
      case LocationPermission.deniedForever:
        return LocationPermissionState.deniedForever;
      case LocationPermission.unableToDetermine:
      default:
        return LocationPermissionState.unknown;
    }
  }
}
