import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_strings.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/circles/models/circle_member.dart';
import '../../../features/map/providers/map_provider.dart';
import '../../../repositories/location_repository.dart';
import '../../../models/location_update.dart';
import '../../../features/settings/providers/settings_provider.dart';

final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  final client = AppConfig.runInDemoMode ? null : Supabase.instance.client;
  return LocationRepository(client);
});

enum HistoryRangeOption {
  today,
  yesterday,
  last24Hours,
}

extension HistoryRangeLabel on HistoryRangeOption {
  String get label {
    switch (this) {
      case HistoryRangeOption.today:
        return 'Today';
      case HistoryRangeOption.yesterday:
        return 'Yesterday';
      case HistoryRangeOption.last24Hours:
        return 'Last 24 hours';
    }
  }
}

class _HistoryWindow {
  const _HistoryWindow(this.from, this.to);

  final DateTime from;
  final DateTime to;
}

_HistoryWindow _historyWindow(HistoryRangeOption option, int retentionHours) {
  final nowLocal = DateTime.now();
  final retentionStart = nowLocal.subtract(Duration(hours: retentionHours));
  late DateTime from;
  late DateTime to;

  switch (option) {
    case HistoryRangeOption.today:
      from = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
      to = nowLocal;
      break;
    case HistoryRangeOption.yesterday:
      to = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
      from = to.subtract(const Duration(days: 1));
      break;
    case HistoryRangeOption.last24Hours:
      to = nowLocal;
      from = nowLocal.subtract(const Duration(hours: 24));
      break;
  }

  if (from.isBefore(retentionStart)) {
    from = retentionStart;
  }

  if (from.isAfter(to)) {
    return _HistoryWindow(to, to);
  }

  return _HistoryWindow(from, to);
}

final historyMembersProvider = FutureProvider.autoDispose<List<CircleMember>>((ref) async {
  final activeMembers = ref.watch(activeMapMembersProvider);
  return activeMembers.when(
    data: (members) => members,
    loading: () => const <CircleMember>[],
    error: (_, __) => const <CircleMember>[],
  );
});

final historyRangeProvider = StateProvider.autoDispose<HistoryRangeOption>((_) => HistoryRangeOption.last24Hours);

final selectedHistoryMemberProvider = StateProvider.autoDispose<String?>((ref) => null);

void setHistoryRange(WidgetRef ref, HistoryRangeOption range) {
  ref.read(historyRangeProvider.notifier).state = range;
}

void setHistoryMemberId(WidgetRef ref, String memberId) {
  ref.read(selectedHistoryMemberProvider.notifier).state = memberId;
}

final historyProvider = FutureProvider.autoDispose<List<LocationUpdate>>((ref) async {
  final viewer = ref.watch(authControllerProvider).user;
  final memberId = ref.watch(selectedHistoryMemberProvider);
  if (viewer == null || memberId == null || memberId.isEmpty) {
    return const <LocationUpdate>[];
  }

  final members = await ref.watch(historyMembersProvider.future);
  final hasAccess = members.any((member) => member.userId == memberId);
  if (!hasAccess) {
    return const <LocationUpdate>[];
  }

  final range = ref.watch(historyRangeProvider);
  final settings = await ref.watch(mapLocationSettingsProvider.future);
  final window = _historyWindow(range, settings.historyRetentionHours);

  if (window.from == window.to) {
    return const <LocationUpdate>[];
  }

  final repository = ref.watch(locationRepositoryProvider);
  return repository.fetchHistoryForMember(
    userId: memberId,
    from: window.from,
    to: window.to,
    limit: 500,
  );
});
