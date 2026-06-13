import '../models/booking.dart';
import '../repositories/i_bookings_repository.dart';

class GetVendorBookingsUseCase {
  const GetVendorBookingsUseCase(this._repository);
  final IBookingsRepository _repository;

  Future<List<Booking>> call(String vendorId) =>
      _repository.getVendorBookings(vendorId);
}
