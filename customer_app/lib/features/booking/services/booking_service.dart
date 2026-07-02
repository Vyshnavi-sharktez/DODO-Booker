import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/time_slot_model.dart';
import '../../../models/booking_model.dart';
import '../../../models/booking_item.dart';
import '../../../models/service_model.dart';
import '../../../models/address_model.dart';
import 'coupon_service.dart';

class BookingService {
  static const _phoneKey = 'dodo_auth_phone';
  final _client = Supabase.instance.client;
  final _couponService = CouponService();

  // ── Internal helpers ────────────────────────────────────────────────────────

  Future<String> _getCustomerId() async {
    final phone = (await SharedPreferences.getInstance()).getString(_phoneKey);
    if (phone == null) throw Exception('Not authenticated');
    debugPrint('[DODO][Booking] Looking up customer_id for phone=$phone');
    final row = await _client
        .from('customers')
        .select('id')
        .eq('phone', phone)
        .single();
    return row['id'] as String;
  }

  // ── Time slots (mock — no DB table yet) ─────────────────────────────────────

  Future<List<TimeSlotModel>> fetchAvailableSlots(String dateStr) async {
    debugPrint('[DODO][Booking] fetchAvailableSlots($dateStr) → mock');
    await Future.delayed(const Duration(milliseconds: 400));
    final slots = _buildSlots();

    // Same-day filtering: hide slots within 1-hour lead time of current time.
    final now = DateTime.now();
    final todayStr = '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    if (dateStr == todayStr) {
      final cutoff = now.add(const Duration(hours: 1));
      final cutoffMinutes = cutoff.hour * 60 + cutoff.minute;
      debugPrint(
        '[DODO][Booking] same-day filter: now=${now.hour}:${now.minute.toString().padLeft(2, '0')} '
        'cutoff=${cutoff.hour}:${cutoff.minute.toString().padLeft(2, '0')} '
        '($cutoffMinutes min)',
      );
      return slots
          .where((s) => _slotMinutes(s.label) >= cutoffMinutes)
          .toList();
    }

