import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/location/location_service.dart';
import '../providers/map_provider.dart';

class LocationPermissionGate extends ConsumerStatefulWidget {
  const LocationPermissionGate({required this.onPermissionStateChanged, super.key});

  final VoidCallback onPermissionStateChanged;

  @override
  ConsumerState<LocationPermissionGate> createState() => _LocationPermissionGateState();
}

class _LocationPermissionGateState extends ConsumerState<LocationPermissionGate> {
  bool _showSystemPrompt = false;

  void _continueToSystemPrompt() {
    setState(() {
      _showSystemPrompt = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final permission = ref.watch(permissionStateProvider);

    if (!_showSystemPrompt) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'SafeCircle GPS needs foreground location to show your current position and to share updates inside your approved circle.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'You choose when to start sharing. Background tracking can be enabled later from Settings.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _continueToSystemPrompt,
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      );
    }

    return permission.when(
      data: (status) {
        switch (status) {
          case LocationPermissionState.granted:
            return const Center(child: CircularProgressIndicator());
          case LocationPermissionState.deniedForever:
            return _BlockedState(onOpenSettings: () async {
              await ref.read(locationServiceProvider).openSettings();
              widget.onPermissionStateChanged();
            });
          case LocationPermissionState.denied:
          case LocationPermissionState.unknown:
            return _RequestState(
              onRequest: () async {
                final result = await ref.read(locationServiceProvider).requestPermission();
                if (result == LocationPermissionState.granted) {
                  widget.onPermissionStateChanged();
                } else {
                  ref.invalidate(permissionStateProvider);
                }
              },
            );
          default:
            return const Center(
              child: Text('Checking location permission status...'),
            );
        }
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(error.toString())),
    );
  }
}

class _RequestState extends StatelessWidget {
  const _RequestState({required this.onRequest});

  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Tap Continue to allow SafeCircle to read your foreground location.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRequest, child: const Text('Allow location access')),
          ],
        ),
      ),
    );
  }
}

class _BlockedState extends StatelessWidget {
  const _BlockedState({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Location permission is permanently denied. Open app settings and allow location.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onOpenSettings,
              child: const Text('Open settings'),
            ),
          ],
        ),
      ),
    );
  }
}
