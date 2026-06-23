import '../../domain/models/booking.dart';
import '../../domain/repositories/i_bookings_repository.dart';
import '../datasources/bookings_remote_datasource.dart';

class BookingsRepositoryImpl implements IBookingsRepository {
  const BookingsRepositoryImpl(this._datasource);
  final BookingsRemoteDatasource _datasource;

  // Only "Start Service" (assigned→in_progress) goes through updateBookingStatus.
  // Completion requires OTP: use initiateCompletion + verifyCompletionOtp instead.
  static const _validProgressTargets = {'in_progress'};

  @override
  Future<List<Booking>> getVendorBookings(String vendorId) async {
    final rows = await _datasource.fetchVendorBookings(vendorId);
    return rows.map(Booking.fromMap).toList();
  }

  @override
  Future<Booking?> getBookingById(String bookingId) async {
    final row = await _datasource.fetchBookingById(bookingId);
    if (row == null) return null;
    return Booking.fromMap(row);
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
  Future<void> initiateCompletion(String bookingId) =>
      _datasource.initiateCompletion(bookingId);

  @override
  Future<bool> verifyCompletionOtp(String bookingId, String otp) =>
      _datasource.verifyCompletionOtp(bookingId, otp);

  @override
  Future<void> createAdminNotification({
    required String title,
    required String message,
    required String notificationType,
    required String entityId,
  }) =>
      _datasource.createAdminNotification(
        title: title,
        message: message,
        notificationType: notificationType,
        entityId: entityId,
      );

  @override
  Future<void> createCustomerNotification({
    required String customerId,
    required String title,
    required String message,
    required String notificationType,
    required String entityId,
  }) =>
      _datasource.createCustomerNotification(
        customerId: customerId,
        title: title,
        message: message,
        notificationType: notificationType,
        entityId: entityId,
      );
}
