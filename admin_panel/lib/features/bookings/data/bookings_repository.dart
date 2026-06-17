import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/booking.dart';

const _reviewSelect = '''
  *,
  customer_reviews!booking_id(id, rating, review_text, created_at),
  booking_items(
    service_id,
    quantity,
    unit_price,
    total_price,
    services(id, name)
  )
''';

class BookingsRepository {
  final SupabaseClient _supabase;

  const BookingsRepository(this._supabase);

  Future<List<Booking>> fetchBookings() async {
    final data = await _supabase
        .from('bookings')
        .select(_reviewSelect)
        .order('created_at', ascending: false);
    final bookings = (data as List<dynamic>)
        .map((r) => Booking.fromMap(r as Map<String, dynamic>))
        .toList();
    final reviewedCount = bookings.where((b) => b.review != null).length;
    debugPrint(
      '[DODO][Bookings] Review loaded: $reviewedCount of ${bookings.length} bookings have reviews',
    );
    return bookings;
  }

  Future<Booking> updateBooking(
    String id, {
    required String vendorId,
    required DateTime serviceDate,
    required String status,
    String? notes,
  }) async {
    final data = await _supabase
        .from('bookings')
        .update({
          'vendor_id': vendorId,
          'service_date': serviceDate.toIso8601String().split('T').first,
          'status': status,
          'notes': notes,
        })
        .eq('id', id)
        .select(_reviewSelect)
        .single();
    return Booking.fromMap(data);
  }

  Future<void> deleteBooking(String id) async {
    await _supabase.from('bookings').delete().eq('id', id);
  }
}
