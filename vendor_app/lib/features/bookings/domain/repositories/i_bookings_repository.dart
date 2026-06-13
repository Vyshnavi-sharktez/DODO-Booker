import '../models/booking.dart';

abstract class IBookingsRepository {
  Future<List<Booking>> getVendorBookings(String vendorId);
  Future<void> updateBookingStatus(String bookingId, String newStatus);
  Future<void> rejectBooking({
    required String bookingId,
    required String rejectionReason,
  });
  Future<void> createAdminNotification({
    required String title,
    required String message,
    required String notificationType,
  });
}
