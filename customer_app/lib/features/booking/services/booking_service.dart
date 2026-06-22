import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/time_slot_model.dart';
import '../../../models/booking_model.dart';
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
    final hash = dateStr.codeUnits.fold(0, (a, b) => a + b);
    return _buildSlots(hash);
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
    };
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
}

// ── Slot builder ───────────────────────────────────────────────────────────────

List<TimeSlotModel> _buildSlots(int hash) {
  final unavailableIndices = {hash % 3, (hash + 5) % 7, (hash + 11) % 15};

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
      isAvailable: !unavailableIndices.contains(i),
    );
  });
}
