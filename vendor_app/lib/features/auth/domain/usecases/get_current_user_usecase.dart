import '../entities/vendor_user.dart';
import '../repositories/i_auth_repository.dart';

class GetCurrentUserUseCase {
  const GetCurrentUserUseCase(this._repository);
  final IAuthRepository _repository;

  Future<VendorUser?> call() => _repository.getCurrentUser();
}
