import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BookingsRemoteDatasource {
  const BookingsRemoteDatasource(this._client);
  final SupabaseClient _client;

  static const _select = '''
    id, booking_number, customer_id, vendor_id, service_date,
    status, subtotal, discount_amount, total_amount,
    address, notes, created_at, rejection_reason, rejected_at,
    booking_items(
      service_id,
      quantity,
      unit_price,
      total_price,
      services(id, name)
    )
  ''';

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

  Future<Map<String, dynamic>?> fetchBookingById(String bookingId) async {
    debugPrint('[NOTIF][Vendor] fetchBookingById — id=$bookingId');
    final result = await _client
        .from('bookings')
        .select(_select)
        .eq('id', bookingId)
        .maybeSingle();
    debugPrint('[NOTIF][Vendor] Supabase result — ${result == null ? "null (no row)" : "found id=${result['id']}"}');
    return result;
  }

  Future<void> updateBookingStatus(
    String bookingId,
    String newStatus,
  ) async {
    await _client
        .from('bookings')
        .update({'status': newStatus}).eq('id', bookingId);
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
    required String entityId,
  }) async {
    await _client.from('notifications').insert({
      'user_type': 'admin',
      'user_id': 'admin',
      'title': title,
      'message': message,
      'notification_type': notificationType,
      'is_read': false,
      'entity_type': 'booking',
      'entity_id': entityId,
    });
  }

  Future<void> createCustomerNotification({
    required String customerId,
    required String title,
    required String message,
    required String notificationType,
    required String entityId,
  }) async {
    await _client.from('notifications').insert({
      'user_type': 'customer',
      'user_id': customerId,
      'title': title,
      'message': message,
      'notification_type': notificationType,
      'is_read': false,
      'entity_type': 'booking',
      'entity_id': entityId,
    });
  }
}
