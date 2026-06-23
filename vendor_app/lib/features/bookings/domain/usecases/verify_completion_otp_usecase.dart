import '../repositories/i_bookings_repository.dart';

class VerifyCompletionOtpUseCase {
  const VerifyCompletionOtpUseCase(this._repository);
  final IBookingsRepository _repository;

  Future<bool> call(String bookingId, String otp) =>
      _repository.verifyCompletionOtp(bookingId, otp);
}
