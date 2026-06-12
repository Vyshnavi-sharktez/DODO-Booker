import '../repositories/i_auth_repository.dart';

class SignInWithOtpUseCase {
  const SignInWithOtpUseCase(this._repository);
  final IAuthRepository _repository;

  Future<void> call(String phone) => _repository.signInWithOtp(phone);
}
