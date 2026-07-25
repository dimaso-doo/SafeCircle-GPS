import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_strings.dart';
import '../../../repositories/auth_repository.dart';
import '../../../models/app_user.dart';

class AuthState {
  const AuthState({
    this.user,
    this.isLoading = false,
    this.errorMessage,
  });

  final AppUser? user;
  final bool isLoading;
  final String? errorMessage;

  AuthState copyWith({
    AppUser? user,
    bool? isLoading,
    String? errorMessage,
  }) {
    return AuthState(
      user: user,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this.ref, this.repository)
      : super(const AuthState(isLoading: true)) {
    _subscription = repository.watchAuthChanges().listen((user) {
      state = AuthState(user: user, isLoading: false, errorMessage: null);
    });

    state = AuthState(user: repository.currentUser, isLoading: false);
  }

  final Ref ref;
  final AuthRepository repository;
  StreamSubscription<AppUser?>? _subscription;

  Future<bool> continueWithName(String displayName) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await repository.signInAnonymously(displayName);
      return true;
    } catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.toString());
      return false;
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await repository.signOut();
      state = const AuthState(isLoading: false);
    } catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.toString());
    }
  }

  Future<bool> deleteAccount() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await repository.deleteAccount();
      state = const AuthState(isLoading: false);
      return true;
    } catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.toString());
      return false;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final client = AppConfig.runInDemoMode ? null : Supabase.instance.client;
  return AuthRepository(client);
});

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref, ref.watch(authRepositoryProvider));
});
