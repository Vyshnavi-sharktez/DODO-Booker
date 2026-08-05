import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/booking.dart';
import '../domain/models/booking_addon.dart';
import '../domain/models/booking_assignment_record.dart';
import '../domain/models/dispatch_settings.dart';
import '../../vendors/domain/models/vendor.dart';

String _generateOtp() => (100000 + Random().nextInt(900000)).toString();

// booking_addons is NOT embedded here — PostgREST cannot resolve the join
// without a recognised FK. Addons are fetched via a separate query.
const _reviewSelect = '''
  *,
  vendors(id, business_name),
  customer_reviews!booking_id(id, rating, review_text, created_at),
  booking_items(
    service_id,
    quantity,
    unit_price,
    total_price,
    catalog_nodes!booking_items_service_id_catalog_fkey(id, name)
  ),
  amc_contracts!amc_contract_id(visits_completed, num_visits, total_visits, created_at, service_interval, status, cancellation_reason, cancellation_remarks, cancellation_requested_at, quantity)
''';

// Valid assignment_type values that match the DB schema.
const kAssignmentTypeVendor = 'External Vendor';
const kAssignmentTypeTeam = 'DODO Team';
const kAssignmentTypeUnassigned = 'Unassigned';

class BookingsRepository {
  final SupabaseClient _supabase;

  const BookingsRepository(this._supabase);

  // ── Addons helper ────────────────────────────────────────────────────────────
  // Fetches booking_addons for a list of booking IDs using a plain filter
  // (no PostgREST embedded join required). Returns a map keyed by booking_id.
  Future<Map<String, List<BookingAddon>>> _fetchAddonsByBookingId(
    List<String> bookingIds,
  ) async {
    if (bookingIds.isEmpty) return {};
    try {
      final data = await _supabase
          .from('booking_addons')
          .select('booking_id, addon_id, addon_name, addon_price')
          .inFilter('booking_id', bookingIds);
      final result = <String, List<BookingAddon>>{};
      for (final row in data as List<dynamic>) {
        final m = row as Map<String, dynamic>;
        final bid = m['booking_id'] as String;
        result.putIfAbsent(bid, () => []).add(BookingAddon.fromMap(m));
      }
      return result;
    } catch (e) {
      debugPrint('[DODO][Bookings] Warning: booking_addons fetch failed: $e');
      return {};
    }
  }

  // Merges an addons map into a bookings list in-place.
  List<Booking> _mergeAddons(
    List<Booking> bookings,
    Map<String, List<BookingAddon>> addonsByBookingId,
  ) {
    if (addonsByBookingId.isEmpty) return bookings;
    return bookings.map((b) {
      final addons = addonsByBookingId[b.id];
      return addons != null ? b.copyWith(addons: addons) : b;
    }).toList();
  }

  // ── Read ─────────────────────────────────────────────────────────────────────

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

