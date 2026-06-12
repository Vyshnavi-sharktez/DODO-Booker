import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/my_booking_model.dart';

class BookingsService {
  static const _phoneKey = 'dodo_auth_phone';
  final _client = Supabase.instance.client;

  // Nested select: joins booking_items → services → categories / sub_categories
  static const _bookingSelect = '''
    *,
    booking_items(
      service_id,
      services(
        id,
        name,
        categories(id, name),
        sub_categories(id, name)
      )
    )
  ''';

  Future<String> _getCustomerId() async {
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
  }

  Future<List<MyBookingModel>> fetchMyBookings() async {
    final customerId = await _getCustomerId();
    debugPrint('[DODO][Bookings] Querying bookings for customer_id=$customerId');
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
    }
    return bookings;
  }

  Future<MyBookingModel?> fetchBookingById(String id) async {
    debugPrint('[DODO][Bookings] fetchBookingById($id)');
    final data = await _client
        .from('bookings')
        .select(_bookingSelect)
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;
    final b = MyBookingModel.fromJson(data);
    debugPrint('[DODO][Bookings] Service loaded: ${b.serviceName}');
    debugPrint('[DODO][Bookings] Address loaded: ${b.address.city.isNotEmpty ? b.address.city : b.address.line1}');
    return b;
  }

  Future<bool> cancelBooking(String bookingId) async {
    debugPrint('[DODO][Booking] Cancel requested for bookingId=$bookingId');
    debugPrint('[DODO][Booking] Updating booking status');
    await _client.from('bookings').update({
      'status': 'cancelled',
      'cancelled_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', bookingId);
    debugPrint('[DODO][Booking] Booking cancelled successfully');
    return true;
  }
}
