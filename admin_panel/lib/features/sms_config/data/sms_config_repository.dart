import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/sms_provider_config.dart';

class SmsConfigRepository {
  final SupabaseClient _supabase;

  const SmsConfigRepository(this._supabase);

  Future<List<SmsProviderConfig>> fetchAll() async {
    final data = await _supabase
        .from('sms_provider_configs')
        .select()
        .order('created_at');
    return (data as List<dynamic>)
        .map((row) => SmsProviderConfig.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveConfig(SmsProviderConfig config) async {
    await _supabase
        .from('sms_provider_configs')
        .upsert(config.toJson(), onConflict: 'provider');
  }

  Future<void> setSecret(
    String provider,
    String secretName,
    String value,
  ) async {
    await _supabase.rpc('upsert_sms_secret', params: {
      'p_provider': provider,
      'p_secret_name': secretName,
      'p_value': value,
    });
  }

  Future<bool> secretIsSet(String provider, String secretName) async {
    final result = await _supabase.rpc('sms_secret_is_set', params: {
      'p_provider': provider,
      'p_secret_name': secretName,
    });
    if (result is bool) return result;
    if (result == null) return false;
    return result.toString().toLowerCase() == 'true';
  }

  Future<Map<String, dynamic>> sendTestMessage(
    String provider,
    String testPhone, {
    bool mock = false,
    String mockOutcome = 'success',
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'sms-test-message',
        body: {
          'provider': provider,
          'test_phone': testPhone,
          if (mock) 'mock': true,
          if (mock) 'mock_outcome': mockOutcome,
        },
      );
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      return {'success': false, 'error': 'Unexpected response'};
    } on FunctionException catch (e) {
      // functions_client throws FunctionException for all non-2xx responses;
      // FunctionResponse is only returned for 2xx. For JSON bodies (simulated
      // failures, real provider errors) details is the already-decoded Map —
      // return it so the caller can inspect success/simulated flags normally.
      final details = e.details;
      if (details is Map) return Map<String, dynamic>.from(details);
      throw Exception(details?.toString() ?? 'Test message failed (HTTP ${e.status})');
    }
  }
}
