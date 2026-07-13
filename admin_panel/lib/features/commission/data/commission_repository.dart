import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/commission_rule.dart';

class CommissionRepository {
  final SupabaseClient _supabase;
  const CommissionRepository(this._supabase);

  Future<CommissionRule?> fetchGlobal() async {
    final data = await _supabase
        .from('commission_rules')
        .select()
        .eq('rule_type', 'global')
        .maybeSingle();
    return data == null ? null : CommissionRule.fromMap(data);
  }

  Future<CommissionRule?> fetchForCategory(String categoryId) async {
    final data = await _supabase
        .from('commission_rules')
        .select()
        .eq('rule_type', 'category')
        .eq('target_id', categoryId)
        .maybeSingle();
    return data == null ? null : CommissionRule.fromMap(data);
  }

  Future<CommissionRule?> fetchForVendor(String vendorId) async {
    final data = await _supabase
        .from('commission_rules')
        .select()
        .eq('rule_type', 'vendor')
        .eq('target_id', vendorId)
        .maybeSingle();
    return data == null ? null : CommissionRule.fromMap(data);
  }

  /// Resolves commission for a vendor booking: vendor > category > global.
  Future<CommissionRule?> resolve({String? vendorId, String? categoryId}) async {
    if (vendorId != null && vendorId.isNotEmpty) {
      final vendorRule = await fetchForVendor(vendorId);
      if (vendorRule != null) return vendorRule;
    }
    if (categoryId != null && categoryId.isNotEmpty) {
      final categoryRule = await fetchForCategory(categoryId);
      if (categoryRule != null) return categoryRule;
    }
    return fetchGlobal();
  }

  /// Resolves commission for settlement: vendor > vendor's category > global.
  /// Fetches the vendor's primary category_id automatically so the caller
  /// doesn't need to supply it (settlement context has no category in scope).
  Future<CommissionRule?> resolveForSettlement(String vendorId) async {
    if (vendorId.isEmpty) return fetchGlobal();

    final vendorRule = await fetchForVendor(vendorId);
    if (vendorRule != null) {
      debugPrint('[Commission] resolveForSettlement: vendor-specific rule found — '
          'type=${vendorRule.commissionType} value=${vendorRule.commissionValue} '
          'enabled=${vendorRule.isEnabled}');
      return vendorRule;
    }
    debugPrint('[Commission] resolveForSettlement: no vendor rule for $vendorId');

    // Look up the vendor's primary category to apply category-level commission.
    String? categoryId;
    try {
      final row = await _supabase
          .from('vendors')
          .select('category_id')
          .eq('id', vendorId)
          .maybeSingle();
      categoryId = row?['category_id'] as String?;
      debugPrint('[Commission] resolveForSettlement: vendor category_id=$categoryId');
    } catch (e) {
      debugPrint('[Commission] resolveForSettlement: category_id lookup failed — $e');
    }

    if (categoryId != null && categoryId.isNotEmpty) {
      final categoryRule = await fetchForCategory(categoryId);
      if (categoryRule != null) {
        debugPrint('[Commission] resolveForSettlement: category rule found — '
            'type=${categoryRule.commissionType} value=${categoryRule.commissionValue} '
            'enabled=${categoryRule.isEnabled}');
        return categoryRule;
      }
      debugPrint('[Commission] resolveForSettlement: no category rule for $categoryId');
    }

    final globalRule = await fetchGlobal();
    debugPrint('[Commission] resolveForSettlement: global rule = '
        '${globalRule == null ? "null" : "type=${globalRule.commissionType} value=${globalRule.commissionValue} enabled=${globalRule.isEnabled}"}');
    return globalRule;
  }

  Future<CommissionRule> upsertRule({
    required String ruleType,
    String? targetId,
    required String commissionType,
    required double commissionValue,
    bool isEnabled = true,
    String? notes,
  }) async {
    final existing = switch (ruleType) {
      'global' => await fetchGlobal(),
      'category' => targetId != null ? await fetchForCategory(targetId) : null,
      _ => targetId != null ? await fetchForVendor(targetId) : null,
    };

    if (existing != null) {
      final data = await _supabase
          .from('commission_rules')
          .update({
            'commission_type': commissionType,
            'commission_value': commissionValue,
            'is_enabled': isEnabled,
            'notes': notes,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', existing.id)
          .select()
          .single();
      return CommissionRule.fromMap(data);
    } else {
      final data = await _supabase
          .from('commission_rules')
          .insert({
            'rule_type': ruleType,
            'target_id': targetId,
            'commission_type': commissionType,
            'commission_value': commissionValue,
            'is_enabled': isEnabled,
            'notes': notes,
          })
          .select()
          .single();
      return CommissionRule.fromMap(data);
    }
  }

  Future<void> deleteForTarget(String targetId) async {
    await _supabase
        .from('commission_rules')
        .delete()
        .eq('target_id', targetId);
  }
}
