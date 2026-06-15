import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileRemoteDatasource {
  const ProfileRemoteDatasource(this._client);
  final SupabaseClient _client;

  static const _bucket = 'avatars';

  Future<Map<String, dynamic>?> fetchByPhone(String phone) async {
    debugPrint('[PROFILE] fetchByPhone — value   : "$phone"');
    debugPrint('[PROFILE] fetchByPhone — length  : ${phone.length}');
    debugPrint('[PROFILE] fetchByPhone — codeUnits: ${phone.codeUnits}');
    try {
      final rows = await _client
          .from('vendors')
          .select()
          .eq('phone', phone)
          .limit(1);
      debugPrint('[PROFILE] fetchByPhone — rowCount : ${rows.length}');
      if (rows.isEmpty) {
        debugPrint('[PROFILE] fetchByPhone — result  : NULL (no match)');
        return null;
      }
      debugPrint('[PROFILE] fetchByPhone — result  : FOUND id=${rows.first['id']}');
      return rows.first;
    } catch (e) {
      debugPrint('[PROFILE] fetchByPhone — EXCEPTION: $e');
      rethrow;
    }
  }

  Future<void> updateByPhone({
    required String phone,
    required Map<String, dynamic> fields,
  }) {
    return _client.from('vendors').update(fields).eq('phone', phone);
  }

  Future<void> updateById({
    required String id,
    required Map<String, dynamic> fields,
  }) {
    return _client.from('vendors').update(fields).eq('id', id);
  }

  /// Uploads bytes to Storage and returns the cache-busted public URL.
  Future<String> uploadPhoto({
    required String vendorId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final path = 'vendors/$vendorId/avatar';
    await _client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    final rawUrl = _client.storage.from(_bucket).getPublicUrl(path);
    final cacheBust = DateTime.now().millisecondsSinceEpoch;
    return '$rawUrl?v=$cacheBust';
  }
}
