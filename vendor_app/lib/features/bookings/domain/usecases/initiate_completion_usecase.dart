import '../repositories/i_bookings_repository.dart';

class InitiateCompletionUseCase {
  const InitiateCompletionUseCase(this._repository);
  final IBookingsRepository _repository;

  Future<void> call(String bookingId) =>
      _repository.initiateCompletion(bookingId);
}
