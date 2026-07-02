import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/my_booking_model.dart';

class BookingsService {
  static const _phoneKey = 'dodo_auth_phone';
  final _client = Supabase.instance.client;

  // Explicit column list avoids relying on * to include columns that Supabase
  // RLS or PostgREST might silently omit (e.g. completion_otp).
  static const _bookingSelect = '''
    id, booking_number, customer_id, vendor_id, dodo_team_id,
    assignment_type, service_date, status,
    subtotal, discount_amount, total_amount,
    address, notes, created_at,
    completion_otp, otp_verified_at,
    booking_items(
      service_id,
      quantity,
      unit_price,
      total_price,
      services(
        id,
        name,
        categories(id, name),
        sub_categories(id, name)
      )
    )
  ''';

  Future<String> _getCustomerId() async {
    try {
      final phone = (await SharedPreferences.getInstance()).getString(_phoneKey);
      if (phone == null) throw Exception('Not authenticated');
      debugPrint('[DODO][Bookings] Current phone: $phone');
      final row = await _client
          .from('customers')
          .select('id')
          .eq('phone', phone)
          .single();
      final customerId = row['id'] as String;
      debugPrint('[DODO][Bookings] Customer ID: $customerId');
      return customerId;
    } catch (e, st) {
      debugPrint('================ BOOKINGS ERROR ================');
      debugPrint(e.toString());
      debugPrint(st.toString());
      debugPrint('================================================');
      rethrow;
    }
  }

  Future<List<MyBookingModel>> fetchMyBookings() async {
    try {
      final customerId = await _getCustomerId();
      debugPrint('[DODO][Bookings] Querying bookings for customer_id=$customerId');
      debugPrint('[DODO][Bookings] Select clause:\n$_bookingSelect');
      final data = await _client
          .from('bookings')
          .select(_bookingSelect)
          .eq('customer_id', customerId)
          .order('created_at', ascending: false);
      final rows = data as List;
      debugPrint('[DODO][Bookings] Rows returned: ${rows.length}');
      final bookings = rows
          .map((e) => MyBookingModel.fromJson(e as Map<String, dynamic>))
          .toList();
      for (final b in bookings) {
        debugPrint('[DODO][Bookings] Service loaded: ${b.serviceName}');
        debugPrint('[DODO][Bookings] Address loaded: ${b.address.city.isNotEmpty ? b.address.city : b.address.line1}');
        debugPrint('[OTP][Customer] list — id=${b.id}  status=${b.status}  otp=${b.completionOtp}');
      }
      return bookings;
    } catch (e, st) {
      debugPrint('================ BOOKINGS ERROR ================');
      debugPrint(e.toString());
      debugPrint(st.toString());
      debugPrint('================================================');
      rethrow;
    }
  }

  Future<MyBookingModel?> fetchBookingById(String id) async {
    debugPrint('[OTP][Customer] fetchBookingById — id=$id');
    final data = await _client
        .from('bookings')
        .select(_bookingSelect)
        .eq('id', id)
        .maybeSingle();
    if (data == null) {
      debugPrint('[OTP][Customer] fetchBookingById — no row returned');
      return null;
    }
    // ── OTP trace ────────────────────────────────────────────────────────────
    debugPrint('[OTP][Customer] raw status         = ${data['status']}');
    debugPrint('[OTP][Customer] raw completion_otp = ${data['completion_otp']}');
    debugPrint('[OTP][Customer] raw keys           = ${data.keys.toList()}');
    final booking = MyBookingModel.fromJson(data);
    debugPrint('[OTP][Customer] model.status       = ${booking.status}');
    debugPrint('[OTP][Customer] model.completionOtp= ${booking.completionOtp}');
    return booking;
  }

  Future<bool> cancelBooking(String bookingId) async {
    debugPrint('[DODO][Booking] Cancel requested for bookingId=$bookingId');

    // Fetch metadata needed for notifications before updating.
    Map<String, dynamic>? meta;
    try {
      meta = await _client
          .from('bookings')
          .select('vendor_id, booking_number')
          .eq('id', bookingId)
          .maybeSingle();
    } catch (_) {}

    debugPrint('[DODO][Booking] Updating booking status');
    await _client.from('bookings').update({
      'status': 'cancelled',
      'cancelled_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', bookingId);
    debugPrint('[DODO][Booking] Booking cancelled successfully');

    // Notify admin and vendor (if assigned) — non-fatal.
    final vendorId = meta?['vendor_id'] as String?;
    final bookingNum = meta?['booking_number'] as String? ?? '';
    final ref = bookingNum.isNotEmpty
        ? '#$bookingNum'
        : '#${bookingId.length > 8 ? bookingId.substring(0, 8) : bookingId}';

    try {
      await _client.from('notifications').insert({
        'user_type': 'admin',
        'user_id': 'admin',
        'title': 'Booking Cancelled',
        'message': 'Customer cancelled booking $ref.',
        'notification_type': 'booking_cancelled',
        'is_read': false,
        'entity_type': 'booking',
        'entity_id': bookingId,
      });
      if (vendorId != null && vendorId.isNotEmpty) {
        await _client.from('notifications').insert({
          'user_type': 'vendor',
          'user_id': vendorId,
          'title': 'Booking Cancelled',
          'message': 'Booking $ref has been cancelled.',
          'notification_type': 'booking_cancelled',
          'is_read': false,
          'entity_type': 'booking',
          'entity_id': bookingId,
        });
      }
    } catch (e) {
      debugPrint('[DODO][Booking] Warning: cancel notifications failed (non-fatal): $e');
    }

    return true;
  }
}
