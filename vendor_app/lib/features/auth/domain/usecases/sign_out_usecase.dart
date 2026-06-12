import '../repositories/i_auth_repository.dart';

class SignOutUseCase {
  const SignOutUseCase(this._repository);
  final IAuthRepository _repository;

  Future<void> call() => _repository.signOut();
}
