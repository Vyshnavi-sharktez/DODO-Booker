import '../repositories/i_bookings_repository.dart';

class RejectBookingUseCase {
  const RejectBookingUseCase(this._repository);
  final IBookingsRepository _repository;

  Future<void> call({
    required String bookingId,
    required String rejectionReason,
  }) =>
      _repository.rejectBooking(
        bookingId: bookingId,
        rejectionReason: rejectionReason,
      );
}
