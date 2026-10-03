import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/availability_block.dart';

class AvailabilityBlockRepository {
  final SupabaseClient _client;
  const AvailabilityBlockRepository(this._client);

  Future<List<AvailabilityBlock>> fetchAll() async {
    final rows = await _client
        .from('availability_blocks')
        .select()
        .order('start_date', ascending: false);
    return (rows as List)
        .map((r) => AvailabilityBlock.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<AvailabilityBlock> create(AvailabilityBlock block) async {
    final row = await _client
        .from('availability_blocks')
        .insert(block.toInsertMap())
        .select()
        .single();
    return AvailabilityBlock.fromMap(row);
  }

  Future<AvailabilityBlock> update(AvailabilityBlock block) async {
    final row = await _client
        .from('availability_blocks')
        .update(block.toUpdateMap())
        .eq('id', block.id)
        .select()
        .single();
    return AvailabilityBlock.fromMap(row);
  }

  Future<void> setEnabled(String id, {required bool enabled}) async {
    await _client.from('availability_blocks').update({
      'is_enabled': enabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> delete(String id) async {
    await _client.from('availability_blocks').delete().eq('id', id);
  }
}
