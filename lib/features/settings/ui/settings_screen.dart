import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/legal_links.dart';
import '../../../core/widgets/empty_states.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/map/providers/map_provider.dart';
import '../../../features/notifications/providers/notification_provider.dart';
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
        _sectionTitle('Profile'),
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(authState.user?.displayName ?? 'KinOrbit member'),
          subtitle: const Text(
            'No email or password. This account is currently stored on this device.',
          ),
        ),
        const Divider(height: 24),
        _sectionTitle('Push notifications'),
        SwitchListTile(
          value: notificationData.pushEnabled,
          title: const Text('Push notifications'),
          subtitle: const Text('Allow KinOrbit alerts to reach your device.'),
          onChanged: (value) async {
            final controller =
                ref.read(safeCircleNotificationControllerProvider);
            if (value) {
              await controller.ensureNotificationsReady();
            }
            await controller.setPushEnabled(value);
          },
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
        _sectionTitle('History'),
        ListTile(
          title: const Text('Local history retention'),
          subtitle: const Text(
            'Recent family history is kept for 24 hours in the current version.',
          ),
        ),
        const Divider(height: 24),
        _sectionTitle('Privacy and account'),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Privacy policy'),
          subtitle: const Text(
            'See how KinOrbit uses location and protects circle data.',
          ),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => _openLegalLink(
            context,
            LegalLinks.privacyPolicyUrl,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.manage_accounts_outlined),
          title: const Text('Account deletion information'),
          subtitle: const Text(
            'Review what is removed when an account is deleted.',
          ),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => _openLegalLink(
            context,
            LegalLinks.accountDeletionUrl,
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          icon: const Icon(Icons.delete_forever_outlined),
          label: const Text('Delete my account and data'),
          onPressed: authState.isLoading
              ? null
              : () async {
                  final shouldDelete = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Delete account permanently?'),
                      content: const Text(
                        'This permanently removes your profile, circle data, '
                        'location history, safe zones, and sharing settings. '
                        'This action cannot be undone.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(dialogContext).pop(true),
                          child: const Text('Delete permanently'),
                        ),
                      ],
                    ),
                  );
                  if (shouldDelete != true) {
                    return;
                  }
                  try {
                    await ref
                        .read(safeCircleNotificationControllerProvider)
                        .deactivateCurrentDeviceToken();
                  } finally {
                    final deleted = await ref
                        .read(authControllerProvider.notifier)
                        .deleteAccount();
                    if (!deleted && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Account could not be deleted. Please try again.',
                          ),
                        ),
                      );
                    }
                  }
                },
        ),
        const SizedBox(height: 16),
        const Text(
          'KinOrbit keeps tracking controls visible and user-initiated at all times.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _openLegalLink(BuildContext context, String value) async {
    final uri = Uri.tryParse(value);
    final opened = uri != null &&
        uri.hasScheme &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This legal page is not configured yet.'),
        ),
      );
    }
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
            'KinOrbit uses background location to keep family visibility active when your app is not open. '
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