    return slots;
  }

  // ── Create booking ──────────────────────────────────────────────────────────

  Future<BookingModel> createBooking({
    required ServiceModel service,
    required AddressModel address,
    required DateTime date,
    required TimeSlotModel slot,
    String? couponId,
    double discountAmount = 0.0,
  }) async {
    debugPrint('[DODO][Booking] createBooking started');
    debugPrint('[DODO][Booking] Service: ${service.name} (id=${service.id})');
    debugPrint('[DODO][Booking] Address object — id=${address.id}  lat=${address.latitude}  lng=${address.longitude}  full="${address.fullAddress}"');
    debugPrint('[DODO][Booking] Date: ${date.toIso8601String().substring(0, 10)}');
    debugPrint('[DODO][Booking] Slot: ${slot.label}');

    final customerId = await _getCustomerId();
    debugPrint('[DODO][Booking] customer_id=$customerId');

    final subtotal = service.startingPrice;
    final tax = subtotal * 0.18;
    final grossAmount = subtotal + tax;
    final totalAmount = (grossAmount - discountAmount).clamp(0.0, double.infinity);
    final serviceDate = date.toIso8601String().substring(0, 10);

    if (couponId != null) {
      debugPrint('[DODO][Booking] Coupon: id=$couponId discount=₹${discountAmount.toStringAsFixed(2)}');
    }

    // ── Generate OTP before building payload ─────────────────────────────────
    final completionOtp = (100000 + Random().nextInt(900000)).toString();
    debugPrint('[OTP][Create] ══════════ OTP GENERATION ══════════');
    debugPrint('[OTP][Create] Generated OTP: $completionOtp  (len=${completionOtp.length})');

    // ── INSERT into bookings ─────────────────────────────────────────────────
    debugPrint('[DODO][Booking] Booking payload — lat=${address.latitude}  lng=${address.longitude}');
    debugPrint('[DODO][Booking] Inserting into bookings table');
    final payload = {
      'customer_id': customerId,
      'service_date': serviceDate,
      'status': 'pending',
      'subtotal': subtotal,
      'discount_amount': discountAmount,
      'total_amount': totalAmount,
      'address': address.fullAddress,
      'notes': '${service.name} · ${slot.label}',
      'latitude': ?address.latitude,
      'longitude': ?address.longitude,
      'completion_otp': completionOtp,
    };
    debugPrint('[OTP][Create] Payload keys    : ${payload.keys.toList()}');
    debugPrint('[OTP][Create] Payload otp val : ${payload['completion_otp']}');
    debugPrint('BOOKING LAT=${address.latitude}');
    debugPrint('BOOKING LNG=${address.longitude}');
    debugPrint('BOOKING PAYLOAD=$payload');

    final bookingData = await _client
        .from('bookings')
        .insert(payload)
        .select()
        .single();

    final bookingId = bookingData['id'] as String;
    debugPrint('[DODO][Booking] Booking created: id=$bookingId');

    // ── Verify OTP was written ────────────────────────────────────────────────
    final returnedOtp = bookingData['completion_otp'] as String?;
    debugPrint('[OTP][Create] Returned row keys: ${(bookingData as Map).keys.toList()}');
    debugPrint('[OTP][Create] Returned otp val : $returnedOtp');
    if (returnedOtp == null) {
      // The INSERT ignored completion_otp — almost always a column-level
      // permission issue (column added after the RLS policy was created).
      // Fall back to an explicit UPDATE using the same session.
      debugPrint('[OTP][Create] ⚠ OTP missing from INSERT result — attempting UPDATE fallback');
      try {
        await _client
            .from('bookings')
            .update({'completion_otp': completionOtp})
            .eq('id', bookingId);
        debugPrint('[OTP][Create] ✓ UPDATE fallback succeeded — OTP=$completionOtp');
      } catch (e) {
        debugPrint('[OTP][Create] ✗ UPDATE fallback failed: $e');
        debugPrint('[OTP][Create]   ACTION REQUIRED: grant the customer role '
            'INSERT/UPDATE on bookings.completion_otp in Supabase dashboard');
      }
    } else {
      debugPrint('[OTP][Create] ✓ OTP written via INSERT: $returnedOtp');
    }

    // ── INSERT into booking_items (non-fatal) ────────────────────────────────
    try {
      debugPrint('[DODO][Booking] Inserting booking_item: service_id=${service.id}');
      await _client.from('booking_items').insert({
        'booking_id': bookingId,
        'service_id': service.id,
        'quantity': 1,
        'unit_price': subtotal,
        'total_price': subtotal,
      });
      debugPrint('[DODO][Booking] booking_item inserted');
    } catch (e) {
      debugPrint('[DODO][Booking] Warning: booking_item insert failed (non-fatal): $e');
    }

    // ── Increment coupon used_count ──────────────────────────────────────────
    if (couponId != null) {
      try {
        await _couponService.incrementUsedCount(couponId);
      } catch (e) {
        debugPrint('[DODO][Booking] Warning: coupon used_count increment failed (non-fatal): $e');
      }
    }

    // ── Notify admin of new booking ──────────────────────────────────────────
    try {
      await _client.from('notifications').insert({
        'user_type': 'admin',
        'user_id': 'admin',
        'title': 'New Booking Received',
        'message': 'A new booking has been created.',
        'notification_type': 'booking_created',
        'is_read': false,
        'entity_type': 'booking',
        'entity_id': bookingId,
      });
    } catch (e) {
      debugPrint('[DODO][Booking] Warning: admin booking_created notification failed (non-fatal): $e');
    }

    // ── Notify customer of their new booking ─────────────────────────────────
    try {
      await _client.from('notifications').insert({
        'user_type': 'customer',
        'user_id': customerId,
        'title': 'Booking Created',
        'message': 'Your booking has been created successfully.',
        'notification_type': 'booking_created',
        'is_read': false,
        'entity_type': 'booking',
        'entity_id': bookingId,
      });
    } catch (e) {
      debugPrint('[DODO][Booking] Warning: customer booking_created notification failed (non-fatal): $e');
    }

    debugPrint('[DODO][Booking] Booking flow complete — id=$bookingId');

    return BookingModel(
      id: bookingId,
      serviceId: service.id,
      serviceName: service.name,
      addressId: address.id,
      addressLabel: address.fullAddress,
      scheduledDate: date,
      timeSlot: slot.label,
      baseAmount: subtotal,
      taxAmount: tax,
      totalAmount: totalAmount,
      status: (bookingData['status'] as String?) ?? 'pending',
      createdAt: bookingData['created_at'] != null
          ? DateTime.parse(bookingData['created_at'] as String)
          : DateTime.now(),
    );
  }

  // ── Rebook (create new booking from previous items) ─────────────────────────

  Future<BookingModel> rebookBooking({
    required List<BookingItem> items,
    required AddressModel address,
    required DateTime date,
    required TimeSlotModel slot,
    String? couponId,
    double discountAmount = 0.0,
  }) async {
    debugPrint('[DODO][Booking] rebookBooking started — ${items.length} items');

    final customerId = await _getCustomerId();

    final subtotal =
        items.fold(0.0, (sum, i) => sum + i.unitPrice * i.quantity);
    final tax = subtotal * 0.18;
    final grossAmount = subtotal + tax;
    final totalAmount =
        (grossAmount - discountAmount).clamp(0.0, double.infinity);
    final serviceDate = date.toIso8601String().substring(0, 10);
    final firstItemName =
        items.isNotEmpty ? items.first.serviceName : 'Service';

    final completionOtp = (100000 + Random().nextInt(900000)).toString();

    final payload = {
      'customer_id': customerId,
      'service_date': serviceDate,
      'status': 'pending',
      'subtotal': subtotal,
      'discount_amount': discountAmount,
      'total_amount': totalAmount,
      'address': address.fullAddress,
      'notes': '$firstItemName · ${slot.label}',
      'latitude': ?address.latitude,
      'longitude': ?address.longitude,
      'completion_otp': completionOtp,
    };

    final bookingData =
        await _client.from('bookings').insert(payload).select().single();
    final bookingId = bookingData['id'] as String;
    debugPrint('[DODO][Booking] Rebook booking created: id=$bookingId');

    // Insert all rebooked service items
    if (items.isNotEmpty) {
      try {
        await _client.from('booking_items').insert(
          items
              .map((item) => {
                    'booking_id': bookingId,
                    'service_id': item.serviceId,
                    'quantity': item.quantity,
                    'unit_price': item.unitPrice,
                    'total_price': item.unitPrice * item.quantity,
                  })
              .toList(),
        );
      } catch (e) {
        debugPrint('[DODO][Booking] Warning: rebook booking_items insert failed (non-fatal): $e');
      }
    }

    // OTP fallback in case INSERT didn't persist it
    final returnedOtp = bookingData['completion_otp'] as String?;
    if (returnedOtp == null) {
      try {
        await _client
            .from('bookings')
            .update({'completion_otp': completionOtp})
            .eq('id', bookingId);
      } catch (_) {}
    }

    if (couponId != null) {
      try {
        await _couponService.incrementUsedCount(couponId);
      } catch (e) {
        debugPrint('[DODO][Booking] Warning: coupon used_count increment failed (non-fatal): $e');
      }
    }

    try {
      await _client.from('notifications').insert({
        'user_type': 'admin',
        'user_id': 'admin',
        'title': 'New Booking Received',
        'message': 'A new booking has been created.',
        'notification_type': 'booking_created',
        'is_read': false,
        'entity_type': 'booking',
        'entity_id': bookingId,
      });
    } catch (e) {
      debugPrint('[DODO][Booking] Warning: admin notification failed (non-fatal): $e');
    }

    try {
      await _client.from('notifications').insert({
        'user_type': 'customer',
        'user_id': customerId,
        'title': 'Booking Created',
        'message': 'Your booking has been created successfully.',
        'notification_type': 'booking_created',
        'is_read': false,
        'entity_type': 'booking',
        'entity_id': bookingId,
      });
    } catch (e) {
      debugPrint('[DODO][Booking] Warning: customer notification failed (non-fatal): $e');
    }

    debugPrint('[DODO][Booking] Rebook flow complete — id=$bookingId');

    return BookingModel(
      id: bookingId,
      serviceId: items.isNotEmpty ? items.first.serviceId : '',
      serviceName: firstItemName,
      addressId: address.id,
      addressLabel: address.fullAddress,
      scheduledDate: date,
      timeSlot: slot.label,
      baseAmount: subtotal,
      taxAmount: tax,
      totalAmount: totalAmount,
      status: 'pending',
      createdAt: bookingData['created_at'] != null
          ? DateTime.parse(bookingData['created_at'] as String)
          : DateTime.now(),
    );
  }
}

