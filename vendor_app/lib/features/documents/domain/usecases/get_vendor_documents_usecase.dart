import '../models/vendor_document.dart';
import '../repositories/i_documents_repository.dart';

class GetVendorDocumentsUseCase {
  const GetVendorDocumentsUseCase(this._repository);
  final IDocumentsRepository _repository;

  Future<List<VendorDocument>> call(String vendorId) =>
      _repository.getDocuments(vendorId);
}
