import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/empty_states.dart';
import '../../../features/circles/models/circle.dart';
import '../../../features/circles/models/circle_member.dart';
import '../../../features/circles/providers/circle_providers.dart';
import '../../../features/map/providers/map_provider.dart';
import '../../../models/safe_zone.dart';
import '../../paywall/ui/paywall_screen.dart';
import '../../subscription/providers/subscription_provider.dart';
import '../providers/safe_zone_provider.dart';

class SafeZonesScreen extends ConsumerStatefulWidget {
  const SafeZonesScreen({super.key});

  @override
  ConsumerState<SafeZonesScreen> createState() => _SafeZonesScreenState();
}

class _SafeZonesScreenState extends ConsumerState<SafeZonesScreen> {
  bool _isBusy = false;

  @override
  Widget build(BuildContext context) {
    final circlesState = ref.watch(circlesProvider);
    final activeCircleId = ref.watch(activeMapCircleIdProvider);
    final subscriptionState = ref.watch(subscriptionStateProvider);

    return subscriptionState.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Safe Zones')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Safe Zones')),
        body: ErrorState(message: error.toString()),
      ),
      data: (subscription) {
        final canUseSafeZones = subscription.canUseSafeZoneFeature();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Safe Zones'),
            actions: [
              IconButton(
                onPressed: _isBusy || !canUseSafeZones ? null : () => _openCreateZone(),
                icon: const Icon(Icons.add_location_alt),
                tooltip: canUseSafeZones ? 'Create safe zone' : 'Premium only',
              ),
            ],
          ),
          body: circlesState.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => ErrorState(message: error.toString()),
            data: (circles) {
              if (circles.isEmpty) {
                return const EmptyState(message: 'Create or join a circle first to manage safe zones.');
              }
              final activeCircle = circles.firstWhere(
                (circle) => circle.id == activeCircleId,
                orElse: () => circles.first,
              );
              final zonesState = ref.watch(safeZonesForActiveCircleProvider);
              final membersState = ref.watch(circleMembersProvider(activeCircle.id));

              return zonesState.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => ErrorState(message: error.toString()),
                data: (zones) {
                  return membersState.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (error, _) => ErrorState(message: error.toString()),
                    data: (members) => _ZoneContent(
                      activeCircle: activeCircle,
                      circles: circles,
                      zones: zones,
                      members: members,
                      isBusy: _isBusy,
                      canUseSafeZones: canUseSafeZones,
                      onPickCircle: (value) {
                        if (value == null) return;
                        ref.read(circleControllerProvider).openCircle(value);
                      },
                      onCreate: canUseSafeZones
                          ? () => _openCreateZone(preselectedMembers: members)
                          : () => _showPremium(context),
                      onEdit: canUseSafeZones
                          ? (zone) => _openEditZone(zone, members: members)
                          : (zone) => _showPremium(context),
                      onDelete: canUseSafeZones
                          ? (zone) => _deleteZone(zone)
                          : (zone) => _showPremium(context),
                      onRefresh: () => ref.invalidate(safeZonesForActiveCircleProvider),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  void _showPremium(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PaywallScreen()));
  }

  Future<void> _openCreateZone({List<CircleMember> preselectedMembers = const []}) async {
    final activeCircleId = ref.read(activeMapCircleIdProvider);
    if (activeCircleId == null) {
      _showSnack('Join a circle before creating zones.');
      return;
    }

    final members = preselectedMembers.isNotEmpty
        ? preselectedMembers
        : (await _loadMembers(activeCircleId));

    if (!mounted) return;
    await _showZoneDialog(isEditing: false, members: members);
  }

  Future<void> _openEditZone(SafeZone zone, {required List<CircleMember> members}) async {
    await _showZoneDialog(isEditing: true, zone: zone, members: members);
  }

  Future<List<CircleMember>> _loadMembers(String circleId) async {
    final row = await ref.read(circleMembersProvider(circleId).future);
    if (!mounted) return const <CircleMember>[];
    return row;
  }

  Future<void> _deleteZone(SafeZone zone) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete safe zone'),
          content: Text('Delete "${zone.name}" and remove all history for it?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() => _isBusy = true);
    try {
      await ref.read(safeZoneControllerProvider).deleteZone(zone.id);
      _showSnack('Safe zone deleted');
    } catch (error) {
      _showSnack('Delete failed: ${error.toString()}');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _showZoneDialog({
    required bool isEditing,
    SafeZone? zone,
    required List<CircleMember> members,
  }) async {
    final controller = _ZoneFormController(
      ref: ref,
      zone: zone,
      members: members,
      onBusyChanged: (value) => setState(() => _isBusy = value),
    );

    await controller.show(
      context: context,
      title: isEditing ? 'Edit safe zone' : 'Create safe zone',
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ZoneContent extends StatelessWidget {
  const _ZoneContent({
    required this.activeCircle,
    required this.circles,
    required this.zones,
    required this.members,
    required this.isBusy,
    required this.canUseSafeZones,
    required this.onPickCircle,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
    required this.onRefresh,
  });

  final CircleModel activeCircle;
  final List<CircleModel> circles;
  final List<SafeZone> zones;
  final List<CircleMember> members;
  final bool isBusy;
  final bool canUseSafeZones;
  final ValueChanged<String?> onPickCircle;
  final VoidCallback onCreate;
  final ValueChanged<SafeZone> onEdit;
  final ValueChanged<SafeZone> onDelete;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        onRefresh();
        await Future.delayed(const Duration(milliseconds: 300));
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: activeCircle.id,
            decoration: const InputDecoration(labelText: 'Active circle'),
            items: circles
                .map((circle) => DropdownMenuItem<String>(
                      value: circle.id,
                      child: Text(circle.name),
                    ))
                .toList(growable: false),
            onChanged: onPickCircle,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: isBusy ? null : onCreate,
            icon: const Icon(Icons.add),
            label: const Text('Add safe zone'),
          ),
          const SizedBox(height: 16),
          if (zones.isEmpty)
            const EmptyState(message: 'No safe zones for this circle. Create one for home/school/work alerts.')
          else
            ...zones.map(
              (zone) => Card(
                child: ListTile(
                  title: Text(zone.name),
                  subtitle: Text(_zoneSubtitle(zone, members)),
                  trailing: canUseSafeZones
                      ? PopupMenuButton<int>(
                          onSelected: (value) async {
                            if (value == 1) {
                              onEdit(zone);
                            } else if (value == 2) {
                              onDelete(zone);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 1, child: Text('Edit')),
                            PopupMenuItem(value: 2, child: Text('Delete')),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _zoneSubtitle(SafeZone zone, List<CircleMember> members) {
    final assignment = zone.targetUserId == null
        ? 'All members'
        : (() {
            final member = members.firstWhere(
              (item) => item.userId == zone.targetUserId,
              orElse: () => const CircleMember(
                id: '',
                circleId: '',
                userId: '',
                role: '',
                isAccepted: false,
                invitedAt: null,
              ),
            );
            if (member.userId.isEmpty) return 'Unassigned member';
            return member.displayName?.trim().isNotEmpty == true
                ? member.displayName!.trim()
                : member.userId.substring(0, member.userId.length > 6 ? 6 : member.userId.length);
          })();

    return '${zone.radiusMeters}m · $assignment';
  }
}

class _ZoneFormController {
  _ZoneFormController({
    required this.ref,
    required this.zone,
    required this.members,
    required this.onBusyChanged,
  });

  final WidgetRef ref;
  final SafeZone? zone;
  final List<CircleMember> members;
  final ValueChanged<bool> onBusyChanged;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _radiusController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  String? _targetUserId;

  Future<void> show({
    required BuildContext context,
    required String title,
  }) async {
    _nameController.text = zone?.name ?? '';
    _radiusController.text = zone == null ? '150' : zone!.radiusMeters.toString();
    _latitudeController.text = zone == null ? '' : zone!.centerLatitude.toStringAsFixed(6);
    _longitudeController.text = zone == null ? '' : zone!.centerLongitude.toStringAsFixed(6);
    _targetUserId = zone?.targetUserId;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Form(
            key: _formKey,
            child: StatefulBuilder(
              builder: (context, setState) {
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(labelText: 'Zone name'),
                        validator: (value) {
                          final name = value?.trim() ?? '';
                          if (name.isEmpty) {
                            return 'Name is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _radiusController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: false),
                        decoration: const InputDecoration(labelText: 'Radius in meters'),
                        validator: (value) {
                          final valueText = value?.trim() ?? '';
                          final radius = int.tryParse(valueText);
                          if (radius == null || radius <= 0) {
                            return 'Radius must be greater than 0';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _latitudeController,
                        keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                        decoration: const InputDecoration(labelText: 'Center latitude'),
                        validator: (value) {
                          final latitude = double.tryParse((value ?? '').trim());
                          if (latitude == null || latitude < -90 || latitude > 90) {
                            return 'Latitude must be -90 to 90';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _longitudeController,
                        keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                        decoration: const InputDecoration(labelText: 'Center longitude'),
                        validator: (value) {
                          final longitude = double.tryParse((value ?? '').trim());
                          if (longitude == null || longitude < -180 || longitude > 180) {
                            return 'Longitude must be -180 to 180';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        value: _targetUserId,
                        decoration: const InputDecoration(labelText: 'Member assignment'),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All members'),
                          ),
                          ...members.map(
                            (member) => DropdownMenuItem<String?>(
                              value: member.userId,
                              child: Text(
                                member.displayName?.trim().isNotEmpty == true
                                    ? member.displayName!.trim()
                                    : member.userId.substring(
                                        0,
                                        member.userId.length > 6 ? 6 : member.userId.length,
                                      ),
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _targetUserId = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () async {
                            final position = await ref.read(currentPositionProvider.future);
                            _latitudeController.text = position.latitude.toStringAsFixed(6);
                            _longitudeController.text = position.longitude.toStringAsFixed(6);
                          },
                          icon: const Icon(Icons.my_location),
                          label: const Text('Use current location'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => _submit(context),
              child: Text(zone == null ? 'Create' : 'Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _submit(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final radius = int.parse(_radiusController.text.trim());
    final latitude = double.parse(_latitudeController.text.trim());
    final longitude = double.parse(_longitudeController.text.trim());

    onBusyChanged(true);
    try {
      if (zone == null) {
        await ref.read(safeZoneControllerProvider).createZone(
          name: name,
          centerLatitude: latitude,
          centerLongitude: longitude,
          radiusMeters: radius,
          targetUserId: _targetUserId,
        );
      } else {
        final clearTargetUser = _targetUserId == null;
        await ref.read(safeZoneControllerProvider).updateZone(
          zoneId: zone!.id,
          name: name,
          centerLatitude: latitude,
          centerLongitude: longitude,
          radiusMeters: radius,
          targetUserId: _targetUserId,
          clearTargetUser: clearTargetUser,
        );
      }

      if (!context.mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: ${error.toString()}')));
    } finally {
      onBusyChanged(false);
    }
  }
}
