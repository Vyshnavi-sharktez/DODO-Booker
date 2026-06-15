import '../models/booking.dart';

abstract class IBookingsRepository {
  Future<List<Booking>> getVendorBookings(String vendorId);
  Future<Booking?> getBookingById(String bookingId);
  Future<void> updateBookingStatus(String bookingId, String newStatus);
  Future<void> rejectBooking({
    required String bookingId,
    required String rejectionReason,
  });
  Future<void> createAdminNotification({
    required String title,
    required String message,
    required String notificationType,
    required String entityId,
  });
  Future<void> createCustomerNotification({
    required String customerId,
    required String title,
    required String message,
    required String notificationType,
    required String entityId,
  });
}
