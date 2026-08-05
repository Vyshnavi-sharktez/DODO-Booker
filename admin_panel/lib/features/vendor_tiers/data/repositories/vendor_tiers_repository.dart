import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/models/vendor_tier.dart';

class VendorTiersRepository {
  final SupabaseClient _client;

  VendorTiersRepository(this._client);

  /// Fetch all vendor tiers sorted by priority order (ascending).
  Future<List<VendorTier>> getVendorTiers() async {
    final response = await _client
        .from('vendor_tiers')
        .select()
        .order('priority', ascending: true)
        .order('created_at', ascending: true);

    final list = (response as List).cast<Map<String, dynamic>>();
    return list.map((json) => VendorTier.fromMap(json)).toList();
  }

  /// Create a new vendor tier.
  Future<VendorTier> createVendorTier(VendorTier tier) async {
    final userId = _client.auth.currentUser?.id;
    final payload = tier.toMap();
    if (userId != null) {
      payload['created_by'] = userId;
      payload['updated_by'] = userId;
    }

    final response = await _client
        .from('vendor_tiers')
        .insert(payload)
        .select()
        .single();

    return VendorTier.fromMap(response);
  }

  /// Update an existing vendor tier.
  Future<VendorTier> updateVendorTier(VendorTier tier) async {
    final userId = _client.auth.currentUser?.id;
    final payload = tier.toMap();
    if (userId != null) {
      payload['updated_by'] = userId;
    }
    payload['updated_at'] = DateTime.now().toIso8601String();

    final response = await _client
        .from('vendor_tiers')
        .update(payload)
        .eq('id', tier.id)
        .select()
        .single();

    return VendorTier.fromMap(response);
  }

  /// Delete a vendor tier by ID.
  Future<void> deleteVendorTier(String id) async {
    await _client.from('vendor_tiers').delete().eq('id', id);
  }

  /// Simple batch update of priority order for reordering.
  Future<void> updateTierPriorities(List<VendorTier> orderedTiers) async {
    final userId = _client.auth.currentUser?.id;
    final nowStr = DateTime.now().toIso8601String();

    for (int i = 0; i < orderedTiers.length; i++) {
      final tier = orderedTiers[i];
      final newPriority = i + 1;

      if (tier.priority != newPriority) {
        final updateData = <String, dynamic>{
          'priority': newPriority,
          'updated_at': nowStr,
        };
        if (userId != null) {
          updateData['updated_by'] = userId;
        }
        await _client.from('vendor_tiers').update(updateData).eq('id', tier.id);
      }
    }
  }

  /// Run batch performance evaluation across all vendors in Supabase
  Future<int> evaluateAllVendors() async {
    final response = await _client.rpc('evaluate_all_vendors_performance');
    return (response as num?)?.toInt() ?? 0;
  }
}
