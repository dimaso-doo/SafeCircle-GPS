import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_strings.dart';
import '../core/demo/demo_backend.dart';
import '../models/app_user.dart';

class AuthRepository {
  AuthRepository([this._client]);

  final SupabaseClient? _client;

  SupabaseClient _ensureClient() {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase client is not configured.');
    }
    return client;
  }

  AppUser? get currentUser {
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.activeUser;
    }

    final user = _client?.auth.currentUser;
    if (user == null) return null;
    return _toAppUser(user.id, user.email, user.userMetadata?['display_name'] as String?);
  }

  Stream<AppUser?> watchAuthChanges() {
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.authStateStream().map((user) => user);
    }
    return _ensureClient().auth.onAuthStateChange.asyncMap((event) async {
      final user = event.session?.user;
      if (user == null) {
        return null;
      }
      final profileName =
          user.userMetadata?['display_name'] as String? ??
          user.userMetadata?['name'] as String? ??
          user.userMetadata?['full_name'] as String? ??
          (user.email?.split('@').first);

      await ensureUserProfile(user.id, profileName);
      return _toAppUser(user.id, user.email, profileName);
    });
  }

  AppUser? _toAppUser(String id, String? email, String? displayName) {
    return AppUser(id: id, email: email, displayName: displayName);
  }

  Future<void> signInAnonymously(String displayName) async {
    final normalizedName = displayName.trim();
    if (normalizedName.length < 2 || normalizedName.length > 50) {
      throw ArgumentError('Name must contain between 2 and 50 characters.');
    }

    if (AppConfig.runInDemoMode) {
      await DemoBackend.shared.signIn(
        email: 'demo@safe-circle.local',
        password: 'demo1234',
      );
      final demoUser = DemoBackend.shared.activeUser;
      if (demoUser != null) {
        DemoBackend.shared.setDisplayName(demoUser.id, normalizedName);
      }
      return;
    }

    final response = await _ensureClient().auth.signInAnonymously(
      data: {
        'display_name': normalizedName,
      },
    );

    final user = response.user;
    if (user == null) {
      throw StateError('KinOrbit could not create your device account.');
    }
  }

  Future<void> ensureUserProfile(String userId, String? displayName) async {
    if (AppConfig.runInDemoMode) {
      if (displayName != null && displayName.trim().isNotEmpty) {
        DemoBackend.shared.setDisplayName(userId, displayName.trim());
      }
      return;
    }

    final requestedName = displayName?.trim();

    final existing = await _ensureClient().from('users').select('id, display_name').eq('id', userId).maybeSingle();

    if (existing == null) {
      await _ensureClient().from('users').insert({
        'id': userId,
        'display_name': requestedName,
      });
      return;
    }

    if (requestedName != null && requestedName.isNotEmpty) {
      await _ensureClient().from('users').update({'display_name': requestedName}).eq('id', userId);
    }
  }

  Future<void> signOut() async {
    if (AppConfig.runInDemoMode) {
      await DemoBackend.shared.signOut();
      return;
    }
    await _ensureClient().auth.signOut();
  }

  Future<void> deleteAccount() async {
    if (AppConfig.runInDemoMode) {
      await DemoBackend.shared.deleteCurrentAccount();
      return;
    }

    final client = _ensureClient();
    await client.functions.invoke('delete-account');

    try {
      await client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // Server-side deletion invalidates the session immediately.
    }
  }
}
