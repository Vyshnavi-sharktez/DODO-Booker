import 'dart:typed_data';
import '../../domain/models/vendor_document.dart';
import '../../domain/repositories/i_documents_repository.dart';
import '../datasources/documents_remote_datasource.dart';

class DocumentsRepositoryImpl implements IDocumentsRepository {
  const DocumentsRepositoryImpl(this._datasource);
  final DocumentsRemoteDatasource _datasource;

  @override
  Future<List<VendorDocument>> getDocuments(String vendorId) async {
    final rows = await _datasource.fetchDocuments(vendorId);
    return rows.map(VendorDocument.fromMap).toList();
  }

  @override
  Future<void> uploadDocument({
    required String vendorId,
    required String documentType,
    required Uint8List bytes,
    required String contentType,
    String? customDocumentName,
  }) async {
    final url = await _datasource.uploadFile(
      vendorId: vendorId,
      documentType: documentType,
      bytes: bytes,
      contentType: contentType,
    );
    await _datasource.saveDocument(
      vendorId: vendorId,
      documentType: documentType,
      documentUrl: url,
      customDocumentName: customDocumentName,
    );
  }
}
