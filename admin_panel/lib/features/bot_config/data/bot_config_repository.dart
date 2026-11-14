import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/bot_config.dart';

class BotConfigRepository {
  final SupabaseClient _supabase;

  const BotConfigRepository(this._supabase);

  Future<BotConfig?> fetchConfig() async {
    final data = await _supabase
        .from('bot_configs')
        .select()
        .limit(1)
        .maybeSingle();
    if (data == null) return null;
    return BotConfig.fromJson(data);
  }

  Future<void> saveConfig(BotConfig config) async {
    await _supabase
        .from('bot_configs')
        .update(config.toJson())
        .eq('id', config.id);
  }

  Future<void> setSecret(String secretName, String value) async {
    await _supabase.rpc('upsert_bot_secret', params: {
      'p_secret_name': secretName,
      'p_value': value,
    });
  }

  Future<bool> secretIsSet(String secretName) async {
    final result = await _supabase.rpc('bot_secret_is_set', params: {
      'p_secret_name': secretName,
    });
    if (result is bool) return result;
    if (result == null) return false;
    return result.toString().toLowerCase() == 'true';
  }

  Future<String> fetchAnonKey() async {
    final data = await _supabase
        .from('settings')
        .select('setting_value')
        .eq('setting_key', 'supabase_anon_key')
        .maybeSingle();
    return (data?['setting_value'] as String?) ?? '';
  }

  Future<void> saveAnonKey(String value) async {
    await _supabase
        .from('settings')
        .update({'setting_value': value})
        .eq('setting_key', 'supabase_anon_key');
  }
}
