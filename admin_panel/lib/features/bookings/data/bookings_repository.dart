import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/booking.dart';

class BookingsRepository {
  final SupabaseClient _supabase;

  const BookingsRepository(this._supabase);

  Future<List<Booking>> fetchBookings() async {
    final data = await _supabase
        .from('bookings')
        .select()
        .order('created_at', ascending: false);
    return (data as List<dynamic>)
        .map((r) => Booking.fromMap(r as Map<String, dynamic>))
        .toList();
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
        .select()
        .single();
    return Booking.fromMap(data);
  }

  Future<void> deleteBooking(String id) async {
    await _supabase.from('bookings').delete().eq('id', id);
  }
}
