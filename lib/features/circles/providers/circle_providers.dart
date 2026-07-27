import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_strings.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../models/circle.dart';
import '../../../models/circle_member.dart';
import '../../../repositories/circle_repository.dart';
import '../../subscription/providers/subscription_provider.dart';

final circleRepositoryProvider = Provider<CircleRepository>((ref) {
  final client = AppConfig.runInDemoMode ? null : Supabase.instance.client;
  return CircleRepository(client);
});

final circlesProvider = FutureProvider.autoDispose<List<CircleModel>>((ref) async {
  final user = ref.watch(authControllerProvider).user;
  if (user == null) return const <CircleModel>[];
  final repository = ref.watch(circleRepositoryProvider);
  return repository.getCirclesForUser(user.id);
});

final selectedCircleIdProvider = StateProvider<String?>((_) => null);

final circleMembersProvider =
    FutureProvider.autoDispose.family<List<CircleMember>, String>((ref, circleId) async {
  final repository = ref.watch(circleRepositoryProvider);
  return repository.getMembersForCircle(circleId);
});

final circleControllerProvider = Provider((ref) => CircleController(ref));

class CircleController {
  CircleController(this.ref);

  final Ref ref;

  Future<void> createCircle(String name) async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;

    final existingCircles = await ref.read(circlesProvider.future);
    final subscription = await ref.read(subscriptionStateProvider.future);
    if (!subscription.canCreateOrJoinCircle(existingCircles.length)) {
      throw StateError(
        'Free plan allows ${subscription.maxCircles} circle only. Upgrade to Premium for more circles.',
      );
    }

    final repository = ref.read(circleRepositoryProvider);
    final circleId =
        await repository.createCircle(ownerId: user.id, name: name);
    ref.read(selectedCircleIdProvider.notifier).state = circleId;
    ref.invalidate(circlesProvider);
  }

  Future<void> joinCircle(String inviteCode) async {
    final repository = ref.read(circleRepositoryProvider);
    final existingCircles = await ref.read(circlesProvider.future);
    final existingIds = existingCircles.map((circle) => circle.id).toSet();
    final subscription = await ref.read(subscriptionStateProvider.future);
    if (!subscription.canCreateOrJoinCircle(existingCircles.length)) {
      throw StateError(
        'Free plan allows ${subscription.maxCircles} accepted circle memberships. Upgrade to Premium to join more.',
      );
    }

    await repository.joinCircleByInviteCode(inviteCode);
    ref.invalidate(circlesProvider);
    final updatedCircles = await ref.read(circlesProvider.future);
    final joinedCircle = updatedCircles
        .where((circle) => !existingIds.contains(circle.id))
        .firstOrNull;
    if (joinedCircle != null) {
      ref.read(selectedCircleIdProvider.notifier).state = joinedCircle.id;
    }
  }

  Future<void> refreshInviteCode(String circleId) async {
    final repository = ref.read(circleRepositoryProvider);
    await repository.regenerateInviteCode(circleId);
    ref.invalidate(circlesProvider);
  }

  Future<void> deleteCircle(String circleId) async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;

    await ref.read(circleRepositoryProvider).deleteCircle(
          circleId: circleId,
          requesterId: user.id,
        );
    _refreshAfterMembershipChange(circleId);
  }

  Future<void> leaveCircle(String circleId) async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;

    await ref.read(circleRepositoryProvider).leaveCircle(
          circleId: circleId,
          userId: user.id,
        );
    _refreshAfterMembershipChange(circleId);
  }

  Future<void> removeMember({
    required String circleId,
    required String memberUserId,
  }) async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;

    await ref.read(circleRepositoryProvider).removeMember(
          circleId: circleId,
          memberUserId: memberUserId,
          requesterId: user.id,
        );
    ref.invalidate(circleMembersProvider(circleId));
  }

  void openCircle(String? circleId) {
    ref.read(selectedCircleIdProvider.notifier).state = circleId;
    if (circleId != null) {
      ref.invalidate(circleMembersProvider(circleId));
    }
  }

  void _refreshAfterMembershipChange(String circleId) {
    if (ref.read(selectedCircleIdProvider) == circleId) {
      ref.read(selectedCircleIdProvider.notifier).state = null;
    }
    ref.invalidate(circleMembersProvider(circleId));
    ref.invalidate(circlesProvider);
  }
}