    final addonMap = await _fetchAddonsByBookingId(
      bookings.map((b) => b.id).toList(),
    );
    return _mergeAddons(bookings, addonMap);
  }

  // ── Mutations ────────────────────────────────────────────────────────────────

  // Status is derived automatically:
  //   Unassigned      → pending
  //   External Vendor → assigned
  //   DODO Team       → assigned_to_dodo_team (no vendor accept step)
  Future<Booking> updateBookingAssignment(
    String id, {
    required String assignmentType,
    String? vendorId,
    String? dodoTeamId,
    required DateTime serviceDate,
    String? notes,
  }) async {
    final status = switch (assignmentType) {
      kAssignmentTypeUnassigned => 'pending',
      kAssignmentTypeTeam => 'assigned_to_dodo_team',
      _ => 'assigned',
    };

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

  Future<Booking> cancelBooking(String id, {String? reason}) async {
    final updateData = <String, dynamic>{
      'status': 'cancelled',
      'cancelled_by': 'admin',
      'cancelled_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (reason != null) updateData['cancellation_reason'] = reason;

    final data = await _supabase
        .from('bookings')
        .update(updateData)
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
    List<({String addonId, String addonName, double addonPrice})> addons =
        const [],
  }) async {
    final serviceTotal =
        items.fold(0.0, (sum, e) => sum + e.unitPrice * e.quantity);
    final addonsTotal = addons.fold(0.0, (sum, a) => sum + a.addonPrice);

    final bookingData = await _supabase
        .from('bookings')
        .insert({
          'customer_id': customerId,
          'status': 'pending',
          'service_date': serviceDate.toIso8601String().split('T').first,
          'address': address.isNotEmpty ? address : null,
          'notes': notes,
          'subtotal': serviceTotal,
          'discount_amount': 0.0,
          'total_amount': serviceTotal + addonsTotal,
          'completion_otp': _generateOtp(),
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

    // Insert addons — non-fatal: table may not be set up yet in this environment.
    List<BookingAddon> insertedAddons = [];
    if (addons.isNotEmpty) {
      try {
        await _supabase.from('booking_addons').insert(
          addons
              .map((a) => {
                    'booking_id': bookingId,
                    'addon_id': a.addonId,
                    'addon_name': a.addonName,
                    'addon_price': a.addonPrice,
                  })
              .toList(),
        );
        insertedAddons = addons
            .map((a) => BookingAddon(
                  addonId: a.addonId,
                  name: a.addonName,
                  price: a.addonPrice,
                ))
            .toList();
      } catch (e) {
        debugPrint('[DODO][Bookings] Warning: booking_addons insert failed: $e');
      }
    }

    final data = await _supabase
        .from('bookings')
        .select(_reviewSelect)
        .eq('id', bookingId)
        .single();
    return Booking.fromMap(data).copyWith(addons: insertedAddons);
  }

  Future<Booking> startDodoTeamService(String id) async {
    final existing = await _supabase
        .from('bookings')
        .select('completion_otp')
        .eq('id', id)
        .single();

    final payload = <String, dynamic>{'status': 'in_progress'};
    if (existing['completion_otp'] == null) {
      payload['completion_otp'] = _generateOtp();
    }

    final data = await _supabase
        .from('bookings')
        .update(payload)
        .eq('id', id)
        .select(_reviewSelect)
        .single();
    return Booking.fromMap(data);
  }

  Future<Booking> completeDodoTeamBooking(
    String id,
    String enteredOtp,
  ) async {
    final booking = await _supabase
        .from('bookings')
        .select('completion_otp')
        .eq('id', id)
        .single();

    if (booking['completion_otp'] != enteredOtp) {
      throw Exception('Invalid OTP');
    }

    final data = await _supabase
        .from('bookings')
        .update({
          'status': 'completed',
          'otp_verified_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id)
        .select(_reviewSelect)
        .single();

    return Booking.fromMap(data);
  }

  Future<void> deleteBooking(String id) async {
    await _supabase.from('bookings').delete().eq('id', id);
  }

  // ── Phase 4 Dispatch Engine Methods ─────────────────────────────────────────

  Future<DispatchSettings> fetchDispatchSettings() async {
    final data = await _supabase
        .from('dispatch_settings')
        .select('*')
        .limit(1)
        .maybeSingle();
    if (data == null) {
      return const DispatchSettings(
        id: '',
        isTierDispatchEnabled: true,
        tierTimeoutSeconds: 60,
        maxAttemptsPerTier: 1,
      );
    }
    return DispatchSettings.fromMap(data);
  }

  Future<DispatchSettings> updateDispatchSettings(DispatchSettings settings) async {
    final userId = _supabase.auth.currentUser?.id;
    final payload = settings.toMap();
    if (userId != null) payload['updated_by'] = userId;
    payload['updated_at'] = DateTime.now().toIso8601String();

    final data = await _supabase
        .from('dispatch_settings')
        .update(payload)
        .eq('id', settings.id)
        .select('*')
        .single();
    return DispatchSettings.fromMap(data);
  }

  Future<Map<String, dynamic>> dispatchBookingNextTier(String bookingId) async {
    final response = await _supabase.rpc('dispatch_booking_next_tier', params: {
      'p_booking_id': bookingId,
    });
    return (response as Map<String, dynamic>?) ?? {};
  }

  Future<List<BookingAssignmentRecord>> fetchBookingAssignmentsHistory(
      String bookingId) async {
    final data = await _supabase
        .from('booking_assignments')
        .select('*, vendors(*), vendor_tiers(*), bookings(booking_number)')
        .eq('booking_id', bookingId)
        .order('assigned_at', ascending: true);
    return (data as List<dynamic>)
        .map((r) => BookingAssignmentRecord.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<BookingAssignmentRecord>> fetchAllBookingAssignmentsHistory() async {
    final data = await _supabase
        .from('booking_assignments')
        .select('*, vendors(*), vendor_tiers(*), bookings(booking_number)')
        .order('assigned_at', ascending: false);
    return (data as List<dynamic>)
        .map((r) => BookingAssignmentRecord.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<int> processPendingDispatchEscalations() async {
    final response =
        await _supabase.rpc('process_pending_dispatch_escalations');
    return (response as num?)?.toInt() ?? 0;
  }
}
