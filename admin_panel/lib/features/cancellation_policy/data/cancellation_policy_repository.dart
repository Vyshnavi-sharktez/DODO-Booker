import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/cancellation_policy.dart';

class CancellationPolicyRepository {
  final SupabaseClient _client;
  const CancellationPolicyRepository(this._client);

  Future<List<CancellationPolicy>> fetchPolicies() async {
    final result = await _client.rpc('admin_get_cancellation_policies');
    final list = result as List? ?? [];
    return list
        .map((e) => CancellationPolicy.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> togglePolicy(String policyId, {required bool isEnabled}) async {
    await _client.rpc('admin_toggle_cancellation_policy', params: {
      'p_policy_id': policyId,
      'p_is_enabled': isEnabled,
    });
  }

  Future<String> upsertSlab({
    required String policyId,
    String? id,
    required int fromMinutes,
    int? toMinutes,
    required double feeAmount,
    String? label,
    int sortOrder = 0,
  }) async {
    final result = await _client.rpc('admin_upsert_cancellation_slab', params: {
      'p_policy_id':    policyId,
      'p_id':           id,
      'p_from_minutes': fromMinutes,
      'p_to_minutes':   toMinutes,
      'p_fee_amount':   feeAmount,
      'p_label':        label,
      'p_sort_order':   sortOrder,
    });
    return result as String;
  }

  Future<void> deleteSlab(String slabId) async {
    await _client.rpc('admin_delete_cancellation_slab', params: {
      'p_slab_id': slabId,
    });
  }
}
