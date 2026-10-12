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
  customers!customer_id(full_name, phone),
  customer_reviews!booking_id(id, rating, review_text, created_at),
  booking_items(
    service_id,
    service_name,
    item_name,
    category_name,
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

  Future<Booking?> fetchBookingById(String id) async {
    final data = await _supabase
        .from('bookings')
        .select(_reviewSelect)
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;
    final booking = Booking.fromMap(data as Map<String, dynamic>);
    final addonMap = await _fetchAddonsByBookingId([id]);
    return _mergeAddons([booking], addonMap).first;
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
        payload['dispatch_status'] = 'assigned';
        payload['last_dispatch_attempt_at'] = null;
        payload['current_dispatch_tier_priority'] = null;
      case kAssignmentTypeTeam:
        payload['vendor_id'] = null;
        payload['dodo_team_id'] = dodoTeamId;
        payload['dispatch_status'] = 'assigned_to_dodo_team';
        payload['last_dispatch_attempt_at'] = null;
        payload['current_dispatch_tier_priority'] = null;
      default:
        payload['vendor_id'] = null;
        payload['dodo_team_id'] = null;
        payload['dispatch_status'] = 'idle';
        payload['last_dispatch_attempt_at'] = null;
        payload['current_dispatch_tier_priority'] = null;
    }

    debugPrint('[MANUAL_ASSIGN][REPO] Executing updateBookingAssignment for bookingId=$id with payload: $payload');

    if (assignmentType == kAssignmentTypeVendor) {
      try {
        await _supabase
            .from('booking_assignments')
            .update({'status': 'cancelled', 'responded_at': DateTime.now().toIso8601String()})
            .eq('booking_id', id)
            .eq('status', 'pending');
      } catch (e) {
        debugPrint('Error cancelling pending assignment records on manual assignment: $e');
      }
    }

    try {
      final data = await _supabase
          .from('bookings')
          .update(payload)
          .eq('id', id)
          .select(_reviewSelect)
          .single();
      debugPrint('[MANUAL_ASSIGN][REPO] DB update success for $id. Result status=${data['status']}, vendor_id=${data['vendor_id']}, dispatch_status=${data['dispatch_status']}');
      return Booking.fromMap(data);
    } catch (e, st) {
      debugPrint('[MANUAL_ASSIGN][REPO] DB update FAILED for $id: $e\n$st');
      rethrow;
    }
  }

  Future<Booking> updateBookingAddress(
    String id,
    String address, {
    double? latitude,
    double? longitude,
  }) async {
    final payload = <String, dynamic>{
      'address': address.trim().isNotEmpty ? address.trim() : null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (latitude != null) payload['latitude'] = latitude;
    if (longitude != null) payload['longitude'] = longitude;

    final data = await _supabase
        .from('bookings')
        .update(payload)
        .eq('id', id)
        .select(_reviewSelect)
        .single();
    return Booking.fromMap(data);
  }

  Future<Booking> updateBookingStatus(String id, String newStatus) async {
    final current = await _supabase
        .from('bookings')
        .select('customer_id, booking_number, status, payment_method, vendor_id')
        .eq('id', id)
        .single();

    final oldStatus = current['status'] as String?;
    final customerId = current['customer_id'] as String?;
    final bookingNumber = current['booking_number'] as String? ?? '';
    final existingVendorId = current['vendor_id'] as String?;

    final Map<String, dynamic> payload = {
      'status': newStatus,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    final isReactivating = oldStatus == 'cancelled' &&
        (newStatus == 'pending' || newStatus == 'assigned');

    if (isReactivating) {
      payload['cancelled_by'] = null;
      payload['cancelled_at'] = null;
      payload['cancellation_reason'] = null;
      payload['payment_method'] = 'cash';
      payload['payment_status'] = 'pending';
      payload['cod_cash_collected'] = null;
      payload['cod_confirmed_at'] = null;
      payload['cod_not_collected_reason'] = null;

      if (newStatus == 'pending') {
        payload['assignment_type'] = kAssignmentTypeUnassigned;
        payload['vendor_id'] = null;
        payload['dodo_team_id'] = null;
        payload['dispatch_status'] = 'idle';
      } else if (newStatus == 'assigned') {
        if (existingVendorId != null && existingVendorId.isNotEmpty) {
          payload['assignment_type'] = kAssignmentTypeVendor;
          payload['dispatch_status'] = 'assigned';
        } else {
          payload['assignment_type'] = kAssignmentTypeUnassigned;
          payload['dispatch_status'] = 'idle';
        }
      }
    } else if (newStatus == 'cancelled') {
      payload['cancelled_by'] = 'admin';
      payload['cancelled_at'] = DateTime.now().toUtc().toIso8601String();
    } else if (newStatus == 'pending') {
      payload['assignment_type'] = kAssignmentTypeUnassigned;
      payload['vendor_id'] = null;
      payload['dodo_team_id'] = null;
      payload['dispatch_status'] = 'idle';
    }

    final data = await _supabase
        .from('bookings')
        .update(payload)
        .eq('id', id)
        .select(_reviewSelect)
        .single();

    if (customerId != null && customerId.isNotEmpty) {
      try {
        final statusLabel = switch (newStatus) {
          'pending' => 'Pending',
          'assigned' => 'Assigned',
          'accepted' => 'Accepted',
          'in_progress' => 'In Progress',
          'completed' => 'Completed',
          'cancelled' => 'Cancelled',
          _ => newStatus,
        };
        await _supabase.from('notifications').insert({
          'user_type': 'customer',
          'user_id': customerId,
          'title': 'Booking Status Updated',
          'message':
              'Your booking #$bookingNumber status has been updated to $statusLabel.',
          'notification_type': 'booking_status',
          'is_read': false,
          'entity_type': 'booking',
          'entity_id': id,
        });
      } catch (e) {
        debugPrint(
            '[DODO][Bookings] Warning: Failed to send customer notification: $e');
      }
    }

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
    String? scheduledTime,
    double? latitude,
    double? longitude,
    required List<({String serviceId, String? customName, String? customCategoryName, int quantity, double unitPrice})> items,
    List<({String addonId, String addonName, double addonPrice})> addons =
        const [],
    double discountAmount = 0.0,
    double taxAmount = 0.0,
    String? couponCode,
  }) async {
    final serviceTotal =
        items.fold(0.0, (sum, e) => sum + e.unitPrice * e.quantity);
    final addonsTotal = addons.fold(0.0, (sum, a) => sum + a.addonPrice);
    final subtotal = serviceTotal + addonsTotal;
    final total = (subtotal - discountAmount + taxAmount).clamp(0.0, double.infinity);

    // ── Validate catalog services and snapshot names ──────────────────────────
    // Done before inserting the booking to avoid orphaned booking rows.
    final catalogServiceIds = items
        .where((e) => e.serviceId.isNotEmpty)
        .map((e) => e.serviceId)
        .toSet()
        .toList();
    final serviceNameMap = <String, String>{};
    if (catalogServiceIds.isNotEmpty) {
      final rows = await _supabase
          .from('catalog_nodes')
          .select('id, name, is_active, is_bookable, availability_status, unavailability_message')
          .inFilter('id', catalogServiceIds);
      final fetched = <String>{};
      for (final row in rows as List<dynamic>) {
        final m = row as Map<String, dynamic>;
        final id = m['id'] as String;
        fetched.add(id);
        final isActive = m['is_active'] as bool? ?? false;
        final isBookable = m['is_bookable'] as bool? ?? false;
        final availabilityStatus = m['availability_status'] as String? ?? 'active';
        if (!isActive || !isBookable || availabilityStatus != 'active') {
          final hint = m['unavailability_message'] as String?;
          final name = m['name'] as String? ?? id;
          throw Exception(
            hint?.isNotEmpty == true ? hint : 'Service "$name" is currently unavailable',
          );
        }
        serviceNameMap[id] = m['name'] as String? ?? '';
      }
      for (final id in catalogServiceIds) {
        if (!fetched.contains(id)) {
          throw Exception('Service (id=$id) no longer exists and cannot be booked');
        }
      }
    }

    final bookingData = await _supabase
        .from('bookings')
        .insert({
          'customer_id': customerId,
          'status': 'pending',
          'service_date': serviceDate.toIso8601String().split('T').first,
          'address': address.isNotEmpty ? address : null,
          'notes': notes,
          'subtotal': subtotal,
          'discount_amount': discountAmount,
          'tax_amount': taxAmount,
          'total_amount': total,
          'is_admin_booking': true,
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
          if (scheduledTime != null) 'scheduled_time': scheduledTime,
          if (couponCode != null) 'coupon_code': couponCode,
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
                  if (e.serviceId.isNotEmpty) 'service_id': e.serviceId,
                  // Catalog items: snapshot the validated catalog name for history.
                  if (e.serviceId.isNotEmpty && serviceNameMap.containsKey(e.serviceId))
                    'service_name': serviceNameMap[e.serviceId],
                  // Custom items (no serviceId): write admin-entered labels.
                  if (e.serviceId.isEmpty && e.customName != null && e.customName!.isNotEmpty)
                    'item_name': e.customName,
                  if (e.serviceId.isEmpty && e.customCategoryName != null && e.customCategoryName!.isNotEmpty)
                    'category_name': e.customCategoryName,
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

  Future<Booking> updateBookingFull({
    required String id,
    required DateTime serviceDate,
    required String address,
    required String status,
    String? notes,
    String? scheduledTime,
    double? latitude,
    double? longitude,
    required List<({String serviceId, String? customName, String? customCategoryName, int quantity, double unitPrice})> items,
    List<({String addonId, String addonName, double addonPrice})> addons = const [],
    double discountAmount = 0.0,
    double taxAmount = 0.0,
    String? couponCode,
  }) async {
    final serviceTotal =
        items.fold(0.0, (sum, e) => sum + e.unitPrice * e.quantity);
    final addonsTotal = addons.fold(0.0, (sum, a) => sum + a.addonPrice);
    final subtotal = serviceTotal + addonsTotal;
    final total =
        (subtotal - discountAmount + taxAmount).clamp(0.0, double.infinity);

    // Snapshot service names for booking_items.service_name.
    // Unlike createBooking, availability (isBookable / isActive) is NOT
    // re-validated here: the admin is editing an existing booking and must
    // be able to preserve services that were made unavailable after the fact.
    final catalogServiceIds = items
        .where((e) => e.serviceId.isNotEmpty)
        .map((e) => e.serviceId)
        .toSet()
        .toList();
    final serviceNameMap = <String, String>{};
    if (catalogServiceIds.isNotEmpty) {
      final rows = await _supabase
          .from('catalog_nodes')
          .select('id, name')
          .inFilter('id', catalogServiceIds);
      for (final row in rows as List<dynamic>) {
        final m = row as Map<String, dynamic>;
        serviceNameMap[m['id'] as String] = m['name'] as String? ?? '';
      }
    }

    // Mark as admin booking before touching items so the category-enforcement
    // trigger sees is_admin_booking = true when the new rows are inserted.
    await _supabase
        .from('bookings')
        .update({'is_admin_booking': true})
        .eq('id', id);

    // Replace booking_items FIRST so they are already in their final state
    // when the bookings UPDATE below fires the realtime event to the customer app.
    await _supabase.from('booking_items').delete().eq('booking_id', id);
    if (items.isNotEmpty) {
      await _supabase.from('booking_items').insert(
        items
            .map((e) => {
                  'booking_id': id,
                  if (e.serviceId.isNotEmpty) 'service_id': e.serviceId,
                  if (e.serviceId.isNotEmpty &&
                      serviceNameMap.containsKey(e.serviceId))
                    'service_name': serviceNameMap[e.serviceId],
                  if (e.serviceId.isEmpty &&
                      e.customName != null &&
                      e.customName!.isNotEmpty)
                    'item_name': e.customName,
                  if (e.serviceId.isEmpty &&
                      e.customCategoryName != null &&
                      e.customCategoryName!.isNotEmpty)
                    'category_name': e.customCategoryName,
                  'quantity': e.quantity,
                  'unit_price': e.unitPrice,
                  'total_price': e.unitPrice * e.quantity,
                })
            .toList(),
      );
    }

    // Replace booking_addons FIRST (non-fatal)
    List<BookingAddon> updatedAddons = [];
    try {
      await _supabase.from('booking_addons').delete().eq('booking_id', id);
      if (addons.isNotEmpty) {
        await _supabase.from('booking_addons').insert(
          addons
              .map((a) => {
                    'booking_id': id,
                    'addon_id': a.addonId,
                    'addon_name': a.addonName,
                    'addon_price': a.addonPrice,
                  })
              .toList(),
        );
        updatedAddons = addons
            .map((a) => BookingAddon(
                  addonId: a.addonId,
                  name: a.addonName,
                  price: a.addonPrice,
                ))
            .toList();
      }
    } catch (e) {
      debugPrint(
          '[DODO][Bookings] Warning: booking_addons update failed: $e');
    }

    // Update booking record LAST — fires the realtime event to the customer app
    // after items and addons are already committed.
    await _supabase.from('bookings').update({
      'service_date': serviceDate.toIso8601String().split('T').first,
      'address': address.isNotEmpty ? address : null,
      'status': status,
      'notes': notes,
      'subtotal': subtotal,
      'discount_amount': discountAmount,
      'tax_amount': taxAmount,
      'total_amount': total,
      'scheduled_time': scheduledTime,
      'is_admin_booking': true,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (couponCode != null) 'coupon_code': couponCode,
    }).eq('id', id);

    final data = await _supabase
        .from('bookings')
        .select(_reviewSelect)
        .eq('id', id)
        .single();
    return Booking.fromMap(data).copyWith(addons: updatedAddons);
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

    try {
      await _supabase.from('service_warranties').update({
        'status': 'Resolved',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('rework_booking_id', id);
    } catch (e) {
      debugPrint('[DODO][Admin] Warning: Failed to sync service_warranties status to Resolved via OTP: $e');
    }

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
    debugPrint('[DISPATCH][REPO] Invoking dispatch_booking_next_tier RPC with p_booking_id: $bookingId');
    final response = await _supabase.rpc('dispatch_booking_next_tier', params: {
      'p_booking_id': bookingId,
    });
    debugPrint('[DISPATCH][REPO] RPC response for $bookingId: $response');
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
