import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/address_model.dart';
import '../../../models/booking_model.dart';
import '../models/instahelp_duration_model.dart';
import '../models/instahelp_activity_model.dart';
import '../models/instahelp_financial_config_model.dart';
import '../models/instahelp_slot_model.dart';

class InstaHelpService {
  static const _phoneKey = 'dodo_auth_phone';
  final _client = Supabase.instance.client;

  /// Fetches global (admin-managed) mode IDs when [vendorId] is null,
  /// or vendor-specific mode IDs when [vendorId] is provided.
  Future<Map<String, String>> fetchModeIds({String? vendorId}) async {
    var query = _client
        .from('instahelp_modes')
        .select('id, mode_type')
        .eq('is_active', true);
    if (vendorId != null) {
      query = query.eq('vendor_id', vendorId);
    } else {
      query = query.isFilter('vendor_id', null);
    }
    final rows = await query;
    final result = <String, String>{};
    for (final r in rows as List) {
      final map = r as Map<String, dynamic>;
      result[map['mode_type'] as String] = map['id'] as String;
    }
    return result;
  }

  /// Fetches vendors offering InstaHelp near [lat]/[lng].
  /// [modeType] filters to vendors with that mode active ('scheduled', 'instant', 'car_wash').
  Future<List<Map<String, dynamic>>> fetchVendorsForLocation(
      double lat, double lng, {String? modeType}) async {
    final rows = await _client.rpc(
      'get_instahelp_vendors_by_location',
      params: {
        'p_lat': lat,
        'p_lng': lng,
        if (modeType != null) 'p_mode_type': modeType,
      },
    );
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<List<InstaHelpDurationModel>> fetchDurations(String modeId) async {
    final rows = await _client
        .from('instahelp_durations')
        .select()
        .eq('mode_id', modeId)
        .eq('is_active', true)
        .order('sort_order', ascending: true);
    return (rows as List)
        .map((r) => InstaHelpDurationModel.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<InstaHelpActivityModel>> fetchActivities(String modeId) async {
    debugPrint('[InstaHelp] Fetching activities for modeId=$modeId');
    try {
      final rows = await _client
          .from('instahelp_activities')
          .select()
          .eq('mode_id', modeId)
          .eq('is_active', true)
          .order('sort_order', ascending: true);
      final list = (rows as List)
          .map((r) =>
              InstaHelpActivityModel.fromMap(r as Map<String, dynamic>))
          .toList();
      debugPrint(
          '[InstaHelp] Fetched ${list.length} active activity group(s) for modeId=$modeId');
      return list;
    } catch (e, st) {
      debugPrint(
          '[InstaHelp] Error fetching activities for modeId=$modeId: $e\n$st');
      rethrow;
    }
  }

  Future<({bool isAvailable, String? message})> checkDateAvailable(
      String modeId, DateTime date) async {
    final dateStr = date.toIso8601String().substring(0, 10);

    // 1. Check explicit date override
    final override = await _client
        .from('instahelp_date_overrides')
        .select('is_available, notes')
        .eq('mode_id', modeId)
        .lte('start_date', dateStr)
        .gte('end_date', dateStr)
        .maybeSingle();
    if (override != null) {
      return (
        isAvailable: override['is_available'] as bool,
        message: override['notes'] as String?,
      );
    }

    // 2. Check working_days in slot config only if one exists.
    // No slot config = all dates available; vendor uses date overrides to block specific dates.
    final config = await _client
        .from('instahelp_slot_config')
        .select('working_days, is_active')
        .eq('mode_id', modeId)
        .maybeSingle();
    if (config == null) {
      return (isAvailable: true, message: null);
    }
    if (!(config['is_active'] as bool)) {
      return (isAvailable: false, message: null);
    }

    // Dart weekday: Mon=1..Sun=7 → Postgres DOW: Sun=0..Sat=6
    final pgDow = date.weekday % 7;
    final workingDays = (config['working_days'] as List).cast<int>();
    return (isAvailable: workingDays.contains(pgDow), message: null);
  }

  Future<List<InstaHelpSlotModel>> fetchSlots(
      String modeId, String durationId, DateTime date) async {
    final dateStr = date.toIso8601String().substring(0, 10);
    final rows = await _client.rpc('get_instahelp_slots', params: {
      'p_mode_id': modeId,
      'p_duration_id': durationId,
      'p_date': dateStr,
    });
    return (rows as List)
        .map((r) => InstaHelpSlotModel.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<InstaHelpFinancialConfigModel?> fetchFinancialConfig(
      String modeId) async {
    final data = await _client
        .from('instahelp_financial_config')
        .select()
        .eq('mode_id', modeId)
        .maybeSingle();
    if (data == null) return null;
    return InstaHelpFinancialConfigModel.fromMap(data as Map<String, dynamic>);
  }

  Stream<InstaHelpFinancialConfigModel?> streamFinancialConfig(
      String modeId) {
    return _client
        .from('instahelp_financial_config')
        .stream(primaryKey: ['id'])
        .eq('mode_id', modeId)
        .map((rows) => rows.isEmpty
            ? null
            : InstaHelpFinancialConfigModel.fromMap(
                rows.first as Map<String, dynamic>))
        .handleError((e) {
      debugPrint('[InstaHelp] streamFinancialConfig error: $e');
    });
  }

  Future<InstaHelpInstantAvailability> checkInstantAvailability(
      String modeId) async {
    final rows = await _client.rpc(
      'check_instahelp_instant_availability',
      params: {'p_mode_id': modeId},
    );
    if (rows is List && rows.isNotEmpty) {
      return InstaHelpInstantAvailability.fromMap(
          rows.first as Map<String, dynamic>);
    }
    return const InstaHelpInstantAvailability(isAvailable: false);
  }

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

  Future<BookingModel> createBooking({
    required String modeId,
    required String modeType,
    required InstaHelpDurationModel duration,
    required AddressModel address,
    required DateTime date,
    required String scheduledTime,
    String paymentMethod = 'cash',
    InstaHelpFinancialConfigModel? financialConfig,
    String? preferredVendorId,
    double preferredVendorFee = 0.0,
  }) async {
    final customerId = await _getCustomerId();
    final basePrice = duration.finalPrice;
    final cfg = financialConfig ?? InstaHelpFinancialConfigModel.zero(modeId);
    final totalPrice = cfg.totalAmount(basePrice) + preferredVendorFee;
    final serviceDate = date.toIso8601String().substring(0, 10);
    final serviceName = 'InstaHelp – ${duration.label}';

    debugPrint('[InstaHelp] Creating booking: $serviceName  price=₹$totalPrice  mode=$modeType  date=$serviceDate  slot=$scheduledTime  preferredVendor=$preferredVendorId');

    final surgeAmt = cfg.surgeAmount(basePrice);
    final scAmt = cfg.serviceChargeAmount(basePrice);
    final gstAmt = cfg.gstAmount(basePrice);

    final hasPreferred = preferredVendorId != null && preferredVendorId.isNotEmpty;

    // 1. INSERT bookings row
    final bookingPayload = {
      'customer_id': customerId,
      'service_date': serviceDate,
      'status': hasPreferred ? 'assigned' : 'pending',
      'subtotal': basePrice,
      'tax_amount': gstAmt,
      'discount_amount': 0.0,
      'total_amount': totalPrice,
      'address': address.fullAddress,
      'notes': serviceName,
      'scheduled_time': scheduledTime,
      'payment_method': paymentMethod,
      'payment_status': 'pending',
      'booking_source': 'instahelp',
      if (address.latitude != null) 'latitude': address.latitude,
      if (address.longitude != null) 'longitude': address.longitude,
      if (hasPreferred) 'vendor_id': preferredVendorId,
      if (hasPreferred) 'assignment_type': 'External Vendor',
    };

    final bookingRow = await _client
        .from('bookings')
        .insert(bookingPayload)
        .select()
        .single();
    final bookingId = bookingRow['id'] as String;
    debugPrint('[InstaHelp] booking id=$bookingId');

    // 2. INSERT booking_items row
    try {
      await _client.from('booking_items').insert({
        'booking_id': bookingId,
        'service_name': serviceName,
        'quantity': 1,
        'unit_price': totalPrice,
        'total_price': totalPrice,
      });
    } catch (e) {
      debugPrint('[InstaHelp] Warning: booking_items insert failed (non-fatal): $e');
    }

    // 3. INSERT instahelp_bookings metadata
    try {
      await _client.from('instahelp_bookings').insert({
        'booking_id': bookingId,
        'mode_id': modeId,
        'duration_id': duration.id,
        'mode_type': modeType,
        'duration_label': duration.label,
        'duration_minutes': duration.durationMinutes,
        'base_price': duration.price,
        'final_price': totalPrice,
        // Financial snapshot
        'gst_percent': cfg.gstPercent,
        'gst_amount': gstAmt,
        'platform_commission_percent': cfg.platformCommissionPercent,
        'platform_commission_amount':
            cfg.platformCommissionPercent > 0
                ? basePrice * cfg.platformCommissionPercent / 100
                : 0.0,
        'surge_fee_enabled': cfg.surgeFeeEnabled,
        'surge_fee_type': cfg.surgeFeeType,
        'surge_fee_value': cfg.surgeFeeValue,
        'surge_fee_amount': surgeAmt,
        'service_charge_enabled': cfg.serviceChargeEnabled,
        'service_charge_type': cfg.serviceChargeType,
        'service_charge_value': cfg.serviceChargeValue,
        'service_charge_amount': scAmt,
      });
    } catch (e) {
      debugPrint('[InstaHelp] Warning: instahelp_bookings insert failed (non-fatal): $e');
    }

    // 4. Customer notification
    try {
      await _client.from('notifications').insert({
        'user_type': 'customer',
        'user_id': customerId,
        'title': 'InstaHelp Booking Confirmed',
        'message': 'Your $serviceName booking has been placed successfully.',
        'notification_type': 'booking_created',
        'is_read': false,
        'entity_type': 'booking',
        'entity_id': bookingId,
      });
    } catch (e) {
      debugPrint('[InstaHelp] Warning: notification failed (non-fatal): $e');
    }

    // 5. Admin notification
    try {
      await _client.from('notifications').insert({
        'user_type': 'admin',
        'user_id': null,
        'title': 'New InstaHelp Booking',
        'message': 'A new $modeType InstaHelp booking has been placed.',
        'notification_type': 'booking_created',
        'is_read': false,
        'entity_type': 'booking',
        'entity_id': bookingId,
      });
    } catch (e) {
      debugPrint('[InstaHelp] Warning: admin notification failed (non-fatal): $e');
    }

    // 6. Vendor notification (when assigned to a preferred vendor)
    if (hasPreferred) {
      try {
        await _client.from('notifications').insert({
          'user_type': 'vendor',
          'user_id': preferredVendorId,
          'title': 'New InstaHelp Booking Assigned',
          'message': 'A new InstaHelp $modeType booking has been assigned to you.',
          'notification_type': 'booking_created',
          'is_read': false,
          'entity_type': 'booking',
          'entity_id': bookingId,
        });
      } catch (e) {
        debugPrint('[InstaHelp] Warning: vendor notification failed (non-fatal): $e');
      }
    }

    return BookingModel.fromJson(bookingRow);
  }
}
