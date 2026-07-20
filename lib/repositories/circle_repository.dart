import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_strings.dart';
import '../core/demo/demo_backend.dart';
import '../models/circle.dart';
import '../models/circle_member.dart';

class CircleRepository {
  CircleRepository([this._client]);

  final SupabaseClient? _client;

  Future<String> createCircle({
    required String ownerId,
    required String name,
  }) async {
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.createCircle(ownerId: ownerId, name: name);
    }

    final client = _client!;
    final row = await client
        .from('circles')
        .insert({
          'owner_id': ownerId,
          'name': name,
        })
        .select('id')
        .single();

    return row['id'] as String;
  }

  Future<String> regenerateInviteCode(String circleId) async {
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.rotateInviteCode(circleId);
    }

    final client = _client!;
    final result = await client.rpc('rotate_circle_invite_code', params: {
      'p_circle_id': circleId,
    });

    return result as String;
  }

  Future<String?> getInviteCode(String circleId) async {
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.getInviteCode(circleId);
    }

    final client = _client!;
    final row = await client
        .from('circles')
        .select('invite_code')
        .eq('id', circleId)
        .single();

    return row['invite_code'] as String?;
  }

  Future<List<CircleModel>> getCirclesForUser(String userId) async {
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.getCirclesForUser(userId);
    }

    final client = _client!;
    final rows = await client
        .from('circle_members')
        .select('circles(id,name,owner_id,invite_code,created_at), is_accepted')
        .eq('user_id', userId)
        .eq('is_accepted', true);

    return rows
        .where((row) => row['circles'] is Map<String, dynamic>)
        .map((row) => CircleModel.fromJson(row['circles'] as Map<String, dynamic>))
        .toList();
  }

  Future<bool> currentUserCanShare(String userId) async {
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.currentUserCanShare(userId);
    }

    final client = _client!;
    final rows = await client
        .from('circle_members')
        .select('id')
        .eq('user_id', userId)
        .eq('is_accepted', true)
        .limit(1);

    return rows.isNotEmpty;
  }

  Future<void> joinCircleByInviteCode(String inviteCode) async {
    if (AppConfig.runInDemoMode) {
      final active = DemoBackend.shared.activeUser;
      if (active == null) return;
      await DemoBackend.shared.joinCircleByInviteCode(
        inviteCode: inviteCode,
        userId: active.id,
      );
      return;
    }

    final client = _client!;
    await client.rpc('join_circle_by_invite_code', params: {
      'p_invite_code': inviteCode.trim(),
    });
  }

  Future<List<CircleMember>> getMembersForCircle(String circleId) async {
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.getMembersForCircle(circleId);
    }

    final client = _client!;
    final rows = await client
        .from('circle_members')
        .select('id,circle_id,user_id,role,is_accepted,invited_at,users(display_name,avatar_url,id)')
        .eq('circle_id', circleId);

    return rows.map((row) => CircleMember.fromJson(row)).toList();
  }

  Future<CircleModel> getCircle(String circleId) async {
    if (AppConfig.runInDemoMode) {
      return DemoBackend.shared.getCircle(circleId);
    }

    final client = _client!;
    final row = await client
        .from('circles')
        .select('id,name,owner_id,invite_code,created_at')
        .eq('id', circleId)
        .single();

    return CircleModel.fromJson(row);
  }
}
