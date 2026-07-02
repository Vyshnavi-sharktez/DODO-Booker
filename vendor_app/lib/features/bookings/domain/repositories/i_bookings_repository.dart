import '../models/booking.dart';

abstract class IBookingsRepository {
  Future<List<Booking>> getVendorBookings(String vendorId);
  Future<List<Booking>> getDodoTeamBookings(String dodoTeamId);
  Future<Booking?> getBookingById(String bookingId);
  Future<void> updateBookingStatus(String bookingId, String newStatus);
  Future<void> rejectBooking({
    required String bookingId,
    required String rejectionReason,
  });
  Future<void> initiateCompletion(String bookingId);
  Future<bool> verifyCompletionOtp(String bookingId, String otp);
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
