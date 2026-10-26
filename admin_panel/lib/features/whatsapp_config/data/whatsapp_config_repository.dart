import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/whatsapp_provider_config.dart';

class WhatsappConfigRepository {
  final SupabaseClient _supabase;

  const WhatsappConfigRepository(this._supabase);

  Future<List<WhatsappProviderConfig>> fetchAll() async {
    final data = await _supabase
        .from('whatsapp_provider_configs')
        .select()
        .order('created_at');
    return (data as List<dynamic>)
        .map((row) =>
            WhatsappProviderConfig.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveConfig(WhatsappProviderConfig config) async {
    await _supabase
        .from('whatsapp_provider_configs')
        .upsert(config.toJson(), onConflict: 'provider');
  }

  // Saves a secret via SECURITY DEFINER RPC — value is stored in Vault and never returned.
  Future<void> setSecret(
    String provider,
    String secretName,
    String value,
  ) async {
    await _supabase.rpc('upsert_whatsapp_secret', params: {
      'p_provider': provider,
      'p_secret_name': secretName,
      'p_value': value,
    });
  }

  // Returns true if a Vault-encrypted secret exists (does not return the value).
  Future<bool> secretIsSet(String provider, String secretName) async {
    final result = await _supabase.rpc('whatsapp_secret_is_set', params: {
      'p_provider': provider,
      'p_secret_name': secretName,
    });
    if (result is bool) return result;
    if (result == null) return false;
    return result.toString().toLowerCase() == 'true';
  }

  // Invokes the whatsapp-test-message Edge Function.
  // Returns the decoded response body. Throws on network or server error.
  Future<Map<String, dynamic>> sendTestMessage(
    String provider,
    String testPhone,
  ) async {
    final response = await _supabase.functions.invoke(
      'whatsapp-test-message',
      body: {'provider': provider, 'test_phone': testPhone},
    );
    final status = response.status;
    final data = response.data;
    if (status >= 400) {
      final msg = data is Map ? data['error'] as String? : null;
      throw Exception(msg ?? 'Test message failed (HTTP $status)');
    }
    if (data is Map<String, dynamic>) return data;
    return {'success': false, 'error': 'Unexpected response'};
  }
}
