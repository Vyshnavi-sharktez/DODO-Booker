import '../models/vendor_profile.dart';
import '../repositories/i_profile_repository.dart';

class GetVendorProfileUseCase {
  const GetVendorProfileUseCase(this._repository);
  final IProfileRepository _repository;

  Future<VendorProfile?> call(String phone) => _repository.getProfileByPhone(phone);
}
