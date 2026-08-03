import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/empty_states.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../models/circle.dart';
import '../../history/ui/history_screen.dart';
import '../../map/providers/map_provider.dart';
import '../../notifications/providers/notification_provider.dart';
import '../providers/circle_providers.dart';

class CirclesScreen extends ConsumerStatefulWidget {
  const CirclesScreen({super.key, required this.onFamilyReady});

  final VoidCallback onFamilyReady;

  @override
  ConsumerState<CirclesScreen> createState() => _CirclesScreenState();
}

class _CirclesScreenState extends ConsumerState<CirclesScreen> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  bool _isCreating = false;
  bool _isJoining = false;
  final Set<String> _busyCircleIds = <String>{};

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _createCircle() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isCreating = true);
    try {
      await ref.read(circleControllerProvider).createCircle(name);
      _nameController.clear();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Circle created.')));
      widget.onFamilyReady();
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().contains('plan allows')
          ? 'You already have a family. Share its invite code to add another person.'
          : 'Unable to create family. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _joinCircle() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    setState(() => _isJoining = true);
    try {
      await ref.read(circleControllerProvider).joinCircle(code);
      _codeController.clear();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Joined circle.')));
      widget.onFamilyReady();
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().contains('plan allows')
          ? 'You already belong to a family.'
          : 'Unable to join family. Check the invite code and try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  void _openMembers(CircleModel circle) {
    final currentUserId = ref.read(authControllerProvider).user?.id;
    final isOwner = currentUserId == circle.ownerId;
    ref.read(circleControllerProvider).openCircle(circle.id);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, __) {
          final members = ref.watch(circleMembersProvider(circle.id));
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${circle.name} members',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 320,
                  child: members.when(
                    data: (membersList) {
                      if (membersList.isEmpty) {
                        return const EmptyState(message: 'No members yet.');
                      }
                      return ListView.separated(
                        itemCount: membersList.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final member = membersList[index];
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                (member.displayName?.isNotEmpty == true)
                                    ? member.displayName!
                                        .substring(0, 1)
                                        .toUpperCase()
                                    : '?',
                              ),
                            ),
                            title: Text(member.displayName ?? 'Unknown'),
                            subtitle: Text(
                              '${member.role}${member.isAccepted ? ' · Accepted' : ' · Pending'}',
                            ),
                            trailing: isOwner &&
                                    member.userId != currentUserId
                                ? IconButton(
                                    tooltip: 'Remove member',
                                    icon: const Icon(
                                      Icons.person_remove_outlined,
                                    ),
                                    onPressed: () => _confirmRemoveMember(
                                      circleId: circle.id,
                                      memberUserId: member.userId,
                                      memberName:
                                          member.displayName ?? 'this member',
                                    ),
                                  )
                                : null,
                          );
                        },
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => ErrorState(message: error.toString()),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      if (isOwner) {
                        await _confirmDeleteCircle(circle);
                      } else {
                        await _confirmLeaveCircle(circle);
                      }
                    },
                    icon: Icon(
                      isOwner
                          ? Icons.delete_forever_outlined
                          : Icons.logout,
                    ),
                    label: Text(
                      isOwner ? 'Delete family' : 'Leave family',
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmDeleteCircle(CircleModel circle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${circle.name}?'),
        content: const Text(
          'This permanently deletes the family and removes every member from it. '
          'Its invite code, safe zones and family events will also be removed. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete family'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runCircleAction(
      circle.id,
      action: () =>
          ref.read(circleControllerProvider).deleteCircle(circle.id),
      successMessage: '${circle.name} was deleted.',
    );
  }

  Future<void> _confirmLeaveCircle(CircleModel circle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Leave ${circle.name}?'),
        content: const Text(
          'You will stop seeing this family and its shared locations. '
          'The family and its other members will remain.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave family'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runCircleAction(
      circle.id,
      action: () =>
          ref.read(circleControllerProvider).leaveCircle(circle.id),
      successMessage: 'You left ${circle.name}.',
    );
  }

  Future<void> _confirmRemoveMember({
    required String circleId,
    required String memberUserId,
    required String memberName,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove $memberName?'),
        content: const Text(
          'This member will immediately lose access to this family and its '
          'shared locations. They can join again later with a valid invite code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove member'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(circleControllerProvider).removeMember(
            circleId: circleId,
            memberUserId: memberUserId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$memberName was removed.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to remove this member.')),
      );
    }
  }

  Future<void> _runCircleAction(
    String circleId, {
    required Future<void> Function() action,
    required String successMessage,
  }) async {
    setState(() => _busyCircleIds.add(circleId));
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update this family. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busyCircleIds.remove(circleId));
      }
    }
  }

  Widget _familyCard(CircleModel circle) {
    final currentUserId = ref.read(authControllerProvider).user?.id;
    final isOwner = currentUserId == circle.ownerId;
    final isBusy = _busyCircleIds.contains(circle.id);

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.groups)),
            title: Text(circle.name),
            subtitle: Text(
              'Invite code: ${circle.inviteCode}\n'
              '${isOwner ? 'You are the owner' : 'You are a member'}',
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: isBusy ? null : () => _openMembers(circle),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed:
                        isBusy ? null : () => _openMembers(circle),
                    icon: const Icon(Icons.people_outline),
                    label: const Text('Members'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: isBusy
                        ? null
                        : () => isOwner
                            ? _confirmDeleteCircle(circle)
                            : _confirmLeaveCircle(circle),
                    icon: isBusy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            isOwner
                                ? Icons.delete_outline
                                : Icons.logout,
                          ),
                    label: Text(
                      isOwner ? 'Delete family' : 'Leave family',
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor:
                          Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _offerNotifications() async {
    if (!mounted) return;
    final shouldEnable = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Family alerts'),
        content: const Text(
          'Would you like KinOrbit to notify you about important family sharing changes? '
          'You can change this later in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );

    if (shouldEnable == true) {
      await ref
          .read(safeCircleNotificationControllerProvider)
          .ensureNotificationsReady();
    }
  }

  void _openCreateDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create family'),
          content: TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Family/Circle name'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                ref.read(pendingSharingIntentProvider.notifier).state = false;
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _isCreating ? null : _createCircle,
              child: _isCreating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  void _openJoinDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Join family'),
          content: TextField(
            controller: _codeController,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'Invite code'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                ref.read(pendingSharingIntentProvider.notifier).state = false;
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _isJoining ? null : _joinCircle,
              child: _isJoining
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Join'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final circles = ref.watch(circlesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Family')),
      body: circles.when(
        data: (items) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(circlesProvider);
            await ref.read(circlesProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (items.isEmpty) ...[
                const SizedBox(height: 56),
                const Icon(Icons.family_restroom, size: 72),
                const SizedBox(height: 20),
                const Text(
                  'Add your family',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Create a private family group or join one with an invite code.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
              ] else ...[
                const Text(
                  'Your family',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                for (final circle in items)
                  _familyCard(circle),
                const SizedBox(height: 16),
              ],
              FilledButton.icon(
                onPressed: _openCreateDialog,
                icon: const Icon(Icons.add),
                label: Text(
                  items.isEmpty ? 'Create family' : 'Add new family',
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _openJoinDialog,
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Join with invite code'),
              ),
              if (items.isNotEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.lock_outline),
                    title: Text('Your families are private'),
                    subtitle: Text(
                      'Only accepted members can see shared locations.',
                    ),
                  ),
                ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 28),
                const Text(
                  'Family tools',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.history),
                        title: const Text('Location history'),
                        subtitle: const Text('Review family routes and recent locations.'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const HistoryScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorState(message: error.toString()),
      ),
    );
  }
}
