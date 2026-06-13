import '../../domain/models/booking.dart';
import '../../domain/repositories/i_bookings_repository.dart';
import '../datasources/bookings_remote_datasource.dart';

class BookingsRepositoryImpl implements IBookingsRepository {
  const BookingsRepositoryImpl(this._datasource);
  final BookingsRemoteDatasource _datasource;

  // Only forward-progress targets are valid via updateBookingStatus.
  // Rejection goes through rejectBooking(); cancellation is admin-only.
  static const _validProgressTargets = {'in_progress', 'completed'};

  @override
  Future<List<Booking>> getVendorBookings(String vendorId) async {
    final rows = await _datasource.fetchVendorBookings(vendorId);
    return rows.map(Booking.fromMap).toList();
  }

  @override
  Future<void> updateBookingStatus(String bookingId, String newStatus) {
    if (!_validProgressTargets.contains(newStatus)) {
      throw ArgumentError(
        'Invalid status transition: "$newStatus" is not a permitted '
        'progress target. Allowed: $_validProgressTargets',
      );
    }
    return _datasource.updateBookingStatus(bookingId, newStatus);
  }

  @override
  Future<void> rejectBooking({
    required String bookingId,
    required String rejectionReason,
  }) {
    if (rejectionReason.trim().isEmpty) {
      throw ArgumentError('Rejection reason must not be empty.');
    }
    return _datasource.rejectBooking(
      bookingId: bookingId,
      rejectionReason: rejectionReason,
    );
  }

  @override
  Future<void> createAdminNotification({
    required String title,
    required String message,
    required String notificationType,
  }) =>
      _datasource.createAdminNotification(
        title: title,
        message: message,
        notificationType: notificationType,
      );
}
