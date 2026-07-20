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
    double taxAmount = 0.0,
    double surgeAmount = 0.0,
    String? surgeName,
    String? surgeType,
    double? surgeValue,
    String? preferredVendorId,
    double? preferredVendorFeeAmount,
    String paymentMethod = 'cash',
    String paymentStatus = 'pending',
  }) async {
    assert(items.isNotEmpty, 'Cannot create a booking with an empty cart');
    debugPrint('[DODO][Checkout] createCartBooking started — ${items.length} item(s)');
    debugPrint('[DODO][PV Assignment] createBooking preferredVendorId = $preferredVendorId');

    final customerId = await _getCustomerId();
    debugPrint('[DODO][Checkout] customer_id=$customerId');

    final subtotal = items.fold(0.0, (sum, i) => sum + i.totalPrice);
    final tax = taxAmount;
    final surge = surgeAmount;
    final pvFee = preferredVendorFeeAmount ?? 0.0;
    final gross = subtotal + surge + pvFee + tax;
    final totalAmount = (gross - discountAmount).clamp(0.0, double.infinity);
    final serviceDate = date.toIso8601String().substring(0, 10);

    debugPrint('[DODO][Checkout] subtotal=₹$subtotal  surge=₹$surge  tax=₹$tax  discount=₹$discountAmount  total=₹$totalAmount');
    debugPrint('[DODO][Checkout] Address object — id=${address.id}  lat=${address.latitude}  lng=${address.longitude}  full="${address.fullAddress}"');
    debugPrint('[DODO][Checkout] Booking payload — lat=${address.latitude}  lng=${address.longitude}');

    // ── INSERT bookings row ──────────────────────────────────────────────────
    // When a preferred vendor is selected, immediately assign the booking as
    // the admin "Confirm Assignment" flow would: status=assigned,
    // assignment_type=External Vendor, vendor_id=preferred vendor.
    // No admin intervention required — booking goes straight to Vendor App.
    final primaryItem = items.isNotEmpty ? items.first : null;
    final hasPv = preferredVendorId != null;
    final payload = {
      'customer_id': customerId,
      'service_date': serviceDate,
      'status': hasPv ? 'assigned' : 'pending',
      if (hasPv) 'assignment_type': 'External Vendor',
      'subtotal': subtotal,
      'discount_amount': discountAmount,
      'total_amount': totalAmount,
      'address': address.fullAddress,
      'notes': slot.label,
      'latitude': ?address.latitude,
      'longitude': ?address.longitude,
      'scheduled_time': slot.label,
      if (primaryItem != null) 'service_id': primaryItem.serviceId,
      'payment_method': paymentMethod,
      'payment_status': paymentStatus,
      if (surge > 0 && surgeName != null) 'surge_fee_name': surgeName,
      if (surge > 0 && surgeType != null) 'surge_fee_type': surgeType,
      if (surge > 0 && surgeValue != null) 'surge_fee_value': surgeValue,
      if (surge > 0) 'surge_fee_amount': surge,
      'preferred_vendor_id': ?preferredVendorId,
      // Set vendor_id = preferred vendor so booking skips admin assignment queue.
      'vendor_id': ?preferredVendorId,
      if (pvFee > 0) 'preferred_vendor_fee_amount': pvFee,
    };
    debugPrint('[DODO][PV Assignment] INSERT preferred_vendor_id = $preferredVendorId');
    debugPrint('[DODO][PV Assignment] INSERT vendor_id = $preferredVendorId');
    debugPrint('BOOKING LAT=${address.latitude}');
    debugPrint('BOOKING LNG=${address.longitude}');
    debugPrint('BOOKING PAYLOAD=$payload');
    final bookingData = await _client
        .from('bookings')
        .insert(payload)
        .select()
        .single();

    final bookingId = bookingData['id'] as String;
    debugPrint('[DODO][Checkout] Booking created: id=$bookingId');

    // ── INSERT booking_items (one row per cart item) ──────────────────────────
    // booking_items.service_id has a FK to catalog_nodes(id).
    // item.serviceId is the catalog_node UUID for all items.
    final rows = items
        .map((item) => {
              'booking_id': bookingId,
              'service_id': item.serviceId,
              'quantity': item.quantity,
              'unit_price': item.unitPrice,
              'total_price': item.totalPrice,
              if (item.parentNodeId != null)
                'catalog_parent_node_id': item.parentNodeId,
            })
        .toList();
    if (rows.isNotEmpty) {
      try {
        await _client.from('booking_items').insert(rows);
        debugPrint('[DODO][Checkout] ${rows.length} booking_item(s) inserted');
      } catch (e) {
        debugPrint('[DODO][Checkout] Warning: booking_items insert failed: $e');
      }
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

    // ── Preferred Vendor assignment notifications ──────────────────────────────
    // The booking is INSERTed with vendor_id already set, so the DB trigger
    // (trg_notify_customer_vendor_assigned) does not fire — it only fires on
    // UPDATE OF vendor_id. Send the same two notifications Admin sends on
    // "Confirm Assignment" → External Vendor.
    if (hasPv) {
      final bookingNumber =
          bookingData['booking_number']?.toString() ?? bookingId;
      try {
        await _client.from('notifications').insert({
          'user_type': 'vendor',
          'user_id': preferredVendorId,
          'title': 'New Booking Assigned',
          'message': 'You have been assigned booking #$bookingNumber.',
          'notification_type': 'vendor_assigned',
          'is_read': false,
          'entity_type': 'booking',
          'entity_id': bookingId,
        });
        debugPrint('[DODO][PV Assignment] Vendor notification sent → vendor=$preferredVendorId booking=$bookingNumber');
      } catch (e) {
        debugPrint('[DODO][PV Assignment] Warning: vendor notification failed (non-fatal): $e');
      }
      try {
        await _client.from('notifications').insert({
          'user_type': 'customer',
          'user_id': customerId,
          'title': 'Provider Assigned',
          'message': 'A service provider has been assigned to your booking.',
          'notification_type': 'vendor_assigned',
          'is_read': false,
          'entity_type': 'booking',
          'entity_id': bookingId,
        });
        debugPrint('[DODO][PV Assignment] Customer vendor_assigned notification sent → customer=$customerId');
      } catch (e) {
        debugPrint('[DODO][PV Assignment] Warning: customer vendor_assigned notification failed (non-fatal): $e');
      }
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
