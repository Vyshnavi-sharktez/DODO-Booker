import 'package:supabase_flutter/supabase_flutter.dart';

class SettingsRepository {
  final SupabaseClient _supabase;

  const SettingsRepository(this._supabase);

  Future<Map<String, String>> fetchAll() async {
    final data = await _supabase
        .from('settings')
        .select('setting_key, setting_value');
    return {
      for (final row in data as List<dynamic>)
        (row as Map<String, dynamic>)['setting_key'] as String:
            (row['setting_value'] as String?) ?? '',
    };
  }

  Future<void> upsertMany(Map<String, String> keyValues) async {
    if (keyValues.isEmpty) return;
    final rows = keyValues.entries
        .map(
          (e) => {
            'setting_key': e.key,
            'setting_value': e.value,
          },
        )
        .toList();
    await _supabase.from('settings').upsert(rows, onConflict: 'setting_key');
  }
}
