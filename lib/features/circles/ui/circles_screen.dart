import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/empty_states.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../providers/circle_providers.dart';
import '../../../features/paywall/ui/paywall_screen.dart';
import '../../subscription/providers/subscription_provider.dart';

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

    final canCreate = await _ensureCircleCapacity();
    if (!canCreate) {
      return;
    }

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Create failed: ${error.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _joinCircle() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    final canJoin = await _ensureCircleCapacity();
    if (!canJoin) {
      return;
    }

    setState(() => _isJoining = true);
    try {
      await ref.read(circleControllerProvider).joinCircle(code);
      _codeController.clear();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Joined circle.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Join failed: ${error.toString()}')),
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
      builder: (context) {
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
                                  ? member.displayName!.substring(0, 1).toUpperCase()
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
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, _) => ErrorState(message: error.toString()),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _ensureCircleCapacity() async {
    final authState = ref.read(authControllerProvider);
    if (authState.user == null) return false;

    final circles = await ref.read(circlesProvider.future);
    final subscription = await ref.read(subscriptionStateProvider.future);
    if (subscription.canCreateOrJoinCircle(circles.length)) {
      return true;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Upgrade to Premium to manage more than one active circle.')),
    );

    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PaywallScreen()),
      );
    }

    return false;
  }

  void _openCreateDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create Circle'),
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
          title: const Text('Join Circle'),
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
      appBar: AppBar(
        title: const Text('Family Circles'),
        actions: [
          IconButton(onPressed: _openJoinDialog, icon: const Icon(Icons.group_add_outlined)),
          IconButton(onPressed: _openCreateDialog, icon: const Icon(Icons.add_box_outlined)),
        ],
      ),
      body: circles.when(
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(message: 'No circles yet. Create one or join with a code.');
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final circle = items[index];
              return ListTile(
                leading: CircleAvatar(child: Text(circle.name.substring(0, 1).toUpperCase())),
                title: Text(circle.name),
                subtitle: Text('Invite code: ${circle.inviteCode}'),
                onTap: () => _openMembers(circle.id),
                trailing: IconButton(
                  tooltip: 'Refresh invite code',
                  icon: const Icon(Icons.refresh),
                  onPressed: () async {
                    try {
                      await ref
                          .read(circleControllerProvider)
                          .refreshInviteCode(circle.id);
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Invite code regenerated')));
                    } catch (error) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: ${error.toString()}')),
                      );
                    }
                  },
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorState(message: error.toString()),
      ),
    );
  }
}
