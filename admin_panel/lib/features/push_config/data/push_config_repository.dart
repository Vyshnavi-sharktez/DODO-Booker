import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/push_config_status.dart';

class PushConfigRepository {
  final SupabaseClient _supabase;

  const PushConfigRepository(this._supabase);

  Future<bool> fcmVaultSecretIsSet(String name) async {
    final result = await _supabase.rpc('fcm_vault_secret_is_set', params: {
      'p_name': name,
    });
    if (result is bool) return result;
    if (result == null) return false;
    return result.toString().toLowerCase() == 'true';
  }

  // Stores a secret in vault via SECURITY DEFINER RPC — value is never returned.
  Future<void> upsertFcmVaultSecret(String name, String value) async {
    await _supabase.rpc('upsert_fcm_vault_secret', params: {
      'p_name': name,
      'p_value': value,
    });
  }

  Future<List<DeviceTokenCount>> getDeviceCounts() async {
    final data = await _supabase.rpc('get_device_token_counts');
    return (data as List<dynamic>)
        .map((row) => DeviceTokenCount.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<PushConfigStatus> fetchStatus() async {
    final results = await Future.wait([
      fcmVaultSecretIsSet('push_function_secret'),
      fcmVaultSecretIsSet('fcm_service_account_b64'),
      getDeviceCounts(),
    ]);
    return PushConfigStatus(
      pushSecretIsSet: results[0] as bool,
      serviceAccountIsSet: results[1] as bool,
      deviceCounts: results[2] as List<DeviceTokenCount>,
    );
  }

  Future<List<PushTestTarget>> getPushTestTargets(String userType) async {
    final data = await _supabase
        .rpc('get_push_test_targets', params: {'p_user_type': userType});
    return (data as List<dynamic>)
        .map((row) => PushTestTarget.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Returns null if the Edge Function has not yet recorded delivery results.
  Future<({int sent, int failed})?> getPushDeliveryResult(
      String notificationId) async {
    final data = await _supabase.rpc('get_push_delivery_result',
        params: {'p_notification_id': notificationId});
    final rows = data as List<dynamic>;
    if (rows.isEmpty) return null;
    final row = rows.first as Map<String, dynamic>;
    return (
      sent: (row['tokens_sent'] as num?)?.toInt() ?? 0,
      failed: (row['tokens_failed'] as num?)?.toInt() ?? 0,
    );
  }
}
