import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_strings.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../models/user_subscription.dart';
import '../../../repositories/subscription_repository.dart';

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((_) {
  final client = AppConfig.runInDemoMode ? null : Supabase.instance.client;
  return SubscriptionRepository(client);
});

final subscriptionStateProvider = FutureProvider.autoDispose<UserSubscriptionState>((ref) async {
  final user = ref.watch(authControllerProvider).user;
  if (user == null) throw StateError('Not signed in');

  final repository = ref.watch(subscriptionRepositoryProvider);
  return repository.getCurrentSubscription(user.id);
});
