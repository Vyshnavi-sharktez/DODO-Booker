import '../../../shared/repositories/base_repository.dart';
import '../domain/models/booking.dart';

class BookingsRepository extends BaseRepository {
  const BookingsRepository(super.supabase);

  Future<List<Booking>> fetchVendorBookings(String vendorId) async =>
      throw UnimplementedError();

  Future<Booking> fetchBookingById(String id) async =>
      throw UnimplementedError();

  Future<Booking> updateStatus(String id, String status) async =>
      throw UnimplementedError();
}
