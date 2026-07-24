import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../features/auth/providers/auth_provider.dart';
import '../features/auth/ui/welcome_screen.dart';
import '../features/circles/ui/circles_screen.dart';
import '../features/map/ui/map_screen.dart';
import '../features/settings/ui/settings_screen.dart';

class SafeCircleApp extends ConsumerStatefulWidget {
  const SafeCircleApp({super.key});

  @override
  ConsumerState<SafeCircleApp> createState() => _SafeCircleAppState();
}

class _SafeCircleAppState extends ConsumerState<SafeCircleApp> {
  int _tabIndex = 0;

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

    final pages = [
      MapScreen(onAddFamily: () => setState(() => _tabIndex = 1)),
      const CirclesScreen(),
      const SettingsScreen(),
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
            NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      ),
    );
  }
}
