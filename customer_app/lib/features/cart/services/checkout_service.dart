import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/time_slot_model.dart';
import '../../../models/booking_model.dart';
import '../../../models/address_model.dart';
import '../models/cart_item.dart';
import '../../amc/services/amc_visit_number_service.dart';
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

    // ── Location-availability enforcement ────────────────────────────────────
    final checked = <String>{};
    if (address.latitude == null || address.longitude == null) {
      // No coordinates: block if the service has any location restrictions —
      // eligibility cannot be verified without coordinates.
      for (final item in items) {
        if (checked.contains(item.serviceId)) continue;
        checked.add(item.serviceId);
        final rows = await _client
            .from('catalog_node_location_restrictions')
            .select('id')
            .eq('node_id', item.serviceId)
            .limit(1);
        if ((rows as List).isNotEmpty) {
          throw Exception(
            '${item.serviceName}: This service has location restrictions. '
            'Please select an address with valid coordinates to continue.',
          );
        }
      }
    } else {
      for (final item in items) {
        if (checked.contains(item.serviceId)) continue;
        checked.add(item.serviceId);
        try {
          final avail = await _client.rpc('check_node_availability', params: {
            'p_node_id': item.serviceId,
            'p_parent_id': item.parentNodeId,
            'p_lat': address.latitude,
            'p_lng': address.longitude,
          });
          if (avail is Map) {
            final status =
                (avail as Map<String, dynamic>)['status'] as String? ??
                    'active';
            if (status != 'active') {
              final msg =
                  (avail)['message'] as String? ??
                      'Not available in your area.';
              throw Exception('${item.serviceName}: $msg');
            }
          }
        } catch (e) {
          if (e is Exception) rethrow;
          debugPrint(
              '[DODO][Checkout] Location check warning (non-fatal): $e');
        }
      }
    }

    // ── AMC contract: reuse existing active contract or create a new one ────
    // Reusing ensures every visit belongs to the same contract lifecycle.
    final amcItem = items.cast<CartItem?>().firstWhere(
          (i) => i!.isAmc,
          orElse: () => null,
        );
    String? amcContractId;
    int amcVisitNumber = 1;
    if (amcItem != null) {
      final planId = amcItem.amcPlanId;
      // Renewals always create a new contract — never reuse the previous one.
      if (!amcItem.amcIsRenewal && planId != null && planId.isNotEmpty) {
        final existing = await _client
            .from('amc_contracts')
            .select('id, visits_completed, num_visits')
            .eq('customer_id', customerId)
            .eq('service_id', amcItem.serviceId)
            .eq('amc_plan_id', planId)
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
        debugPrint('[AMC][Insert] planId=${amcItem.amcPlanId}  planName=${amcItem.amcPlanName}  packageDuration=${amcItem.amcPackageDuration}  serviceInterval=${amcItem.amcServiceInterval}');
        debugPrint('[AMC][Insert] numVisits=${amcItem.amcNumVisits}  pricePerVisit=${amcItem.amcPricePerVisit}  originalTotal=${amcItem.amcOriginalTotal}  discountType=${amcItem.amcDiscountType}  discountValue=${amcItem.amcDiscountValue}  discountAmount=${amcItem.amcDiscountAmount}  finalPrice=${amcItem.amcFinalPrice}');
        final qty = amcItem.amcQuantity;
        final contractRow = await _client.from('amc_contracts').insert({
          'customer_id': customerId,
          'service_id': amcItem.serviceId,
          'service_name': amcItem.serviceName,
          'plan_name': amcItem.amcPlanName ?? amcItem.serviceName,
          'recurrence_interval': amcItem.amcRecurrenceInterval ?? '',
          'price_per_visit': amcItem.amcPricePerVisit ?? amcItem.unitPrice,
          'status': 'active',
          'total_visits': amcItem.amcNumVisits ?? 0,
          'quantity': qty,
          'is_renewal': amcItem.amcIsRenewal,
          if (amcItem.amcPreviousContractId != null)
            'previous_contract_id': amcItem.amcPreviousContractId,
          if (planId != null && planId.isNotEmpty) 'amc_plan_id': planId,
          if (amcItem.amcPackageDuration != null)
            'package_duration': amcItem.amcPackageDuration,
          if (amcItem.amcServiceInterval != null)
            'service_interval': amcItem.amcServiceInterval,
          if (amcItem.amcNumVisits != null) 'num_visits': amcItem.amcNumVisits,
          if (amcItem.amcOriginalTotal != null)
            'original_total': (amcItem.amcOriginalTotal ?? 0) * qty,
          'discount_type': amcItem.amcDiscountType,
          'discount_value': amcItem.amcDiscountValue ?? 0,
          if (amcItem.amcDiscountAmount != null)
            'discount_amount': (amcItem.amcDiscountAmount ?? 0) * qty,
          if (amcItem.amcFinalPrice != null)
            'final_price': (amcItem.amcFinalPrice ?? 0) * qty,
        }).select('id').single();
        amcContractId = contractRow['id'] as String;
        debugPrint('[DODO][Checkout][AMC] Created contract id=$amcContractId');

        if (amcItem.amcIsRenewal) {
          final planLabel = amcItem.amcPlanName ?? amcItem.serviceName;
          try {
            await _client.from('notifications').insert({
              'user_type': 'admin',
              'user_id': 'admin',
              'title': 'AMC Membership Renewed',
              'message': 'A customer has renewed their "$planLabel" AMC membership.',
              'notification_type': 'amc_renewed',
              'is_read': false,
              'entity_type': 'amc_contract',
              'entity_id': amcContractId,
            });
          } catch (e) {
            debugPrint('[AMC][Renewal] Warning: admin renewal notification failed (non-fatal): $e');
          }
          try {
            await _client.from('notifications').insert({
              'user_type': 'customer',
              'user_id': customerId,
              'title': 'AMC Membership Renewed',
              'message': 'Your "$planLabel" AMC membership has been renewed successfully.',
              'notification_type': 'amc_renewed',
              'is_read': false,
              'entity_type': 'amc_contract',
              'entity_id': amcContractId,
            });
          } catch (e) {
            debugPrint('[AMC][Renewal] Warning: customer renewal notification failed (non-fatal): $e');
          }
        }
      }
    }

    // ── INSERT bookings row (or UPDATE existing pending AMC visit) ───────────
    // When a preferred vendor is selected, immediately assign the booking as
    // the admin "Confirm Assignment" flow would: status=assigned,
    // assignment_type=External Vendor, vendor_id=preferred vendor.
    // No admin intervention required — booking goes straight to Vendor App.
    //
    // Option B AMC lifecycle: if the DB trigger created an unscheduled pending
    // placeholder for the next visit, UPDATE that row instead of INSERTing.
    final primaryItem = items.isNotEmpty ? items.first : null;
    final hasPv = preferredVendorId != null;

    String? pendingVisitId;
    if (amcContractId != null) {
      pendingVisitId = await findUnscheduledAmcVisit(_client, amcContractId);
      if (pendingVisitId != null) {
        debugPrint('[DODO][Checkout][AMC] Found unscheduled visit id=$pendingVisitId — scheduling instead of INSERT');
      }
    }

    final Map<String, dynamic> bookingData;
    if (pendingVisitId != null) {
      await _client.from('bookings').update({
        'service_date': serviceDate,
        'scheduled_time': slot.label,
        'address': address.fullAddress,
        'notes': slot.label,
        'latitude': ?address.latitude,
        'longitude': ?address.longitude,
        'subtotal': subtotal,
        'discount_amount': discountAmount,
        'total_amount': totalAmount,
        'payment_method': paymentMethod,
        'payment_status': paymentStatus,
        'status': hasPv ? 'assigned' : 'pending',
        if (hasPv) 'assignment_type': 'External Vendor',
        'preferred_vendor_id': ?preferredVendorId,
        'vendor_id': ?preferredVendorId,
        if (pvFee > 0) 'preferred_vendor_fee_amount': pvFee,
      }).eq('id', pendingVisitId);
      bookingData = Map<String, dynamic>.from(
        await _client.from('bookings').select().eq('id', pendingVisitId).single(),
      );
      debugPrint('[DODO][Checkout][AMC] Scheduled existing pending visit id=$pendingVisitId');
    } else {
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
        if (amcItem != null) ...{
          'is_amc': true,
          'amc_plan_name': amcItem.amcPlanName ?? amcItem.serviceName,
          'amc_recurrence_interval': amcItem.amcRecurrenceInterval ?? '',
          'amc_contract_id': ?amcContractId,
          'amc_visit_number': amcVisitNumber,
        },
      };
      debugPrint('[DODO][PV Assignment] INSERT preferred_vendor_id = $preferredVendorId');
      debugPrint('[DODO][PV Assignment] INSERT vendor_id = $preferredVendorId');
      debugPrint('BOOKING LAT=${address.latitude}');
      debugPrint('BOOKING LNG=${address.longitude}');
      debugPrint('BOOKING PAYLOAD=$payload');
      bookingData = Map<String, dynamic>.from(
        await _client.from('bookings').insert(payload).select().single(),
      );
      debugPrint('[DODO][Checkout] Booking created: id=${bookingData['id']}');
    }

    final bookingId = bookingData['id'] as String;

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

    debugPrint('[DODO][Checkout] Flow complete — bookingId=$bookingId');

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
      isAmc: amcItem != null,
      amcPlanName: amcItem?.amcPlanName,
      amcRecurrenceInterval: amcItem?.amcRecurrenceInterval,
    );
  }

  // ── AMC contract utilities ────────────────────────────────────────────────────

  /// Returns the active AMC contract row for [serviceId] + [planId] when one
  /// exists and still has visits remaining. Returns null otherwise.
  /// Used by the checkout screen to enforce the one-active-AMC rule.
  Future<Map<String, dynamic>?> findActiveAmcContract({
    required String serviceId,
    required String? planId,
  }) async {
    if (planId == null || planId.isEmpty) return null;
    final customerId = await _getCustomerId();
    final rows = await _client
        .from('amc_contracts')
        .select('id, service_name, plan_name, visits_completed, num_visits, total_visits')
        .eq('customer_id', customerId)
        .eq('service_id', serviceId)
        .eq('amc_plan_id', planId)
        .eq('status', 'active')
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    final row = Map<String, dynamic>.from(list.first as Map);
    final completed = (row['visits_completed'] as num?)?.toInt() ?? 0;
    final total = (row['num_visits'] as num?)?.toInt() ??
        (row['total_visits'] as num?)?.toInt() ?? 0;
    if (total > 0 && completed >= total) return null;
    return row;
  }

  /// Submits a full-membership cancellation request for admin approval.
  /// Sets contract status to 'cancellation_requested' so admin can approve or
  /// reject. No visits are cancelled until the admin approves.
  Future<void> requestMembershipCancellation(
    String contractId, {
    required String reason,
    String? remarks,
  }) async {
    final trimmedRemarks = remarks?.trim();
    final customerId = await _getCustomerId();
    await _client.from('amc_contracts').update({
      'status': 'cancellation_requested',
      'cancellation_reason': reason,
      if (trimmedRemarks != null && trimmedRemarks.isNotEmpty)
        'cancellation_remarks': trimmedRemarks,
      'cancellation_requested_at':
          DateTime.now().toUtc().toIso8601String(),
    }).eq('id', contractId);
    await _client.from('amc_cancellation_requests').insert({
      'contract_id': contractId,
      'customer_id': customerId,
      'reason': reason,
      if (trimmedRemarks != null && trimmedRemarks.isNotEmpty)
        'remarks': trimmedRemarks,
      'status': 'pending',
      'type': 'membership',
    });
  }

  /// Submits a single-visit cancellation request for admin approval.
  /// The AMC contract remains active. Only [bookingId] is cancelled upon approval.
  Future<void> requestVisitCancellation(
    String contractId,
    String bookingId,
  ) async {
    final customerId = await _getCustomerId();
    await _client.from('amc_cancellation_requests').insert({
      'contract_id': contractId,
      'customer_id': customerId,
      'status': 'pending',
      'type': 'visit',
      'booking_id': bookingId,
    });
  }

  /// Cancels [contractId] and any pending unscheduled visit placeholder
  /// (status = 'pending', service_date IS NULL) that the DB trigger created.
  /// Completed visits are not affected.
  Future<void> cancelAmcContract(String contractId) async {
    await _client
        .from('amc_contracts')
        .update({'status': 'cancelled'})
        .eq('id', contractId);
    await _client
        .from('bookings')
        .update({'status': 'cancelled'})
        .eq('amc_contract_id', contractId)
        .eq('status', 'pending')
        .filter('service_date', 'is', null);
    // Also cancel any pending scheduling requests for this contract.
    await _client
        .from('amc_scheduling_requests')
        .update({'status': 'cancelled'})
        .eq('amc_contract_id', contractId)
        .eq('status', 'pending');
  }

  /// Submits a scheduling request for the customer's next AMC visit.
  /// Returns `'requested'` on success or `'already_requested'` if a pending
  /// request already exists. Does NOT touch bookings or assign a vendor.
  Future<String> requestNextVisit(
    String contractId, {
    DateTime? preferredDate,
    String? notes,
  }) async {
    final existing = await _client
        .from('amc_scheduling_requests')
        .select('id')
        .eq('amc_contract_id', contractId)
        .eq('status', 'pending')
        .limit(1);
    if ((existing as List).isNotEmpty) return 'already_requested';

    final customerId = await _getCustomerId();

    await _client.from('amc_scheduling_requests').insert({
      'amc_contract_id': contractId,
      'customer_id': customerId,
      'status': 'pending',
      if (preferredDate != null)
        'preferred_date': preferredDate.toIso8601String().substring(0, 10),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
    return 'requested';
  }

  /// Returns the ID of the active scheduling request for [contractId], or null.
  Future<String?> getActivePendingRequest(String contractId) async {
    final rows = await _client
        .from('amc_scheduling_requests')
        .select('id')
        .eq('amc_contract_id', contractId)
        .eq('status', 'pending')
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return list.first['id'] as String?;
  }

  /// Cancels a pending scheduling request initiated by the customer.
  /// Sets status to 'cancelled_by_customer' — distinct from system cancels so
  /// the admin notification trigger only fires for explicit customer actions.
  /// The .eq('status', 'pending') guard prevents double-cancels if the admin
  /// has already approved or rejected the request.
  Future<void> cancelPendingRequest(String requestId) async {
    await _client
        .from('amc_scheduling_requests')
        .update({'status': 'cancelled_by_customer'})
        .eq('id', requestId)
        .eq('status', 'pending');
  }
}
