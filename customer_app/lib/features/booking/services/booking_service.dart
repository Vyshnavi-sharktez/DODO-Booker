import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/time_slot_model.dart';
import '../../../models/booking_model.dart';
import '../../../models/booking_item.dart';
import '../../../features/catalog/models/catalog_node_model.dart';
import '../../../models/address_model.dart';
import '../../../models/addon_model.dart';
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

  // ── Time slots (dynamic from service_scheduling table) ──────────────────────

  Future<List<TimeSlotModel>> fetchAvailableSlots(
    String dateStr,
    String serviceId,
  ) async {
    debugPrint('[DODO][Slots] ══════════ fetchAvailableSlots ══════════');
    debugPrint('[DODO][Slots] date=$dateStr  serviceId="$serviceId"');

    // ── 1. Load scheduling config ────────────────────────────────────────────
    Map<String, dynamic>? cfg;
    if (serviceId.isNotEmpty) {
      try {
        final rows = await _client
            .from('service_scheduling')
            .select()
            .eq('service_id', serviceId);
        debugPrint('[DODO][Slots] Supabase returned ${rows.length} row(s) for service_id="$serviceId"');
        if (rows.isNotEmpty) {
          cfg = rows.first;
          debugPrint('[DODO][Slots] Raw cfg: $cfg');
        } else {
          debugPrint('[DODO][Slots] ⚠ No row found in service_scheduling for service_id="$serviceId"');
        }
      } catch (e) {
        debugPrint('[DODO][Slots] ✗ Supabase query failed: $e');
      }
    } else {
      debugPrint('[DODO][Slots] ⚠ serviceId is empty — skipping DB query');
    }

    if (cfg == null) {
      debugPrint('[DODO][Slots] → returning [] (no scheduling config found)');
      return [];
    }

    final isEnabled = (cfg['is_enabled'] as bool?) ?? true;
    debugPrint('[DODO][Slots] is_enabled=$isEnabled');
    if (!isEnabled) {
      debugPrint('[DODO][Slots] → returning [] (scheduling disabled)');
      return [];
    }

    // ── 2. Check working day ─────────────────────────────────────────────────
    final date = DateTime.parse(dateStr);
    // Dart: Mon=1 … Sun=7 → convert to Sun=0 … Sat=6
    final dayOfWeek = date.weekday == 7 ? 0 : date.weekday;
    final workingDays = (cfg['working_days'] as List?)
        ?.map((e) => (e as num).toInt())
        .toList() ?? [1, 2, 3, 4, 5];
    debugPrint('[DODO][Slots] date=$dateStr  dart.weekday=${date.weekday}  '
        'mapped dayOfWeek=$dayOfWeek  working_days=$workingDays');
    if (!workingDays.contains(dayOfWeek)) {
      debugPrint('[DODO][Slots] → returning [] ($dateStr is not a working day)');
      return [];
    }

    // ── 3. Read manual slot list and max bookings ────────────────────────────
    final labels = (cfg['slots'] as List?)
        ?.map((e) => e as String)
        .toList() ?? <String>[];
    final maxBookings = (cfg['max_bookings_per_slot'] as num?)?.toInt() ?? 5;
    debugPrint('[DODO][Slots] slots from DB: $labels  maxBookings=$maxBookings');

    // ── 5. Load existing booking counts for this service+date ───────────────
    final capacityMap = <String, int>{};
    if (serviceId.isNotEmpty) {
      try {
        final rows = await _client
            .from('bookings')
            .select('scheduled_time, status')
            .eq('service_date', dateStr)
            .eq('service_id', serviceId)
            .not('scheduled_time', 'is', null);
        for (final row in rows) {
          final status = (row['status'] as String?) ?? '';
          if (status == 'cancelled' || status == 'rejected') continue;
          final t = row['scheduled_time'] as String?;
          if (t != null) capacityMap[t] = (capacityMap[t] ?? 0) + 1;
        }
        debugPrint('[DODO][Slots] Capacity map: $capacityMap');
      } catch (e) {
        debugPrint('[DODO][Slots] Warning: could not load booking counts: $e');
      }
    }

    // ── 6. Same-day lead-time filter ─────────────────────────────────────────
    final now = DateTime.now();
    final todayStr = '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final isToday = dateStr == todayStr;
    final cutoffNow = now.add(const Duration(hours: 1));
    final cutoffMin = isToday ? cutoffNow.hour * 60 + cutoffNow.minute : 0;
    debugPrint('[DODO][Slots] isToday=$isToday  '
        'now=${now.hour}:${now.minute.toString().padLeft(2,'0')}  '
        'cutoffMin=$cutoffMin (${cutoffMin ~/ 60}:${(cutoffMin % 60).toString().padLeft(2,'0')})');

    // ── 7. Build TimeSlotModel list ──────────────────────────────────────────
    // Today: remove past slots entirely. Future: keep all, mark capacity.
    final result = <TimeSlotModel>[];
    for (final label in labels) {
      final slotMin = _labelToMinutes(label);
      if (isToday && slotMin < cutoffMin) {
        debugPrint('[DODO][Slots]   "$label" ($slotMin min) — FILTERED (before cutoff $cutoffMin)');
        continue;
      }
      final bookedCount = capacityMap[label] ?? 0;
      final isAvailable = bookedCount < maxBookings;
      debugPrint('[DODO][Slots]   "$label" ($slotMin min) — KEPT  booked=$bookedCount/$maxBookings  available=$isAvailable');
      result.add(TimeSlotModel(
        id: 'ts_${label.replaceAll(RegExp(r'[^0-9]'), '')}',
        label: label,
        period: _periodFor(slotMin),
        isAvailable: isAvailable,
      ));
    }
    debugPrint('[DODO][Slots] → returning ${result.length} slot(s)');
    return result;
  }

  // ── Create booking ──────────────────────────────────────────────────────────

  Future<BookingModel> createBooking({
    required CatalogNodeModel service,
    required AddressModel address,
    required DateTime date,
    required TimeSlotModel slot,
    String? couponId,
    double discountAmount = 0.0,
    double priceAdjustment = 0.0,
    List<SelectedAddon> selectedAddons = const [],
  }) async {
    debugPrint('[DODO][Booking] createBooking started');
    debugPrint('[DODO][Booking] Service: ${service.name} (id=${service.id})');
    debugPrint('[DODO][Booking] Address object — id=${address.id}  lat=${address.latitude}  lng=${address.longitude}  full="${address.fullAddress}"');
    debugPrint('[DODO][Booking] Date: ${date.toIso8601String().substring(0, 10)}');
    debugPrint('[DODO][Booking] Slot: ${slot.label}');

    final customerId = await _getCustomerId();
    debugPrint('[DODO][Booking] customer_id=$customerId');

    final addonsTotal = totalAddonsPrice(selectedAddons);
    final subtotal = (service.basePrice ?? 0.0) + priceAdjustment + addonsTotal;
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
      'scheduled_time': slot.label,
      if (service.legacyId != null) 'service_id': service.legacyId,
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

    // ── INSERT into booking_items ─────────────────────────────────────────────
    // booking_items.service_id has a FK to services(id).
    // Migrated catalog nodes (legacy_type='service') reuse the original service
    // UUID as both their id AND legacy_id, so the FK is always satisfied.
    // Brand-new catalog nodes (legacy_id == null) have no services row yet;
    // they must be excluded until the schema adds a node_id FK path.
    final bookingServiceId = service.legacyId;
    if (bookingServiceId != null) {
      try {
        debugPrint('[DODO][Booking] Inserting booking_item: service_id=$bookingServiceId unit_price=$subtotal');
        await _client.from('booking_items').insert({
          'booking_id': bookingId,
          'service_id': bookingServiceId,
          'quantity': 1,
          'unit_price': subtotal,
          'total_price': subtotal,
        });
        debugPrint('[DODO][Booking] booking_item inserted');
      } catch (e) {
        debugPrint('[DODO][Booking] Warning: booking_item insert failed: $e');
      }
    } else {
      debugPrint('[DODO][Booking] Skipping booking_item: node ${service.id} '
          'is a new catalog node with no services row (legacy_id = null)');
    }

    // ── INSERT into booking_addons (non-fatal) ───────────────────────────────
    if (selectedAddons.isNotEmpty) {
      try {
        debugPrint('[DODO][Booking] Inserting ${selectedAddons.length} booking_addon(s)');
        await _client.from('booking_addons').insert(
          selectedAddons
              .map((a) => {
                    'booking_id': bookingId,
                    'addon_id': a.addonId,
                    'addon_name': a.addonName,
                    'addon_price': a.addonPrice,
                  })
              .toList(),
        );
        debugPrint('[DODO][Booking] booking_addons inserted');
      } catch (e) {
        debugPrint('[DODO][Booking] Warning: booking_addons insert failed (non-fatal): $e');
      }
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

    final rebookServiceId =
        items.isNotEmpty && items.first.serviceId.isNotEmpty ? items.first.serviceId : null;
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
      'scheduled_time': slot.label,
      if (rebookServiceId != null) 'service_id': rebookServiceId,
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

// ── Slot helpers ───────────────────────────────────────────────────────────────

/// "07:00 AM" / "01:00 PM" → minutes since midnight.
int _labelToMinutes(String label) {
  final parts = label.split(' ');
  final timeParts = parts[0].split(':');
  var hour = int.parse(timeParts[0]);
  final minute = int.parse(timeParts[1]);
  final isPm = parts[1] == 'PM';
  if (isPm && hour != 12) hour += 12;
  if (!isPm && hour == 12) hour = 0;
  return hour * 60 + minute;
}

/// Maps minutes-since-midnight to a SlotPeriod bucket.
SlotPeriod _periodFor(int totalMinutes) {
  if (totalMinutes < 12 * 60) return SlotPeriod.morning;
  if (totalMinutes < 17 * 60) return SlotPeriod.afternoon;
  return SlotPeriod.evening;
}
