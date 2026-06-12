import '../entities/vendor_user.dart';
import '../repositories/i_auth_repository.dart';

class VerifyOtpUseCase {
  const VerifyOtpUseCase(this._repository);
  final IAuthRepository _repository;

  Future<VendorUser> call({required String phone, required String token}) =>
      _repository.verifyOtp(phone: phone, token: token);
}
