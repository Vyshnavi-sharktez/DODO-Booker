import 'dart:typed_data';
import '../repositories/i_profile_repository.dart';

class UploadProfilePhotoUseCase {
  const UploadProfilePhotoUseCase(this._repository);
  final IProfileRepository _repository;

  Future<String> call({
    required String vendorId,
    required Uint8List bytes,
    required String contentType,
  }) =>
      _repository.uploadProfilePhoto(
        vendorId: vendorId,
        bytes: bytes,
        contentType: contentType,
      );
}
