import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/amc_plan.dart';

class AmcPlansRepository {
  final SupabaseClient _supabase;

  const AmcPlansRepository(this._supabase);

  // ── Plan CRUD ──────────────────────────────────────────────────────────────

  Future<List<AmcPlan>> fetchAll() async {
    final data = await _supabase
        .from('amc_plans')
        .select()
        .order('created_at', ascending: true);
    return (data as List<dynamic>)
        .map((r) => AmcPlan.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<AmcPlan> create({
    required String planName,
    required String packageDuration,
    int? packageDurationValue,
    required String serviceInterval,
    int? serviceIntervalValue,
    required double pricePerVisit,
    required String discountType,
    required double discountValue,
    required bool isActive,
  }) async {
    final data = await _supabase
        .from('amc_plans')
        .insert({
          'plan_name': planName,
          'package_duration': packageDuration,
          if (packageDurationValue != null)
            'package_duration_value': packageDurationValue,
          'service_interval': serviceInterval,
          if (serviceIntervalValue != null)
            'service_interval_value': serviceIntervalValue,
          'price_per_visit': pricePerVisit,
          'discount_type': discountType,
          'discount_value': discountValue,
          'is_active': isActive,
        })
        .select()
        .single();
    return AmcPlan.fromMap(data);
  }

  Future<AmcPlan> update(
    String id, {
    required String planName,
    required String packageDuration,
    int? packageDurationValue,
    required String serviceInterval,
    int? serviceIntervalValue,
    required double pricePerVisit,
    required String discountType,
    required double discountValue,
    required bool isActive,
  }) async {
    final data = await _supabase
        .from('amc_plans')
        .update({
          'plan_name': planName,
          'package_duration': packageDuration,
          'package_duration_value': packageDurationValue,
          'service_interval': serviceInterval,
          'service_interval_value': serviceIntervalValue,
          'price_per_visit': pricePerVisit,
          'discount_type': discountType,
          'discount_value': discountValue,
          'is_active': isActive,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id)
        .select()
        .single();
    return AmcPlan.fromMap(data);
  }

  Future<void> toggleActive(String id, {required bool isActive}) async {
    await _supabase
        .from('amc_plans')
        .update({
          'is_active': isActive,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
  }

  Future<void> delete(String id) async {
    await _supabase.from('amc_plans').delete().eq('id', id);
  }

  // ── Node-plan linking ──────────────────────────────────────────────────────

  /// Returns IDs of all plans currently linked to [nodeId].
  Future<List<String>> fetchLinkedPlanIds(String nodeId) async {
    final data = await _supabase
        .from('catalog_node_amc_plans')
        .select('amc_plan_id')
        .eq('node_id', nodeId)
        .order('sort_order', ascending: true);
    return (data as List<dynamic>)
        .map((r) => (r as Map<String, dynamic>)['amc_plan_id'] as String)
        .toList();
  }

  /// Syncs the linked plan set for [nodeId]: inserts new links, removes
  /// delinked ones. [planIds] is the full desired set after save.
  Future<void> syncNodePlans(String nodeId, List<String> planIds) async {
    final existing = await fetchLinkedPlanIds(nodeId);
    final existingSet = existing.toSet();
    final desiredSet = planIds.toSet();

    final toAdd = desiredSet.difference(existingSet);
    final toRemove = existingSet.difference(desiredSet);

    if (toRemove.isNotEmpty) {
      await _supabase
          .from('catalog_node_amc_plans')
          .delete()
          .eq('node_id', nodeId)
          .inFilter('amc_plan_id', toRemove.toList());
    }

    if (toAdd.isNotEmpty) {
      final rows = toAdd.toList().asMap().entries.map((e) => {
            'node_id': nodeId,
            'amc_plan_id': e.value,
            'sort_order': existing.length + e.key,
          }).toList();
      await _supabase.from('catalog_node_amc_plans').insert(rows);
    }
  }
}
