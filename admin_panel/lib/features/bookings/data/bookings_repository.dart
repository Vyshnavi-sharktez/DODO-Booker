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

// Valid assignment_type values that match the DB schema.
const kAssignmentTypeVendor = 'External Vendor';
const kAssignmentTypeTeam = 'DODO Team';
const kAssignmentTypeUnassigned = 'Unassigned';

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

  // Status is derived automatically:
  //   Unassigned      → pending
  //   External Vendor / DODO Team → assigned
  Future<Booking> updateBookingAssignment(
    String id, {
    required String assignmentType,
    String? vendorId,
    String? dodoTeamId,
    required DateTime serviceDate,
    String? notes,
  }) async {
    final status = assignmentType == kAssignmentTypeUnassigned
        ? 'pending'
        : 'assigned';

    final Map<String, dynamic> payload = {
      'service_date': serviceDate.toIso8601String().split('T').first,
      'status': status,
      'notes': notes,
      'assignment_type': assignmentType,
    };

    switch (assignmentType) {
      case kAssignmentTypeVendor:
        payload['vendor_id'] = vendorId;
        payload['dodo_team_id'] = null;
      case kAssignmentTypeTeam:
        payload['vendor_id'] = null;
        payload['dodo_team_id'] = dodoTeamId;
      default:
        payload['vendor_id'] = null;
        payload['dodo_team_id'] = null;
    }

    final data = await _supabase
        .from('bookings')
        .update(payload)
        .eq('id', id)
        .select(_reviewSelect)
        .single();
    return Booking.fromMap(data);
  }

  Future<Booking> cancelBooking(String id) async {
    final data = await _supabase
        .from('bookings')
        .update({'status': 'cancelled'})
        .eq('id', id)
        .select(_reviewSelect)
        .single();
    return Booking.fromMap(data);
  }

  Future<Booking> createBooking({
    required String customerId,
    required DateTime serviceDate,
    required String address,
    String? notes,
    required List<({String serviceId, int quantity, double unitPrice})> items,
  }) async {
    final subtotal =
        items.fold(0.0, (sum, e) => sum + e.unitPrice * e.quantity);

    final bookingData = await _supabase
        .from('bookings')
        .insert({
          'customer_id': customerId,
          'status': 'pending',
          'service_date': serviceDate.toIso8601String().split('T').first,
          'address': address.isNotEmpty ? address : null,
          'notes': notes,
          'subtotal': subtotal,
          'discount_amount': 0.0,
          'total_amount': subtotal,
        })
        .select('id')
        .single();

    final bookingId = bookingData['id'] as String;

    if (items.isNotEmpty) {
      await _supabase.from('booking_items').insert(
        items
            .map((e) => {
                  'booking_id': bookingId,
                  'service_id': e.serviceId,
                  'quantity': e.quantity,
                  'unit_price': e.unitPrice,
                  'total_price': e.unitPrice * e.quantity,
                })
            .toList(),
      );
    }

    final data = await _supabase
        .from('bookings')
        .select(_reviewSelect)
        .eq('id', bookingId)
        .single();
    return Booking.fromMap(data);
  }

  Future<void> deleteBooking(String id) async {
    await _supabase.from('bookings').delete().eq('id', id);
  }
}
