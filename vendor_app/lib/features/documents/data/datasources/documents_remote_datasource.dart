import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

class DocumentsRemoteDatasource {
  const DocumentsRemoteDatasource(this._client);
  final SupabaseClient _client;

  static const _bucket = 'vendor-documents';

  Future<List<Map<String, dynamic>>> fetchDocuments(String vendorId) async {
    final result = await _client
        .from('vendor_documents')
        .select()
        .eq('vendor_id', vendorId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(result as List);
  }

  /// Uploads bytes and returns a cache-busted public URL.
  Future<String> uploadFile({
    required String vendorId,
    required String documentType,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final path = '$vendorId/$documentType';
    await _client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    final rawUrl = _client.storage.from(_bucket).getPublicUrl(path);
    final cacheBust = DateTime.now().millisecondsSinceEpoch;
    return '$rawUrl?v=$cacheBust';
  }

  /// Inserts a new row or updates the existing row for the same vendor+type.
  /// [customDocumentName] is stored only for the "other" document type.
  /// On UPDATE it is only written if non-null, preserving the existing value
  /// during a Replace operation.
  Future<void> saveDocument({
    required String vendorId,
    required String documentType,
    required String documentUrl,
    String? customDocumentName,
  }) async {
    final existing = await _client
        .from('vendor_documents')
        .select('id')
        .eq('vendor_id', vendorId)
        .eq('document_type', documentType)
        .maybeSingle();

    if (existing != null) {
      final updates = <String, dynamic>{
        'document_url': documentUrl,
        'verification_status': 'pending',
      };
      if (customDocumentName != null) {
        updates['custom_document_name'] = customDocumentName;
      }
      await _client
          .from('vendor_documents')
          .update(updates)
          .eq('id', existing['id'] as String);
    } else {
      await _client.from('vendor_documents').insert({
        'vendor_id': vendorId,
        'document_type': documentType,
        'document_url': documentUrl,
        'verification_status': 'pending',
        'custom_document_name': customDocumentName,
      });
    }
  }
}
