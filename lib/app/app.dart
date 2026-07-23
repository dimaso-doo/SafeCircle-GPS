import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../features/auth/providers/auth_provider.dart';
import '../features/auth/ui/welcome_screen.dart';
import '../features/circles/ui/circles_screen.dart';
import '../features/history/ui/history_screen.dart';
import '../features/map/ui/map_screen.dart';
import '../features/notifications/providers/notification_provider.dart';
import '../features/safe_zones/ui/safe_zones_screen.dart';
import '../features/settings/ui/settings_screen.dart';

class SafeCircleApp extends ConsumerStatefulWidget {
  const SafeCircleApp({super.key});

  @override
  ConsumerState<SafeCircleApp> createState() => _SafeCircleAppState();
}

class _SafeCircleAppState extends ConsumerState<SafeCircleApp> {
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    ref.listenManual<AuthState>(
      authControllerProvider,
      (previous, next) {
        final userId = next.user?.id;
        if (userId == null || previous?.user?.id == userId) {
          return;
        }

        unawaited(
          ref
              .read(safeCircleNotificationControllerProvider)
              .ensureNotificationsReady()
              .catchError((_) {}),
        );
      },
      fireImmediately: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    if (authState.isLoading) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    if (authState.user == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appTheme,
        home: const WelcomeScreen(),
      );
    }

    final pages = const [
      MapScreen(),
      CirclesScreen(),
      SafeZonesScreen(),
      HistoryScreen(),
      SettingsScreen(),
    ];

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appTheme,
      home: Scaffold(
        body: IndexedStack(index: _tabIndex, children: pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tabIndex,
          onDestinationSelected: (index) => setState(() => _tabIndex = index),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.map), label: 'Map'),
            NavigationDestination(icon: Icon(Icons.groups), label: 'Family'),
            NavigationDestination(icon: Icon(Icons.security), label: 'Zones'),
            NavigationDestination(icon: Icon(Icons.history), label: 'History'),
            NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      ),
    );
  }
}
