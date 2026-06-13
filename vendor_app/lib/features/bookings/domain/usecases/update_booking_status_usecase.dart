import '../repositories/i_bookings_repository.dart';

class UpdateBookingStatusUseCase {
  const UpdateBookingStatusUseCase(this._repository);
  final IBookingsRepository _repository;

  Future<void> call(String bookingId, String newStatus) =>
      _repository.updateBookingStatus(bookingId, newStatus);
}
