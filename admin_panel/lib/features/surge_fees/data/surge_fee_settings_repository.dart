import 'package:supabase_flutter/supabase_flutter.dart';

class SurgeFeeConfig {
  final String? id;
  final bool isEnabled;
  final String surgeName;
  final String surgeType; // 'percentage' | 'fixed'
  final double surgeValue;
  final String? description;

  const SurgeFeeConfig({
    this.id,
    required this.isEnabled,
    required this.surgeName,
    required this.surgeType,
    required this.surgeValue,
    this.description,
  });

  factory SurgeFeeConfig.defaults() => const SurgeFeeConfig(
        isEnabled: false,
        surgeName: 'Surge Fee',
        surgeType: 'percentage',
        surgeValue: 0.0,
        description: null,
      );

  factory SurgeFeeConfig.fromMap(Map<String, dynamic> m) => SurgeFeeConfig(
        id: m['id'] as String?,
        isEnabled: (m['is_enabled'] as bool?) ?? false,
        surgeName: (m['surge_name'] as String?) ?? 'Surge Fee',
        surgeType: (m['surge_type'] as String?) ?? 'percentage',
        surgeValue: (m['surge_value'] as num?)?.toDouble() ?? 0.0,
        description: m['description'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'is_enabled': isEnabled,
        'surge_name': surgeName,
        'surge_type': surgeType,
        'surge_value': surgeValue,
        'description': description,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
}

class SurgeFeeSettingsRepository {
  final SupabaseClient _client;
  const SurgeFeeSettingsRepository(this._client);

  Future<SurgeFeeConfig> fetch() async {
    final rows = await _client
        .from('surge_fee_settings')
        .select()
        .order('updated_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return SurgeFeeConfig.defaults();
    return SurgeFeeConfig.fromMap(rows.first);
  }

  Future<SurgeFeeConfig> save(SurgeFeeConfig config) async {
    final payload = config.toMap();

    // Try to UPDATE by the known id and verify via .select() — Supabase SDK v2
    // returns empty when 0 rows match (no exception), so we must check length.
    if (config.id != null) {
      final updated = await _client
          .from('surge_fee_settings')
          .update(payload)
          .eq('id', config.id!)
          .select();
      if (updated.isNotEmpty) return SurgeFeeConfig.fromMap(updated.first);
    }

    // id unknown or UPDATE matched 0 rows: find the actual singleton row.
    final existing = await _client
        .from('surge_fee_settings')
        .select('id')
        .order('updated_at', ascending: false)
        .limit(1);
    if (existing.isNotEmpty) {
      final existingId = existing.first['id'] as String;
      final updated = await _client
          .from('surge_fee_settings')
          .update(payload)
          .eq('id', existingId)
          .select();
      if (updated.isNotEmpty) return SurgeFeeConfig.fromMap(updated.first);
    }

    // Table is truly empty (pre-migration): insert the singleton row.
    final row = await _client
        .from('surge_fee_settings')
        .insert(payload)
        .select()
        .single();
    return SurgeFeeConfig.fromMap(row);
  }
}
