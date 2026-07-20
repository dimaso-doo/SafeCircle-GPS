import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/empty_states.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/circles/models/circle_member.dart';
import '../providers/history_provider.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  @override
  Widget build(BuildContext context) {
    final membersState = ref.watch(historyMembersProvider);
    final authUserId = ref.watch(authControllerProvider).user?.id;
    final selectedMemberId = ref.watch(selectedHistoryMemberProvider);
    final selectedRange = ref.watch(historyRangeProvider);
    final history = ref.watch(historyProvider);

    if (membersState is AsyncLoading) {
      return const Scaffold(
        appBar: AppBar(title: Text('Location History')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (membersState.hasError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Location History')),
        body: ErrorState(message: membersState.error.toString()),
      );
    }

    final members = membersState.valueOrNull ?? const <CircleMember>[];
    if (members.isEmpty) {
      return const Scaffold(
        appBar: AppBar(title: Text('Location History')),
        body: EmptyState(message: 'Join a circle to view member history.'),
      );
    }

    final memberOptions = _memberItems(members);
    final defaultMember = _initialMember(members, authUserId);

    if (selectedMemberId == null || memberOptions.every((item) => item.value != selectedMemberId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setHistoryMemberId(ref, defaultMember.userId);
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Location History')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: _filtersSection(
              context,
              selectedMemberId ?? defaultMember.userId,
              selectedRange,
              memberOptions,
            ),
          ),
          Expanded(
            child: history.when(
              data: (items) {
                if (items.isEmpty) {
                  return const EmptyState(message: 'No location points available for this period.');
                }

                final ordered = [...items]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
                final markers = <Marker>{
                  for (final point in ordered)
                    Marker(
                      markerId: MarkerId(point.id),
                      position: LatLng(point.latitude, point.longitude),
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                    ),
                };

                final polyline = <Polyline>{
                  Polyline(
                    polylineId: const PolylineId('history_path'),
                    color: Theme.of(context).colorScheme.primary,
                    width: 4,
                    points: ordered.map((item) => LatLng(item.latitude, item.longitude)).toList(),
                  ),
                };

                final center = ordered.isNotEmpty ? ordered.last : null;
                if (center == null) {
                  return const EmptyState(message: 'No location points to render.');
                }

                return Column(
                  children: [
                    SizedBox(
                      height: 280,
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: LatLng(center.latitude, center.longitude),
                          zoom: 14,
                        ),
                        markers: markers,
                        polylines: polyline,
                        myLocationEnabled: false,
                        myLocationButtonEnabled: false,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.separated(
                        itemCount: ordered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final entry = ordered[index];
                          return ListTile(
                            title: Text(
                              '${entry.latitude.toStringAsFixed(5)}, ${entry.longitude.toStringAsFixed(5)}',
                            ),
                            subtitle: Text(
                              DateFormat('yyyy-MM-dd HH:mm:ss').format(entry.createdAt.toLocal()),
                            ),
                            trailing: entry.accuracy != null
                                ? Text('± ${entry.accuracy!.toStringAsFixed(1)}m')
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => ErrorState(message: error.toString()),
            ),
          ),
        ],
      ),
    );
  }

  List<DropdownMenuItem<String>> _memberItems(List<CircleMember> members) {
    return members.map((member) {
      final name = member.displayName?.trim().isNotEmpty == true
          ? member.displayName!.trim()
          : 'Member ${member.userId.substring(0, member.userId.length > 6 ? 6 : member.userId.length)}';
      return DropdownMenuItem(value: member.userId, child: Text(name));
    }).toList(growable: false);
  }

  CircleMember _initialMember(List<CircleMember> members, String? authUserId) {
    if (authUserId != null) {
      for (final member in members) {
        if (member.userId == authUserId) {
          return member;
        }
      }
    }

    return members.first;
  }

  Widget _filtersSection(
    BuildContext context,
    String selectedMember,
    HistoryRangeOption selectedRange,
    List<DropdownMenuItem<String>> memberOptions,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: selectedMember,
          decoration: const InputDecoration(labelText: 'Member'),
          items: memberOptions,
          onChanged: (value) {
            if (value == null) return;
            setHistoryMemberId(ref, value);
          },
        ),
        const SizedBox(height: 12),
        SegmentedButton<HistoryRangeOption>(
          segments: HistoryRangeOption.values
              .map(
                (option) => ButtonSegment<HistoryRangeOption>(
                  value: option,
                  label: Text(option.label),
                ),
              )
              .toList(growable: false),
          selected: {selectedRange},
          onSelectionChanged: (selection) {
            if (selection.isEmpty) return;
            setHistoryRange(ref, selection.first);
          },
        ),
      ],
    );
  }
}
