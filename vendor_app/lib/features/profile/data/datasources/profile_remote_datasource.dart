import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileRemoteDatasource {
  const ProfileRemoteDatasource(this._client);
  final SupabaseClient _client;

  Future<Map<String, dynamic>?> fetchByPhone(String phone) {
    return _client.from('vendors').select().eq('phone', phone).maybeSingle();
  }

  Future<void> updateByPhone({
    required String phone,
    required Map<String, dynamic> fields,
  }) {
    return _client.from('vendors').update(fields).eq('phone', phone);
  }
}
