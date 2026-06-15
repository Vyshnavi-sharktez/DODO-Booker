import 'dart:typed_data';
import '../models/vendor_document.dart';

abstract interface class IDocumentsRepository {
  Future<List<VendorDocument>> getDocuments(String vendorId);
  Future<void> uploadDocument({
    required String vendorId,
    required String documentType,
    required Uint8List bytes,
    required String contentType,
    String? customDocumentName,
  });
}
