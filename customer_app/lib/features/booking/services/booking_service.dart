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
import '../../../features/tax/services/tax_service.dart';
import 'coupon_service.dart';

class BookingService {
  static const _phoneKey = 'dodo_auth_phone';
  final _client = Supabase.instance.client;
  final _couponService = CouponService();
  final _taxService = TaxService();

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
    String serviceId, {
    String? parentNodeId,
  }) async {
    debugPrint('[DODO][Slots] ══════════ fetchAvailableSlots ══════════');
    debugPrint('[DODO][Slots] date=$dateStr  serviceId="$serviceId"  parentNodeId=$parentNodeId');

    // ── 0. Try relationship/node-scoped scheduling config ───────────────────
    // Call the RPC even when parentNodeId is null: the function handles null
    // p_parent_id by checking node-scoped configs on the service itself (step B
    // in the RPC's resolution loop). Relationship-scoped configs still require a
    // non-null parentNodeId to match the correct edge.
    if (serviceId.isNotEmpty) {
      try {
        final scopedResult = await _client.rpc(
          'resolve_catalog_module_config',
          params: {
            'p_module': 'scheduling',
            'p_service_id': serviceId,
            'p_parent_id': parentNodeId,
          },
        );
        if (scopedResult != null && scopedResult is Map) {
          final scopedCfg = Map<String, dynamic>.from(scopedResult as Map);
          debugPrint('[DODO][Slots] CONFIG SOURCE: scoped (resolve_catalog_module_config)');
          debugPrint('[DODO][Slots] Scoped config raw: $scopedCfg');
          final isEnabled = (scopedCfg['is_enabled'] as bool?) ?? true;
          if (!isEnabled) {
            debugPrint('[DODO][Slots] → returning [] (scoped scheduling disabled)');
            return [];
          }
          // await so that any exception from _buildSlots is caught by this
          // try/catch rather than propagating as an unhandled Future rejection.
          return await _buildSlots(dateStr, serviceId, scopedCfg,
              configSource: 'scoped');
        } else {
          debugPrint('[DODO][Slots] RPC returned null — no scoped config, falling through to global');
        }
      } catch (e) {
        debugPrint('[DODO][Slots] Warning: scoped scheduling RPC failed, falling through: $e');
      }
    }

    // ── 1. Fetch global scheduling config ───────────────────────────────────
    // Always loaded first so the master switch can be checked even when the
    // service has no service_scheduling row of its own.
    Map<String, dynamic>? globalCfg;
    try {
      final globalRows =
          await _client.from('global_scheduling').select().limit(1);
      if (globalRows.isNotEmpty) {
        globalCfg = globalRows.first as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[DODO][Slots] Warning: could not load global_scheduling: $e');
    }

    final globalMasterOn = (globalCfg?['is_enabled'] as bool?) ?? false;
    debugPrint('[DODO][Slots] globalMasterOn=$globalMasterOn');

    // ── 2. Resolve which schedule config to use ──────────────────────────────
    // Priority:
    //   1. Global master ON  → all services use global (no service row needed)
    //   2. Global master OFF + service opted in → this service uses global
    //   3. Global master OFF + not opted in     → service's own config
    //
    // `isEnabled` is tracked separately: global_scheduling.is_enabled is the
    // master switch, not a per-service scheduling-active flag.
    Map<String, dynamic>? scheduleCfg;
    bool isEnabled;

    if (globalMasterOn) {
      // Master ON → use global for every service without querying service_scheduling.
      debugPrint('[DODO][Slots] CONFIG SOURCE: global (master override)');
      scheduleCfg = globalCfg;
      isEnabled = true;
    } else {
      // Master OFF → load the service's own row, then check per-service opt-in.
      Map<String, dynamic>? serviceCfg;
      if (serviceId.isNotEmpty) {
        try {
          final rows = await _client
              .from('service_scheduling')
              .select()
              .eq('service_id', serviceId);
          debugPrint('[DODO][Slots] Supabase returned ${rows.length} row(s) for service_id="$serviceId"');
          if (rows.isNotEmpty) {
            serviceCfg = rows.first as Map<String, dynamic>;
            debugPrint('[DODO][Slots] Raw serviceCfg: $serviceCfg');
          } else {
            debugPrint('[DODO][Slots] ⚠ No row found in service_scheduling for service_id="$serviceId"');
          }
        } catch (e) {
          debugPrint('[DODO][Slots] ✗ Supabase query failed: $e');
        }
      } else {
        debugPrint('[DODO][Slots] ⚠ serviceId is empty — skipping DB query');
      }

      isEnabled = (serviceCfg?['is_enabled'] as bool?) ?? true;
      final serviceOptedIn =
          (serviceCfg?['use_global_schedule'] as bool?) ?? false;
      debugPrint('[DODO][Slots] serviceOptedIn=$serviceOptedIn  isEnabled=$isEnabled');

      if (serviceOptedIn && globalCfg != null) {
        debugPrint('[DODO][Slots] CONFIG SOURCE: global (per-service opt-in)');
        scheduleCfg = globalCfg;
      } else {
        debugPrint('[DODO][Slots] CONFIG SOURCE: service-specific (service_scheduling table)');
        scheduleCfg = serviceCfg;
      }
    }

    if (scheduleCfg == null) {
      debugPrint('[DODO][Slots] → returning [] (no scheduling config found)');
      return [];
    }

    debugPrint('[DODO][Slots] is_enabled=$isEnabled');
    if (!isEnabled) {
      debugPrint('[DODO][Slots] → returning [] (scheduling disabled)');
      return [];
    }

    return await _buildSlots(dateStr, serviceId, scheduleCfg!);
  }

  /// Shared slot-generation logic used by both scoped and fallback paths.
  Future<List<TimeSlotModel>> _buildSlots(
      String dateStr, String serviceId, Map<String, dynamic> cfg,
      {String configSource = 'unknown'}) async {
    debugPrint('[DODO][Slots] ── _buildSlots: configSource=$configSource');

    // ── Check working day ────────────────────────────────────────────────────
    final date = DateTime.parse(dateStr);
    final dayOfWeek = date.weekday == 7 ? 0 : date.weekday;
    final workingDays = (cfg['working_days'] as List?)
            ?.map((e) => (e as num).toInt())
            .toList() ??
        [1, 2, 3, 4, 5];
    debugPrint('[DODO][Slots] STAGE working-day: date=$dateStr  '
        'dart.weekday=${date.weekday}  mapped=$dayOfWeek  '
        'working_days=$workingDays  → pass=${workingDays.contains(dayOfWeek)}');
    if (!workingDays.contains(dayOfWeek)) {
      debugPrint('[DODO][Slots] → returning [] ($dateStr is not a working day)');
      return [];
    }

    // ── Read slot list and max bookings ──────────────────────────────────────
    // Trim each label to handle slots stored with surrounding spaces
    // (e.g. when admin enters "09:00 AM, 10:00 AM" and split(',') is used).
    final rawLabels = (cfg['slots'] as List?)?.cast<dynamic>().toList() ?? [];
    debugPrint('[DODO][Slots] STAGE parse-slots: raw=${rawLabels.length} labels=$rawLabels');
    final labels = rawLabels
        .map((e) => (e as String).trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final maxBookings = (cfg['max_bookings_per_slot'] as num?)?.toInt() ?? 5;
    debugPrint('[DODO][Slots] STAGE parse-slots: after trim=${labels.length} labels=$labels  maxBookings=$maxBookings');

    // ── Load existing booking counts for this service+date ───────────────────
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

    // ── Same-day lead-time filter ────────────────────────────────────────────
    final now = DateTime.now();
    final todayStr = '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final isToday = dateStr == todayStr;
    final cutoffNow = now.add(const Duration(hours: 1));
    final cutoffMin = isToday ? cutoffNow.hour * 60 + cutoffNow.minute : 0;
    debugPrint('[DODO][Slots] isToday=$isToday  '
        'now=${now.hour}:${now.minute.toString().padLeft(2, '0')}  '
        'cutoffMin=$cutoffMin (${cutoffMin ~/ 60}:${(cutoffMin % 60).toString().padLeft(2, '0')})');

    // ── Build TimeSlotModel list ─────────────────────────────────────────────
    final result = <TimeSlotModel>[];
    for (final label in labels) {
      final slotMin = _labelToMinutes(label);
      if (isToday && slotMin < cutoffMin) {
        debugPrint(
            '[DODO][Slots]   "$label" ($slotMin min) — FILTERED (before cutoff $cutoffMin)');
        continue;
      }
      final bookedCount = capacityMap[label] ?? 0;
      final isAvailable = bookedCount < maxBookings;
      debugPrint(
          '[DODO][Slots]   "$label" ($slotMin min) — KEPT  booked=$bookedCount/$maxBookings  available=$isAvailable');
      result.add(TimeSlotModel(
        id: 'ts_${label.replaceAll(RegExp(r'[^0-9]'), '')}',
        label: label,
        period: _periodFor(slotMin),
        isAvailable: isAvailable,
      ));
    }
    final filteredByTime = labels.length - result.length;
    debugPrint('[DODO][Slots] STAGE summary: '
        'raw=${rawLabels.length}  '
        'parsed=${labels.length}  '
        'filtered-by-time=$filteredByTime  '
        'returned=${result.length}');
    if (result.isEmpty && labels.isNotEmpty) {
      final cutoffHH = cutoffMin ~/ 60;
      final cutoffMM = (cutoffMin % 60).toString().padLeft(2, '0');
      debugPrint('[DODO][Slots] ⚠ All ${labels.length} slot(s) were filtered.'
          '  isToday=$isToday  cutoffMin=$cutoffMin ($cutoffHH:$cutoffMM)');
    }
    debugPrint('[DODO][Slots] → returning ${result.length} slot(s)');
    return result;
  }

  // ── Create booking ──────────────────────────────────────────────────────────

  Future<double> _resolveTaxAmount(
      double subtotal, String serviceId, String? parentNodeId) async {
    final taxSettings =
        await _taxService.getResolvedTaxForService(serviceId, parentNodeId);
    return taxSettings.computeTax(subtotal);
  }

  Future<BookingModel> createBooking({
    required CatalogNodeModel service,
    required AddressModel address,
    required DateTime date,
    required TimeSlotModel slot,
    String? couponId,
    double discountAmount = 0.0,
    double priceAdjustment = 0.0,
    List<SelectedAddon> selectedAddons = const [],
    String? parentNodeId,
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
    final tax = await _resolveTaxAmount(subtotal, service.id, parentNodeId);
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
      'service_id': service.id,
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
    // booking_items.service_id FK → catalog_nodes(id). Use service.id directly.
    try {
      debugPrint('[DODO][Booking] Inserting booking_item: service_id=${service.id} unit_price=$subtotal parentNodeId=$parentNodeId');
      await _client.from('booking_items').insert({
        'booking_id': bookingId,
        'service_id': service.id,
        'quantity': 1,
        'unit_price': subtotal,
        'total_price': subtotal,
        if (parentNodeId != null) 'catalog_parent_node_id': parentNodeId,
      });
      debugPrint('[DODO][Booking] booking_item inserted');
    } catch (e) {
      debugPrint('[DODO][Booking] Warning: booking_item insert failed: $e');
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
    String? parentNodeId,
  }) async {
    debugPrint('[DODO][Booking] rebookBooking started — ${items.length} items  parentNodeId=$parentNodeId');

    final customerId = await _getCustomerId();

    final subtotal =
        items.fold(0.0, (sum, i) => sum + i.unitPrice * i.quantity);
    final firstServiceId = items.isNotEmpty ? items.first.serviceId : '';
    final tax = await _resolveTaxAmount(subtotal, firstServiceId, parentNodeId);
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
      'scheduled_time': slot.label,
      if (firstServiceId.isNotEmpty) 'service_id': firstServiceId,
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
                    if (item.catalogParentNodeId != null)
                      'catalog_parent_node_id': item.catalogParentNodeId,
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

/// Parses a slot label to minutes since midnight.
/// Accepts both "07:00 AM" and "07:00AM" (with or without space before AM/PM).
int _labelToMinutes(String label) {
  final upper = label.toUpperCase().replaceAll(' ', '');
  final isPm = upper.endsWith('PM');
  final timePart = upper.replaceAll('AM', '').replaceAll('PM', '');
  final timeParts = timePart.split(':');
  var hour = int.parse(timeParts[0]);
  final minute = int.parse(timeParts[1]);
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