// ── Slot builder ───────────────────────────────────────────────────────────────

List<TimeSlotModel> _buildSlots() {
  final raw = [
    // Morning
    ('ts_m1', '07:00 AM', SlotPeriod.morning),
    ('ts_m2', '08:00 AM', SlotPeriod.morning),
    ('ts_m3', '09:00 AM', SlotPeriod.morning),
    ('ts_m4', '10:00 AM', SlotPeriod.morning),
    ('ts_m5', '11:00 AM', SlotPeriod.morning),
    // Afternoon
    ('ts_a1', '12:00 PM', SlotPeriod.afternoon),
    ('ts_a2', '01:00 PM', SlotPeriod.afternoon),
    ('ts_a3', '02:00 PM', SlotPeriod.afternoon),
    ('ts_a4', '03:00 PM', SlotPeriod.afternoon),
    ('ts_a5', '04:00 PM', SlotPeriod.afternoon),
    // Evening
    ('ts_e1', '05:00 PM', SlotPeriod.evening),
    ('ts_e2', '06:00 PM', SlotPeriod.evening),
    ('ts_e3', '07:00 PM', SlotPeriod.evening),
    ('ts_e4', '08:00 PM', SlotPeriod.evening),
    ('ts_e5', '09:00 PM', SlotPeriod.evening),
  ];

  return List.generate(raw.length, (i) {
    final (id, label, period) = raw[i];
    return TimeSlotModel(
      id: id,
      label: label,
      period: period,
      isAvailable: true,
    );
  });
}

/// Parses a slot label ("07:00 AM" / "01:00 PM") → minutes since midnight.
int _slotMinutes(String label) {
  final parts = label.split(' ');       // ["07:00", "AM"]
  final timeParts = parts[0].split(':'); // ["07", "00"]
  var hour = int.parse(timeParts[0]);
  final minute = int.parse(timeParts[1]);
  final isPm = parts[1] == 'PM';
  if (isPm && hour != 12) hour += 12;
  if (!isPm && hour == 12) hour = 0;   // 12:00 AM → midnight
  return hour * 60 + minute;
}
