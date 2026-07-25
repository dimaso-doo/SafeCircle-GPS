import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/empty_states.dart';
import '../../history/ui/history_screen.dart';
import '../../notifications/providers/notification_provider.dart';
import '../../safe_zones/ui/safe_zones_screen.dart';
import '../providers/circle_providers.dart';

class CirclesScreen extends ConsumerStatefulWidget {
  const CirclesScreen({super.key});

  @override
  ConsumerState<CirclesScreen> createState() => _CirclesScreenState();
}

class _CirclesScreenState extends ConsumerState<CirclesScreen> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  bool _isCreating = false;
  bool _isJoining = false;

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
      await _offerNotifications();
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

  void _openMembers(String circleId) {
    ref.read(circleControllerProvider).openCircle(circleId);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => Consumer(
        builder: (context, ref, __) {
          final members = ref.watch(circleMembersProvider(circleId));
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Circle members',
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
                          );
                        },
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => ErrorState(message: error.toString()),
                  ),
                ),
              ],
            ),
          );
        },
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
              onPressed: () => Navigator.of(context).pop(),
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
              onPressed: () => Navigator.of(context).pop(),
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
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.groups)),
                      title: Text(circle.name),
                      subtitle: Text('Invite code: ${circle.inviteCode}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openMembers(circle.id),
                    ),
                  ),
                const SizedBox(height: 16),
              ],
              if (items.isEmpty) ...[
                FilledButton.icon(
                  onPressed: _openCreateDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Create family'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _openJoinDialog,
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('Join with invite code'),
                ),
              ] else
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.lock_outline),
                    title: Text('Your family is private'),
                    subtitle: Text(
                      'To add someone, share the invite code shown above.',
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
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.shield_outlined),
                        title: const Text('Safe zones'),
                        subtitle: const Text('Manage home, school and other family places.'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SafeZonesScreen(),
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
