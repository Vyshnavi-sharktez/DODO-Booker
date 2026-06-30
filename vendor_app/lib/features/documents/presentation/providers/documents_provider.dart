import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../data/datasources/documents_remote_datasource.dart';
import '../../data/repositories/documents_repository_impl.dart';
import '../../domain/models/vendor_document.dart';
import '../../domain/repositories/i_documents_repository.dart';
import '../../domain/usecases/get_vendor_documents_usecase.dart';
import '../../domain/usecases/upload_document_usecase.dart';

final documentTypesProvider =
    FutureProvider.autoDispose<List<DocumentTypeModel>>((ref) {
  return ref.read(documentsDatasourceProvider).fetchDocumentTypes();
});

final documentsDatasourceProvider = Provider<DocumentsRemoteDatasource>((ref) {
  return DocumentsRemoteDatasource(ref.watch(supabaseClientProvider));
});

final documentsRepositoryProvider = Provider<IDocumentsRepository>((ref) {
  return DocumentsRepositoryImpl(ref.watch(documentsDatasourceProvider));
});

final getVendorDocumentsUseCaseProvider =
    Provider<GetVendorDocumentsUseCase>((ref) {
  return GetVendorDocumentsUseCase(ref.watch(documentsRepositoryProvider));
});

final uploadDocumentUseCaseProvider = Provider<UploadDocumentUseCase>((ref) {
  return UploadDocumentUseCase(ref.watch(documentsRepositoryProvider));
});

final vendorDocumentsProvider =
    FutureProvider.autoDispose<List<VendorDocument>>((ref) {
  final vendor = ref.watch(currentVendorUserProvider);
  if (vendor == null) return Future.value([]);
  return ref.read(getVendorDocumentsUseCaseProvider)(vendor.id);
});
