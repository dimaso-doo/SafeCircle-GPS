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
    return _ensureClient().auth.onAuthStateChange.map((event) => event.session?.user).map((user) {
      if (user == null) return null;
      return _toAppUser(user.id, user.email, user.userMetadata?['display_name'] as String?);
    });
  }

  AppUser? _toAppUser(String id, String? email, String? displayName) {
    return AppUser(id: id, email: email, displayName: displayName);
  }

  Future<void> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    if (AppConfig.runInDemoMode) {
      await DemoBackend.shared.register(
        email: email,
        password: password,
        displayName: displayName,
      );
      return;
    }

    final response = await _ensureClient().auth.signUp(
      email: email,
      password: password,
      data: {
        if (displayName != null && displayName.trim().isNotEmpty)
          'display_name': displayName.trim(),
      },
    );

    final user = response.user;
    if (user == null) {
      throw StateError('Sign up did not return a user. Confirm email flow before creating profile.');
    }

    await ensureUserProfile(user.id, displayName);
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

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (AppConfig.runInDemoMode) {
      await DemoBackend.shared.signIn(email: email, password: password);
      return;
    }

    await _ensureClient().auth.signInWithPassword(email: email, password: password);
  }

  Future<void> forgotPassword(String email) async {
    if (AppConfig.runInDemoMode) {
      return;
    }
    await _ensureClient().auth.resetPasswordForEmail(email);
  }

  Future<void> signOut() async {
    if (AppConfig.runInDemoMode) {
      await DemoBackend.shared.signOut();
      return;
    }
    await _ensureClient().auth.signOut();
  }
}
