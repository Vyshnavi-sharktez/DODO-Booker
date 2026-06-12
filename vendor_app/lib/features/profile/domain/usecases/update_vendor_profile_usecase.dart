import '../repositories/i_profile_repository.dart';

class UpdateVendorProfileUseCase {
  const UpdateVendorProfileUseCase(this._repository);
  final IProfileRepository _repository;

  Future<void> call({
    required String phone,
    required Map<String, dynamic> fields,
  }) => _repository.updateProfileByPhone(phone: phone, fields: fields);
}
