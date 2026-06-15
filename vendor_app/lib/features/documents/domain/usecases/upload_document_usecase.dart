import 'dart:typed_data';
import '../repositories/i_documents_repository.dart';

class UploadDocumentUseCase {
  const UploadDocumentUseCase(this._repository);
  final IDocumentsRepository _repository;

  Future<void> call({
    required String vendorId,
    required String documentType,
    required Uint8List bytes,
    required String contentType,
    String? customDocumentName,
  }) =>
      _repository.uploadDocument(
        vendorId: vendorId,
        documentType: documentType,
        bytes: bytes,
        contentType: contentType,
        customDocumentName: customDocumentName,
      );
}
