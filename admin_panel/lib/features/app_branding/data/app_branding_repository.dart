import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models/app_branding_model.dart';

class AppBrandingRepository {
  const AppBrandingRepository(this._supabase);

  final SupabaseClient _supabase;

  static const _bucket = 'app-branding';

  static const _mimeMap = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
  };

  Future<List<AppBrandingModel>> loadAll() async {
    final data = await _supabase
        .from('app_branding')
        .select()
        .order('app_id');
    return (data as List<dynamic>)
        .map((m) => AppBrandingModel.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  /// Uploads [bytes] to the `app-branding` bucket and returns the public URL.
  /// Validates mime type before uploading.
  Future<String> uploadIcon({
    required String appId,
    required Uint8List bytes,
    required String extension,
  }) async {
    final ext = extension.toLowerCase();
    final mime = _mimeMap[ext];
    if (mime == null) {
      throw Exception(
        'Unsupported format "$ext". Use PNG, JPG, or WEBP.',
      );
    }
    final path = '$appId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _supabase.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: true),
        );
    return _supabase.storage.from(_bucket).getPublicUrl(path);
  }

  /// Persists [iconUrl] (or clears it when null) for the given [appId].
  Future<void> saveIconUrl(String appId, String? iconUrl) async {
    await _supabase
        .from('app_branding')
        .update({'icon_url': iconUrl})
        .eq('app_id', appId);
  }
}
