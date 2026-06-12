import '../entities/vendor_user.dart';
import '../repositories/i_auth_repository.dart';

class AuthStateChangesUseCase {
  const AuthStateChangesUseCase(this._repository);
  final IAuthRepository _repository;

  Stream<VendorUser?> call() => _repository.authStateChanges();
}
