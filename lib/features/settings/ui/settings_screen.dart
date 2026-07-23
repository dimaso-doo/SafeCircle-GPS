import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/widgets/empty_states.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/map/providers/map_provider.dart';
import '../../../features/notifications/providers/notification_provider.dart';
import '../../../features/paywall/ui/paywall_screen.dart';
import '../../../features/settings/providers/settings_provider.dart';
import '../../../features/subscription/providers/subscription_provider.dart';
import '../../../models/location_sharing_settings.dart';
import '../../../models/notification_settings.dart';
import '../../../models/user_subscription.dart';
import '../../../services/location/location_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final subscriptionState = ref.watch(subscriptionStateProvider);
    final settingsState = ref.watch(mapLocationSettingsProvider);
    final backgroundPermission = ref.watch(backgroundPermissionGrantedProvider);
    final notificationSettings = ref.watch(notificationSettingsProvider);

    if (authState.user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const EmptyState(message: 'Sign in to manage settings.'),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: subscriptionState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorState(message: error.toString()),
        data: (subscription) => settingsState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ErrorState(message: error.toString()),
          data: (settings) => notificationSettings.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => ErrorState(message: error.toString()),
            data: (notificationData) => _SettingsContent(
              authState: authState,
              settings: settings,
              notificationData: notificationData,
              subscription: subscription,
              backgroundPermission: backgroundPermission,
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsContent extends ConsumerWidget {
  const _SettingsContent({
    required this.authState,
    required this.settings,
    required this.notificationData,
    required this.subscription,
    required this.backgroundPermission,
  });

  final AuthState authState;
  final LocationSharingSettings settings;
  final NotificationSettings notificationData;
  final UserSubscriptionState subscription;
  final AsyncValue<bool> backgroundPermission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canUsePriority = subscription.canUsePriorityUpdates || subscription.isPremium;
    final backgroundIsGranted = backgroundPermission.valueOrNull == true;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Subscription'),
        ListTile(
          title: Text(subscription.planName),
          subtitle: Text(
            subscription.isPremium
                ? 'Premium plan active'
                : 'Free plan: 1 circle, up to 2 members, 24h history',
          ),
          trailing: subscription.isPremium
              ? const Icon(Icons.star, color: Colors.orange)
              : TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PaywallScreen()),
                  ),
                  child: const Text('Upgrade'),
                ),
        ),
        const Divider(height: 24),
        _sectionTitle('Push notifications'),
        SwitchListTile(
          value: notificationData.pushEnabled,
          title: const Text('Push notifications'),
          subtitle: const Text('Allow SafeCircle alerts to reach your device.'),
          onChanged: (value) =>
              ref.read(safeCircleNotificationControllerProvider).setPushEnabled(value),
        ),
        SwitchListTile(
          value: notificationData.notifySos,
          title: const Text('SOS alerts'),
          subtitle: const Text('Receive emergency SOS alerts from circle members.'),
          onChanged: notificationData.pushEnabled
              ? (value) => ref.read(safeCircleNotificationControllerProvider).setNotifySos(value)
              : null,
        ),
        SwitchListTile(
          value: notificationData.notifySafeZoneEnter,
          title: const Text('Safe zone entered'),
          subtitle: const Text('Receive alerts when a member enters a safe zone.'),
          onChanged: notificationData.pushEnabled
              ? (value) =>
                  ref.read(safeCircleNotificationControllerProvider).setNotifySafeZoneEnter(value)
              : null,
        ),
        SwitchListTile(
          value: notificationData.notifySafeZoneExit,
          title: const Text('Safe zone exited'),
          subtitle: const Text('Receive alerts when a member leaves a safe zone.'),
          onChanged: notificationData.pushEnabled
              ? (value) =>
                  ref.read(safeCircleNotificationControllerProvider).setNotifySafeZoneExit(value)
              : null,
        ),
        SwitchListTile(
          value: notificationData.notifySharingPaused,
          title: const Text('Sharing paused'),
          subtitle: const Text('Receive alerts when a member pauses live sharing.'),
          onChanged: notificationData.pushEnabled
              ? (value) =>
                  ref.read(safeCircleNotificationControllerProvider).setNotifySharingPaused(value)
              : null,
        ),
        const Divider(height: 24),
        _sectionTitle('Location sharing controls'),
        SwitchListTile(
          value: settings.isSharingEnabled,
          title: const Text('Location sharing enabled'),
          subtitle: const Text('Allow SafeCircle to upload your location when you tap Share now.'),
          onChanged: (value) => ref.read(settingsControllerProvider).setSharingEnabled(value),
        ),
        SwitchListTile(
          value: settings.isPaused,
          title: const Text('Pause sharing now'),
          subtitle: const Text('Temporarily stop sending new updates without disabling consent.'),
          onChanged: settings.isSharingEnabled
              ? (value) => ref.read(settingsControllerProvider).setPaused(value)
              : null,
        ),
        const Divider(height: 24),
        _sectionTitle('Background location sharing'),
        SwitchListTile(
          value: settings.isBackgroundSharingEnabled,
          title: const Text('Track in background'),
          subtitle: const Text(
            'Keep family safety updates active when the app is not visible. '
            'Requires explicit OS permission and uses a visible foreground service on Android.',
          ),
          onChanged: (value) => _handleBackgroundToggle(context, ref, value),
        ),
        if (backgroundPermission.isLoading)
          const ListTile(
            leading: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text('Checking background permission...'),
          )
        else if (backgroundPermission.hasError)
          ListTile(title: Text('Background permission check failed: ${backgroundPermission.error}'))
        else if (!backgroundIsGranted && settings.isBackgroundSharingEnabled)
          ListTile(
            title: const Text('Background permission is not enabled.'),
            subtitle: const Text(
              'Open location settings and grant "Allow all the time" to continue background updates.',
            ),
            trailing: TextButton(
              onPressed: () async {
                await ref.read(locationServiceProvider).openSettings();
                ref.invalidate(backgroundPermissionGrantedProvider);
              },
              child: const Text('Open settings'),
            ),
          )
        else if (!backgroundIsGranted && !settings.isBackgroundSharingEnabled)
          const ListTile(
            title: Text('Background permission currently off.'),
            subtitle: Text('You can turn it on any time from this screen.'),
          ),
        const Divider(height: 24),
        _sectionTitle('Battery optimization'),
        ListTile(
          title: const Text('Update interval'),
          subtitle: Text('Every ${settings.updateIntervalSeconds} seconds'),
          trailing: SizedBox(
            width: 180,
            child: Slider.adaptive(
              min: canUsePriority
                  ? 10
                  : subscription.minFreeUpdateIntervalSeconds.toDouble(),
              max: 300,
              divisions: canUsePriority ? 29 : 27,
              value: settings.updateIntervalSeconds
                  .clamp(
                    canUsePriority ? 10 : subscription.minFreeUpdateIntervalSeconds,
                    300,
                  )
                  .toDouble(),
              label: '${settings.updateIntervalSeconds.clamp(canUsePriority ? 10 : subscription.minFreeUpdateIntervalSeconds, 300)}s',
              onChanged: (value) =>
                  ref.read(settingsControllerProvider).setUpdateInterval(value.toInt()),
            ),
          ),
        ),
        ListTile(
          title: const Text('Distance filter'),
          subtitle: Text('Send when moved ${settings.distanceFilterMeters}m or more'),
          trailing: SizedBox(
            width: 180,
            child: Slider.adaptive(
              min: canUsePriority
                  ? 10
                  : subscription.minFreeDistanceFilterMeters.toDouble(),
              max: 1000,
              divisions: canUsePriority ? 99 : 90,
              value: settings.distanceFilterMeters.clamp(
                canUsePriority ? 10 : subscription.minFreeDistanceFilterMeters,
                1000,
              ).toDouble(),
              label: '${settings.distanceFilterMeters.clamp(canUsePriority ? 10 : subscription.minFreeDistanceFilterMeters, 1000)}m',
              onChanged: (value) => ref
                  .read(settingsControllerProvider)
                  .setDistanceFilter(value.toInt().clamp(10, 1000)),
            ),
          ),
        ),
        SwitchListTile(
          value: settings.isBatterySavingMode,
          title: const Text('Battery saving mode'),
          subtitle: const Text('Prefer longer intervals and larger movement thresholds to reduce updates.'),
          onChanged: (value) => ref.read(settingsControllerProvider).setBatterySavingMode(value),
        ),
        if (settings.isBatterySavingMode)
          const ListTile(
            title: Text('Battery saving mode on'),
            subtitle: Text('Interval and distance thresholds are automatically raised.'),
          ),
        const Divider(height: 24),
        _sectionTitle('History retention'),
        ListTile(
          title: const Text('Local history retention'),
          subtitle: Text('Keep history for ${settings.historyRetentionHours} hour(s).'),
        ),
        ToggleButtons(
          isSelected: [
            settings.historyRetentionHours == 24,
            settings.historyRetentionHours == 168,
            settings.historyRetentionHours == 720,
          ],
          onPressed: (index) async {
            const values = [24, 168, 720];
            final requestedHours = values[index];

            if (index == 0) {
              await ref.read(settingsControllerProvider).setHistoryRetentionHours(requestedHours);
              return;
            }

            if (subscription.canKeepHistoryHours(requestedHours)) {
              await ref.read(settingsControllerProvider).setHistoryRetentionHours(requestedHours);
            } else {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Premium required for ${index == 1 ? '7-day' : '30-day'} retention.')),
              );
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PaywallScreen()),
              );
            }
          },
          children: const [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('24h (Free)'),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('7d (Premium)'),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('30d (Premium)'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
          onPressed: authState.isLoading
              ? null
              : () async {
                  try {
                    await ref
                        .read(safeCircleNotificationControllerProvider)
                        .deactivateCurrentDeviceToken();
                  } finally {
                    await ref.read(authControllerProvider.notifier).signOut();
                  }
                },
        ),
        const SizedBox(height: 16),
        const Text(
          'Store configuration is explicit: product IDs are read from environment values, not hardcoded. '
          'SafeCircle keeps tracking controls visible and user-initiated at all times.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _handleBackgroundToggle(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    final service = ref.read(locationServiceProvider);

    if (!enabled) {
      await ref.read(settingsControllerProvider).setBackgroundSharingEnabled(false);
      return;
    }

    final confirmed = await _showBackgroundEnableDialog(context);
    if (!confirmed) {
      return;
    }

    final hasPermission = await _ensureBackgroundPermission(service);
    if (!hasPermission) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Background permission is not granted. Open settings to continue in background or keep foreground sharing only.',
          ),
        ),
      );
      await service.openSettings();
      return;
    }

    await ref.read(settingsControllerProvider).setBackgroundSharingEnabled(true);
  }

  Future<bool> _ensureBackgroundPermission(LocationService service) async {
    var permission = await service.checkRawPermission();

    if (permission == LocationPermission.denied || permission == LocationPermission.unableToDetermine) {
      permission = await service.requestRawPermission();
    }

    if (!service.hasForegroundPermission(permission)) {
      return false;
    }

    if (service.hasBackgroundPermission(permission)) {
      return true;
    }

    permission = await service.requestRawPermission();
    return service.hasBackgroundPermission(permission);
  }

  Future<bool> _showBackgroundEnableDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Enable background location sharing'),
          content: const Text(
            'SafeCircle uses background location to keep family visibility active when your app is not open. '
            'This is used only for live family sharing and only while your location sharing is enabled. '
            'You can disable this at any time. A visible background status is always shown.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Continue')),
          ],
        );
      },
    );

    return result == true;
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}
