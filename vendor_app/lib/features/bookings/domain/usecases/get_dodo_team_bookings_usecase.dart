import '../models/booking.dart';
import '../repositories/i_bookings_repository.dart';

class GetDodoTeamBookingsUseCase {
  const GetDodoTeamBookingsUseCase(this._repository);
  final IBookingsRepository _repository;

  Future<List<Booking>> call(String dodoTeamId) =>
      _repository.getDodoTeamBookings(dodoTeamId);
}
