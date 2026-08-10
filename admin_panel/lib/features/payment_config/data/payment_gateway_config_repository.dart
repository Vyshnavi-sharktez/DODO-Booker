import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/payment_gateway_config.dart';

class PaymentGatewayConfigRepository {
  final SupabaseClient _supabase;

  const PaymentGatewayConfigRepository(this._supabase);

  Future<List<PaymentGatewayConfig>> fetchAll() async {
    final data = await _supabase
        .from('payment_gateway_configs')
        .select()
        .order('created_at');
    return (data as List<dynamic>)
        .map((row) =>
            PaymentGatewayConfig.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveConfig(PaymentGatewayConfig config) async {
    await _supabase
        .from('payment_gateway_configs')
        .upsert(config.toJson(), onConflict: 'gateway');
  }

  // Saves a secret via SECURITY DEFINER RPC — value is never returned.
  Future<void> setSecret(
    String gateway,
    String secretName,
    String value,
  ) async {
    await _supabase.rpc('upsert_gateway_secret', params: {
      'p_gateway': gateway,
      'p_secret_name': secretName,
      'p_value': value,
    });
  }

  // Returns true if a vault-encrypted secret exists (does not return the value).
  Future<bool> secretIsSet(String gateway, String secretName) async {
    final result = await _supabase.rpc('gateway_secret_is_set', params: {
      'p_gateway': gateway,
      'p_secret_name': secretName,
    });
    if (result is bool) return result;
    if (result == null) return false;
    return result.toString().toLowerCase() == 'true';
  }
}
