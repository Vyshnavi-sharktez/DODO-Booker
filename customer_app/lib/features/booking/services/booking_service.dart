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
import '../../../features/amc/models/amc_plan_model.dart';
import '../../../features/amc/services/amc_visit_number_service.dart';
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
    String? vendorId,
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
              configSource: 'scoped', vendorId: vendorId);
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

    return await _buildSlots(dateStr, serviceId, scheduleCfg!, vendorId: vendorId);
  }

  /// Shared slot-generation logic used by both scoped and fallback paths.
  Future<List<TimeSlotModel>> _buildSlots(
      String dateStr, String serviceId, Map<String, dynamic> cfg,
      {String configSource = 'unknown', String? vendorId}) async {
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
    // When vendorId is set, only count that vendor's bookings so capacity is
    // vendor-specific (lets customers see slots the chosen vendor can still take).
    final capacityMap = <String, int>{};
    if (serviceId.isNotEmpty) {
      try {
        final baseQ = _client
            .from('bookings')
            .select('scheduled_time, status')
            .eq('service_date', dateStr)
            .eq('service_id', serviceId)
            .not('scheduled_time', 'is', null);
        final rows = vendorId != null
            ? await baseQ.eq('preferred_vendor_id', vendorId)
            : await baseQ;
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

    // ── Vendor busy check ────────────────────────────────────────────────────
    // Uses the get_vendor_busy_status SECURITY DEFINER RPC — the customer app
    // must not read other customers' bookings directly via the bookings table.
    int vendorBusyUntilMin = 0;
    if (vendorId != null && isToday) {
      final nowMin = now.hour * 60 + now.minute;
      try {
        final result = await _client.rpc('get_vendor_busy_status', params: {
          'p_vendor_id': vendorId,
          'p_service_date': dateStr,
          'p_now_minutes': nowMin,
        });
        final rows = result as List;
        if (rows.isNotEmpty) {
          final row = rows.first as Map<String, dynamic>;
          final isBusy = row['is_busy'] as bool? ?? false;
          final busyUntilMin = (row['busy_until_minutes'] as num?)?.toInt();
          if (isBusy && busyUntilMin != null) {
            vendorBusyUntilMin = busyUntilMin;
            debugPrint('[DODO][Slots] Vendor $vendorId busy until approx. '
                '${vendorBusyUntilMin ~/ 60}:${(vendorBusyUntilMin % 60).toString().padLeft(2, '0')}');
          }
        }
      } catch (e) {
        debugPrint('[DODO][Slots] Warning: vendor busy check failed: $e');
      }
    }

    // ── Build TimeSlotModel list ─────────────────────────────────────────────
    final result = <TimeSlotModel>[];
    for (final label in labels) {
      final slotMin = _labelToMinutes(label);
      if (isToday && slotMin < cutoffMin) {
        debugPrint(
            '[DODO][Slots]   "$label" ($slotMin min) — FILTERED (before cutoff $cutoffMin)');
        continue;
      }
      if (vendorBusyUntilMin > 0 && slotMin < vendorBusyUntilMin) {
        debugPrint(
            '[DODO][Slots]   "$label" ($slotMin min) — FILTERED (vendor busy until $vendorBusyUntilMin)');
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
    String? preferredVendorId,
    double? preferredVendorFeeAmount,
    AmcPlanModel? amcPlan,
    String paymentMethod = 'cod',
  }) async {
    debugPrint('[DODO][Booking] createBooking started');
    debugPrint('[DODO][Booking] Service: ${service.name} (id=${service.id})');
    debugPrint('[DODO][Booking] Address object — id=${address.id}  lat=${address.latitude}  lng=${address.longitude}  full="${address.fullAddress}"');
    debugPrint('[DODO][Booking] Date: ${date.toIso8601String().substring(0, 10)}');
    debugPrint('[DODO][Booking] Slot: ${slot.label}');
    if (amcPlan != null) debugPrint('[DODO][Booking] AMC plan: ${amcPlan.name} (${amcPlan.recurrenceInterval}) ₹${amcPlan.pricePerVisit}/visit');

    final customerId = await _getCustomerId();
    debugPrint('[DODO][Booking] customer_id=$customerId');

    final addonsTotal = amcPlan != null ? 0.0 : totalAddonsPrice(selectedAddons);
    final subtotal = amcPlan != null
        ? amcPlan.pricePerVisit
        : (service.basePrice ?? 0.0) + priceAdjustment + addonsTotal;
    final tax = await _resolveTaxAmount(subtotal, service.id, parentNodeId);
    final pvFee = preferredVendorFeeAmount ?? 0.0;
    final grossAmount = subtotal + tax + pvFee;
    final totalAmount = (grossAmount - discountAmount).clamp(0.0, double.infinity);
    final serviceDate = date.toIso8601String().substring(0, 10);

    if (couponId != null) {
      debugPrint('[DODO][Booking] Coupon: id=$couponId discount=₹${discountAmount.toStringAsFixed(2)}');
    }

    // ── Generate OTP before building payload ─────────────────────────────────
    final completionOtp = (100000 + Random().nextInt(900000)).toString();
    debugPrint('[OTP][Create] ══════════ OTP GENERATION ══════════');
    debugPrint('[OTP][Create] Generated OTP: $completionOtp  (len=${completionOtp.length})');

    // ── Look up existing active contract or create a new one ────────────────
    // Reuse an active contract so every visit belongs to the same contract.
    // Only create a new contract when none exists (first purchase) or the
    // existing one is already completed/cancelled.
    String? amcContractId;
    int amcVisitNumber = 1;
    if (amcPlan != null) {
      if (amcPlan.id.isNotEmpty) {
        final existing = await _client
            .from('amc_contracts')
            .select('id, visits_completed, num_visits')
            .eq('customer_id', customerId)
            .eq('service_id', service.id)
            .eq('amc_plan_id', amcPlan.id)
            .eq('status', 'active')
            .limit(1);
        final list = existing as List;
        if (list.isNotEmpty) {
          final row = list.first as Map<String, dynamic>;
          final completed = (row['visits_completed'] as num?)?.toInt() ?? 0;
          final total = (row['num_visits'] as num?)?.toInt() ?? 0;
          if (total == 0 || completed < total) {
            amcContractId = row['id'] as String;
            amcVisitNumber = await resolveNextAmcVisitNumber(_client, amcContractId);
            debugPrint('[AMC] Reusing contract id=$amcContractId  visits=$completed/$total → booking visit #$amcVisitNumber');
          }
        }
      }

      if (amcContractId == null) {
        debugPrint('[AMC][Insert] plan: id=${amcPlan.id}  planName=${amcPlan.planName}  packageDuration=${amcPlan.packageDuration}  serviceInterval=${amcPlan.serviceInterval}');
        debugPrint('[AMC][Insert] computed: packageDays=${amcPlan.packageDays}  intervalDays=${amcPlan.intervalDays}  numVisits=${amcPlan.numVisits}');
        debugPrint('[AMC][Insert] pricing: pricePerVisit=${amcPlan.pricePerVisit}  originalTotal=${amcPlan.originalTotal}  discountType=${amcPlan.discountType}  discountValue=${amcPlan.discountValue}  discountAmount=${amcPlan.discountAmount}  finalPrice=${amcPlan.finalPrice}');
        final contractRow = await _client.from('amc_contracts').insert({
          'customer_id': customerId,
          'service_id': service.id,
          'service_name': service.name,
          'plan_name': amcPlan.name,
          'recurrence_interval': amcPlan.recurrenceInterval,
          'price_per_visit': amcPlan.pricePerVisit,
          'status': 'active',
          'total_visits': amcPlan.numVisits,
          'amc_plan_id': amcPlan.id.isNotEmpty ? amcPlan.id : null,
          'package_duration': amcPlan.packageDuration,
          'service_interval': amcPlan.serviceInterval,
          'num_visits': amcPlan.numVisits,
          'original_total': amcPlan.originalTotal,
          'discount_type': amcPlan.discountType,
          'discount_value': amcPlan.discountValue,
          'discount_amount': amcPlan.discountAmount,
          'final_price': amcPlan.finalPrice,
        }).select('id').single();
        amcContractId = contractRow['id'] as String;
        debugPrint('[AMC][Insert] Contract created id=$amcContractId');
      }
    }

    // ── Check for existing unscheduled AMC visit (Option B lifecycle) ────────
    // When the DB trigger creates a next-visit placeholder (status=pending,
    // service_date=NULL), UPDATE that row instead of INSERTing a new booking.
    String? pendingVisitId;
    if (amcContractId != null) {
      pendingVisitId = await findUnscheduledAmcVisit(_client, amcContractId);
      if (pendingVisitId != null) {
        debugPrint('[DODO][Booking][AMC] Found unscheduled visit id=$pendingVisitId — scheduling instead of INSERT');
      }
    }

    // ── INSERT into bookings (or UPDATE existing pending AMC visit) ──────────
    debugPrint('[DODO][Booking] Booking payload — lat=${address.latitude}  lng=${address.longitude}');
    final Map<String, dynamic> bookingData;
    if (pendingVisitId != null) {
      await _client.from('bookings').update({
        'service_date': serviceDate,
        'scheduled_time': slot.label,
        'address': address.fullAddress,
        'notes': '${service.name} · ${slot.label}',
        'latitude': ?address.latitude,
        'longitude': ?address.longitude,
        'subtotal': subtotal,
        'discount_amount': discountAmount,
        'total_amount': totalAmount,
        'preferred_vendor_id': ?preferredVendorId,
        'vendor_id': ?preferredVendorId,
        if (pvFee > 0) 'preferred_vendor_fee_amount': pvFee,
      }).eq('id', pendingVisitId);
      bookingData = Map<String, dynamic>.from(
        await _client.from('bookings').select().eq('id', pendingVisitId).single(),
      );
      debugPrint('[DODO][Booking][AMC] Scheduled existing pending visit id=$pendingVisitId');
    } else {
      debugPrint('[DODO][Booking] Inserting into bookings table');
      final payload = {
        'customer_id': customerId,
        'service_date': serviceDate,
        'status': 'pending',
        'payment_method': paymentMethod,
        'payment_status': 'pending',
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
        'preferred_vendor_id': ?preferredVendorId,
        if (pvFee > 0) 'preferred_vendor_fee_amount': pvFee,
        // Auto-assign: when customer picks a preferred vendor, write vendor_id
        // immediately so admin dispatch is bypassed for this booking.
        'vendor_id': ?preferredVendorId,
        if (amcPlan != null) ...{
          'is_amc': true,
          'amc_plan_name': amcPlan.name,
          'amc_recurrence_interval': amcPlan.recurrenceInterval,
          if (amcContractId != null) 'amc_contract_id': amcContractId,
          'amc_visit_number': amcVisitNumber,
        },
      };
      debugPrint('[OTP][Create] Payload keys    : ${payload.keys.toList()}');
      debugPrint('[OTP][Create] Payload otp val : ${payload['completion_otp']}');
      debugPrint('BOOKING LAT=${address.latitude}');
      debugPrint('BOOKING LNG=${address.longitude}');
      debugPrint('BOOKING PAYLOAD=$payload');
      bookingData = Map<String, dynamic>.from(
        await _client.from('bookings').insert(payload).select().single(),
      );
      debugPrint('[DODO][Booking] Booking created: id=${bookingData['id']}');
    }

    final bookingId = bookingData['id'] as String;

    // ── Verify OTP was written (INSERT path only) ────────────────────────────
    // The trigger-created placeholder already has an OTP; skip for UPDATE path.
    if (pendingVisitId == null) {
      final returnedOtp = bookingData['completion_otp'] as String?;
      debugPrint('[OTP][Create] Returned row keys: ${(bookingData).keys.toList()}');
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
      isAmc: amcPlan != null,
      amcPlanName: amcPlan?.name,
      amcRecurrenceInterval: amcPlan?.recurrenceInterval,
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
