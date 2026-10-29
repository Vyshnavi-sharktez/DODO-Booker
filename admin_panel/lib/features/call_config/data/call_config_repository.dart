import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/call_provider_config.dart';

class CallConfigRepository {
  final SupabaseClient _client;

  CallConfigRepository(this._client);

  Future<CallProviderConfig> fetchConfig() async {
    final row = await _client
        .from('call_provider_configs')
        .select('*')
        .eq('provider', 'exotel')
        .single();
    return CallProviderConfig.fromMap(row);
  }

  Future<void> saveConfig({
    required bool isEnabled,
    required String? accountSid,
    required String? exophone,
    required bool recordCalls,
    required int callTimeoutSeconds,
  }) async {
    await _client
        .from('call_provider_configs')
        .upsert({
          'provider': 'exotel',
          'is_enabled': isEnabled,
          'account_sid': accountSid?.trim().isEmpty == true ? null : accountSid?.trim(),
          'exophone': exophone?.trim().isEmpty == true ? null : exophone?.trim(),
          'record_calls': recordCalls,
          'call_timeout_seconds': callTimeoutSeconds,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'provider');
  }

  Future<void> saveSecret({
    required String secretName,
    required String value,
  }) async {
    await _client.rpc('upsert_call_secret', params: {
      'p_provider': 'exotel',
      'p_secret_name': secretName,
      'p_value': value,
    });
  }

  Future<bool> secretIsSet(String secretName) async {
    try {
      final result = await _client.rpc('call_secret_is_set', params: {
        'p_provider': 'exotel',
        'p_secret_name': secretName,
      });
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('[CallConfigRepository] secretIsSet error: $e');
      return false;
    }
  }
}
