import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/time_slot_model.dart';
import '../../../models/booking_model.dart';
import '../../../models/address_model.dart';
import '../models/cart_item.dart';
import '../../booking/services/coupon_service.dart';

class CheckoutService {
  static const _phoneKey = 'dodo_auth_phone';
  final _client = Supabase.instance.client;
  final _couponService = CouponService();

  Future<String> _getCustomerId() async {
    final phone = (await SharedPreferences.getInstance()).getString(_phoneKey);
    if (phone == null) throw Exception('Not authenticated');
    final row = await _client
        .from('customers')
        .select('id')
        .eq('phone', phone)
        .single();
    return row['id'] as String;
  }

  Future<BookingModel> createCartBooking({
    required List<CartItem> items,
    required AddressModel address,
    required DateTime date,
    required TimeSlotModel slot,
    String? couponId,
    double discountAmount = 0.0,
  }) async {
    assert(items.isNotEmpty, 'Cannot create a booking with an empty cart');
    debugPrint('[DODO][Checkout] createCartBooking started — ${items.length} item(s)');

    final customerId = await _getCustomerId();
    debugPrint('[DODO][Checkout] customer_id=$customerId');

    final subtotal = items.fold(0.0, (sum, i) => sum + i.totalPrice);
    final tax = subtotal * 0.18;
    final gross = subtotal + tax;
    final totalAmount = (gross - discountAmount).clamp(0.0, double.infinity);
    final serviceDate = date.toIso8601String().substring(0, 10);

    debugPrint('[DODO][Checkout] subtotal=₹$subtotal  tax=₹$tax  discount=₹$discountAmount  total=₹$totalAmount');

    // ── INSERT bookings row ──────────────────────────────────────────────────
    final bookingData = await _client
        .from('bookings')
        .insert({
          'customer_id': customerId,
          'service_date': serviceDate,
          'status': 'pending',
          'subtotal': subtotal,
          'discount_amount': discountAmount,
          'total_amount': totalAmount,
          'address': address.fullAddress,
          'notes': slot.label,
        })
        .select()
        .single();

    final bookingId = bookingData['id'] as String;
    debugPrint('[DODO][Checkout] Booking created: id=$bookingId');

    // ── INSERT booking_items (one row per cart item) ──────────────────────────
    try {
      final rows = items
          .map((item) => {
                'booking_id': bookingId,
                'service_id': item.serviceId,
                'quantity': item.quantity,
                'unit_price': item.unitPrice,
                'total_price': item.totalPrice,
              })
          .toList();
      await _client.from('booking_items').insert(rows);
      debugPrint('[DODO][Checkout] ${rows.length} booking_item(s) inserted');
    } catch (e) {
      debugPrint('[DODO][Checkout] Warning: booking_items insert failed (non-fatal): $e');
    }

    // ── Increment coupon used_count ───────────────────────────────────────────
    if (couponId != null) {
      try {
        await _couponService.incrementUsedCount(couponId);
      } catch (e) {
        debugPrint('[DODO][Checkout] Warning: coupon used_count increment failed (non-fatal): $e');
      }
    }

    // ── Admin notification ────────────────────────────────────────────────────
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
      debugPrint('[DODO][Checkout] Warning: admin notification failed (non-fatal): $e');
    }

    // ── Customer notification ─────────────────────────────────────────────────
    try {
      await _client.from('notifications').insert({
        'user_type': 'customer',
        'user_id': customerId,
        'title': 'Booking Confirmed',
        'message': 'Your booking has been placed successfully.',
        'notification_type': 'booking_created',
        'is_read': false,
        'entity_type': 'booking',
        'entity_id': bookingId,
      });
    } catch (e) {
      debugPrint('[DODO][Checkout] Warning: customer notification failed (non-fatal): $e');
    }

    debugPrint('[DODO][Checkout] Flow complete — id=$bookingId');

    final firstName = items.first.serviceName;
    final serviceName =
        items.length == 1 ? firstName : '$firstName + ${items.length - 1} more';

    return BookingModel(
      id: bookingId,
      serviceId: items.first.serviceId,
      serviceName: serviceName,
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
