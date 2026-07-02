import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BookingsRemoteDatasource {
  const BookingsRemoteDatasource(this._client);
  final SupabaseClient _client;

  static const _select = '''
    id, booking_number, customer_id, vendor_id, dodo_team_id,
    assignment_type, service_date,
    status, subtotal, discount_amount, total_amount,
    address, notes, created_at, rejection_reason, rejected_at,
    completion_otp, otp_verified_at,
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

  Future<List<Map<String, dynamic>>> fetchDodoTeamBookings(
    String dodoTeamId,
  ) async {
    // Exclude assigned_to_dodo_team: DODO Team only sees bookings once
    // the admin has started the service (in_progress and beyond).
    final data = await _client
        .from('bookings')
        .select(_select)
        .eq('dodo_team_id', dodoTeamId)
        .neq('status', 'assigned_to_dodo_team')
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

  Future<void> initiateCompletion(String bookingId) async {
    // Preserve an OTP already set at booking creation; only generate as fallback
    // for bookings created before the OTP-at-creation change was deployed.
    final row = await _client
        .from('bookings')
        .select('completion_otp')
        .eq('id', bookingId)
        .single();
    final existingOtp = row['completion_otp'] as String?;

    final payload = <String, dynamic>{'status': 'awaiting_verification'};
    if (existingOtp == null || existingOtp.isEmpty) {
      payload['completion_otp'] =
          (100000 + Random().nextInt(900000)).toString();
    }

    await _client.from('bookings').update(payload).eq('id', bookingId);
  }

  // Returns true and sets status=completed when OTP matches; false otherwise.
  Future<bool> verifyCompletionOtp(String bookingId, String otp) async {
    debugPrint('[OTP][DS] ══════════ verifyCompletionOtp() START ══════════');
    debugPrint('[OTP][DS] bookingId : $bookingId');
    debugPrint('[OTP][DS] otp passed: "$otp"  len=${otp.length}  codeUnits=${otp.codeUnits}');

    // ── Step 1: Fetch stored OTP and current status ───────────────────────────
    debugPrint('[OTP][DS] Step 1 → SELECT completion_otp, status FROM bookings WHERE id=?');
    final row = await _client
        .from('bookings')
        .select('completion_otp, status')
        .eq('id', bookingId)
        .single();

    final stored = row['completion_otp'] as String?;
    final currentStatus = row['status'] as String?;
    debugPrint('[OTP][DS] Step 1 result: completion_otp="$stored"  status="$currentStatus"');
    if (stored != null) {
      debugPrint('[OTP][DS]   stored codeUnits: ${stored.codeUnits}');
      debugPrint('[OTP][DS]   stored.trim()   : "${stored.trim()}"');
    } else {
      debugPrint('[OTP][DS]   ⚠️  completion_otp is NULL in DB — initiation may have failed');
    }

    // ── Step 2: Compare OTPs ──────────────────────────────────────────────────
    final storedTrimmed = stored?.trim() ?? '';
    final enteredTrimmed = otp.trim();
    final match = storedTrimmed == enteredTrimmed;
    debugPrint('[OTP][DS] Step 2 → compare:');
    debugPrint('[OTP][DS]   stored (trimmed) : "$storedTrimmed"');
    debugPrint('[OTP][DS]   entered (trimmed): "$enteredTrimmed"');
    debugPrint('[OTP][DS]   match            : $match');

    if (stored == null || !match) {
      debugPrint('[OTP][DS] Step 2 → MISMATCH or null — returning false');
      return false;
    }
    debugPrint('[OTP][DS] Step 2 → MATCH ✓');

    // ── Step 3: UPDATE + select to detect RLS-silenced 0-row updates ─────────
    // Without .select(), a blocked UPDATE returns HTTP 200 with [] — no error.
    // Adding .select() lets us check whether a row was actually modified.
    debugPrint('[OTP][DS] Step 3 → UPDATE bookings SET status=completed, otp_verified_at=now() WHERE id=?');
    final updated = await _client
        .from('bookings')
        .update({
          'status': 'completed',
          'otp_verified_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', bookingId)
        .select('id, status, otp_verified_at');

    debugPrint('[OTP][DS] Step 3 result: rowsReturned=${updated.length}  data=$updated');

    if (updated.isEmpty) {
      // UPDATE returned 0 rows. Two possible causes:
      //   (a) RLS policy blocks this vendor from updating this booking's status.
      //   (b) The booking id no longer exists (deleted between steps 1 and 3).
      // Check Supabase → Authentication → Policies → bookings table UPDATE policy.
      debugPrint('[OTP][DS] ⚠️  UPDATE affected 0 rows — RLS likely blocking the update');
      debugPrint('[OTP][DS]    Check: Supabase Dashboard → Table Editor → bookings → Policies → UPDATE');
      return false;
    }

    final newStatus = updated.first['status'] as String?;
    debugPrint('[OTP][DS] ✓ UPDATE succeeded — newStatus="$newStatus"');
    debugPrint('[OTP][DS] ══════════ verifyCompletionOtp() DONE → true ══════════');
    return true;
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
