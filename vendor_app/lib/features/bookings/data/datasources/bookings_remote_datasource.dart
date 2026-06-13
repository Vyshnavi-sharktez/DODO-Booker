import 'package:supabase_flutter/supabase_flutter.dart';

class BookingsRemoteDatasource {
  const BookingsRemoteDatasource(this._client);
  final SupabaseClient _client;

  static const _select =
      'id, booking_number, customer_id, vendor_id, service_date, '
      'status, subtotal, discount_amount, total_amount, '
      'address, notes, created_at, rejection_reason, rejected_at';

  Future<List<Map<String, dynamic>>> fetchVendorBookings(
    String vendorId,
  ) async {
    final data = await _client
        .from('bookings')
        .select(_select)
        .eq('vendor_id', vendorId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<void> updateBookingStatus(
    String bookingId,
    String newStatus,
  ) async {
    await _client
        .from('bookings')
        .update({'status': newStatus})
        .eq('id', bookingId);
  }

  // vendor_id is intentionally NOT set to null — the vendor retains ownership
  // so the booking remains visible in their Rejected tab and admin can reassign.
  Future<void> rejectBooking({
    required String bookingId,
    required String rejectionReason,
  }) async {
    await _client.from('bookings').update({
      'status': 'rejected',
      'rejection_reason': rejectionReason,
      'rejected_at': DateTime.now().toIso8601String(),
    }).eq('id', bookingId);
  }

  Future<void> createAdminNotification({
    required String title,
    required String message,
    required String notificationType,
  }) async {
    await _client.from('notifications').insert({
      'user_type': 'admin',
      'user_id': 'admin',
      'title': title,
      'message': message,
      'notification_type': notificationType,
      'is_read': false,
    });
  }
}
