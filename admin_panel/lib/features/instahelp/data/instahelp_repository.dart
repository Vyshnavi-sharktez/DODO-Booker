import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/instahelp_mode.dart';
import '../domain/models/instahelp_duration.dart';
import '../domain/models/instahelp_activity.dart';
import '../domain/models/instahelp_financial_config.dart';
import '../domain/models/instahelp_order.dart';
import '../domain/models/instahelp_slot_config.dart';
import '../domain/models/instahelp_date_override.dart';
import '../../bookings/domain/models/booking_addon.dart';

// Join string that mirrors BookingsRepository._reviewSelect + instahelp_bookings!inner.
// The !inner ensures only bookings with an instahelp_bookings row are returned.
const _ordersSelect = '''
  *,
  vendors(id, business_name, vendor_number),
  customers!customer_id(full_name, phone, customer_number),
  customer_reviews!booking_id(id, rating, review_text, created_at),
  booking_items(
    service_id,
    service_name,
    item_name,
    category_name,
    quantity,
    unit_price,
    total_price,
    catalog_nodes!booking_items_service_id_catalog_fkey(id, name)
  ),
  amc_contracts!amc_contract_id(visits_completed, num_visits, total_visits, created_at, service_interval, status, cancellation_reason, cancellation_remarks, cancellation_requested_at, quantity),
  instahelp_bookings!inner(mode_type, duration_label, duration_minutes, base_price, final_price)
''';

class InstaHelpRepository {
  final SupabaseClient _supabase;
  const InstaHelpRepository(this._supabase);

  // ── Modes ─────────────────────────────────────────────────────────────────

  Future<List<InstaHelpMode>> fetchModes() async {
    final data = await _supabase
        .from('instahelp_modes')
        .select()
        .isFilter('vendor_id', null)
        .order('mode_type', ascending: true);
    return (data as List)
        .map((r) => InstaHelpMode.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<InstaHelpMode>> fetchVendorModes(String vendorId) async {
    const _modeOrder = ['scheduled', 'instant', 'car_wash'];
    final data = await _supabase
        .from('instahelp_modes')
        .select()
        .eq('vendor_id', vendorId);
    final modes = (data as List)
        .map((r) => InstaHelpMode.fromMap(r as Map<String, dynamic>))
        .toList();
    modes.sort((a, b) {
      final ai = _modeOrder.indexOf(a.modeType);
      final bi = _modeOrder.indexOf(b.modeType);
      return (ai == -1 ? 99 : ai).compareTo(bi == -1 ? 99 : bi);
    });
    return modes;
  }

  Future<void> initVendorModes(String vendorId) async {
    final existing = await fetchVendorModes(vendorId);
    if (existing.isNotEmpty) return;
    final globalModes = await fetchModes();
    for (final mode in globalModes) {
      await _supabase.from('instahelp_modes').insert({
        'vendor_id': vendorId,
        'mode_type': mode.modeType,
        'is_active': true,
      });
    }
  }

  // ── Durations ─────────────────────────────────────────────────────────────

  Future<List<InstaHelpDuration>> fetchDurations(String modeId) async {
    final data = await _supabase
        .from('instahelp_durations')
        .select()
        .eq('mode_id', modeId)
        .order('sort_order', ascending: true);
    return (data as List)
        .map((r) => InstaHelpDuration.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<InstaHelpDuration> createDuration({
    required String modeId,
    required String label,
    required int durationMinutes,
    required double price,
    required String discountType,
    required double discountValue,
    required bool isActive,
    required int sortOrder,
    required String slotStartTime,
    required String slotEndTime,
    required int slotIntervalMinutes,
    required int maxBookingsPerSlot,
  }) async {
    final data = await _supabase
        .from('instahelp_durations')
        .insert({
          'mode_id': modeId,
          'label': label,
          'duration_minutes': durationMinutes,
          'price': price,
          'discount_type': discountType,
          'discount_value': discountValue,
          'is_active': isActive,
          'sort_order': sortOrder,
          'slot_start_time': slotStartTime,
          'slot_end_time': slotEndTime,
          'slot_interval_minutes': slotIntervalMinutes,
          'max_bookings_per_slot': maxBookingsPerSlot,
        })
        .select()
        .single();
    return InstaHelpDuration.fromMap(data);
  }

  Future<InstaHelpDuration> updateDuration(
    String id, {
    required String label,
    required int durationMinutes,
    required double price,
    required String discountType,
    required double discountValue,
    required bool isActive,
    required String slotStartTime,
    required String slotEndTime,
    required int slotIntervalMinutes,
    required int maxBookingsPerSlot,
  }) async {
    final data = await _supabase
        .from('instahelp_durations')
        .update({
          'label': label,
          'duration_minutes': durationMinutes,
          'price': price,
          'discount_type': discountType,
          'discount_value': discountValue,
          'is_active': isActive,
          'slot_start_time': slotStartTime,
          'slot_end_time': slotEndTime,
          'slot_interval_minutes': slotIntervalMinutes,
          'max_bookings_per_slot': maxBookingsPerSlot,
        })
        .eq('id', id)
        .select()
        .single();
    return InstaHelpDuration.fromMap(data);
  }

  Future<void> toggleDurationActive(String id,
      {required bool isActive}) async {
    await _supabase
        .from('instahelp_durations')
        .update({'is_active': isActive}).eq('id', id);
  }

  Future<void> deleteDuration(String id) async {
    await _supabase.from('instahelp_durations').delete().eq('id', id);
  }

  Future<void> reorderDurations(List<({String id, int sortOrder})> items) async {
    await Future.wait(items.map((item) => _supabase
        .from('instahelp_durations')
        .update({'sort_order': item.sortOrder})
        .eq('id', item.id)));
  }

  // ── Activities ────────────────────────────────────────────────────────────

  Future<List<InstaHelpActivity>> fetchActivities(String modeId) async {
    final data = await _supabase
        .from('instahelp_activities')
        .select()
        .eq('mode_id', modeId)
        .order('sort_order', ascending: true);
    return (data as List)
        .map((r) => InstaHelpActivity.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<InstaHelpActivity> createActivity(
    String modeId, {
    required String title,
    required List<String> includedItems,
    required List<String> excludedItems,
    required bool isActive,
    required int sortOrder,
  }) async {
    final data = await _supabase
        .from('instahelp_activities')
        .insert({
          'mode_id': modeId,
          'title': title,
          'included_items': includedItems,
          'excluded_items': excludedItems,
          'is_active': isActive,
          'sort_order': sortOrder,
        })
        .select()
        .single();
    return InstaHelpActivity.fromMap(data);
  }

  Future<InstaHelpActivity> updateActivity(
    String id, {
    required String title,
    required List<String> includedItems,
    required List<String> excludedItems,
    required bool isActive,
  }) async {
    final data = await _supabase
        .from('instahelp_activities')
        .update({
          'title': title,
          'included_items': includedItems,
          'excluded_items': excludedItems,
          'is_active': isActive,
        })
        .eq('id', id)
        .select()
        .single();
    return InstaHelpActivity.fromMap(data);
  }

  Future<void> toggleActivityActive(String id, {required bool isActive}) async {
    await _supabase
        .from('instahelp_activities')
        .update({'is_active': isActive}).eq('id', id);
  }

  Future<void> deleteActivity(String id) async {
    await _supabase.from('instahelp_activities').delete().eq('id', id);
  }

  Future<void> reorderActivities(List<({String id, int sortOrder})> items) async {
    await Future.wait(items.map((item) => _supabase
        .from('instahelp_activities')
        .update({'sort_order': item.sortOrder})
        .eq('id', item.id)));
  }

  // ── Slot Config ───────────────────────────────────────────────────────────

  Future<InstaHelpSlotConfig?> fetchSlotConfig(String modeId) async {
    final data = await _supabase
        .from('instahelp_slot_config')
        .select()
        .eq('mode_id', modeId)
        .maybeSingle();
    if (data == null) return null;
    return InstaHelpSlotConfig.fromMap(data);
  }

  Future<InstaHelpSlotConfig> upsertSlotConfig(
    String modeId, {
    required List<int> workingDays,
    required String startTime,
    required String endTime,
    required int slotIntervalMinutes,
    required int maxBookingsPerSlot,
    required bool isActive,
  }) async {
    final data = await _supabase
        .from('instahelp_slot_config')
        .upsert({
          'mode_id': modeId,
          'working_days': workingDays,
          'start_time': startTime,
          'end_time': endTime,
          'slot_interval_minutes': slotIntervalMinutes,
          'max_bookings_per_slot': maxBookingsPerSlot,
          'is_active': isActive,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'mode_id')
        .select()
        .single();
    return InstaHelpSlotConfig.fromMap(data);
  }

  // ── Financial Config ──────────────────────────────────────────────────────

  Future<InstaHelpFinancialConfig?> fetchFinancialConfig(String modeId) async {
    final data = await _supabase
        .from('instahelp_financial_config')
        .select()
        .eq('mode_id', modeId)
        .maybeSingle();
    if (data == null) return null;
    return InstaHelpFinancialConfig.fromMap(data as Map<String, dynamic>);
  }

  Future<InstaHelpFinancialConfig> upsertFinancialConfig(
    String modeId, {
    required double gstPercent,
    required double platformCommissionPercent,
    required bool surgeFeeEnabled,
    required String surgeFeeType,
    required double surgeFeeValue,
    required bool serviceChargeEnabled,
    required String serviceChargeType,
    required double serviceChargeValue,
  }) async {
    final data = await _supabase
        .from('instahelp_financial_config')
        .upsert({
          'mode_id': modeId,
          'gst_percent': gstPercent,
          'platform_commission_percent': platformCommissionPercent,
          'surge_fee_enabled': surgeFeeEnabled,
          'surge_fee_type': surgeFeeType,
          'surge_fee_value': surgeFeeValue,
          'service_charge_enabled': serviceChargeEnabled,
          'service_charge_type': serviceChargeType,
          'service_charge_value': serviceChargeValue,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'mode_id')
        .select()
        .single();
    return InstaHelpFinancialConfig.fromMap(data as Map<String, dynamic>);
  }

  // ── Date Overrides ────────────────────────────────────────────────────────

  Future<List<InstaHelpDateOverride>> fetchDateOverrides(String modeId) async {
    final data = await _supabase
        .from('instahelp_date_overrides')
        .select()
        .eq('mode_id', modeId)
        .order('start_date', ascending: true);
    return (data as List)
        .map((r) => InstaHelpDateOverride.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<InstaHelpDateOverride> createDateOverride(
    String modeId, {
    required DateTime startDate,
    required DateTime endDate,
    required bool isAvailable,
    String? customStartTime,
    String? customEndTime,
    String? notes,
  }) async {
    final data = await _supabase
        .from('instahelp_date_overrides')
        .insert({
          'mode_id': modeId,
          'start_date': startDate.toIso8601String().substring(0, 10),
          'end_date': endDate.toIso8601String().substring(0, 10),
          'is_available': isAvailable,
          'custom_start_time': customStartTime,
          'custom_end_time': customEndTime,
          'notes': notes,
        })
        .select()
        .single();
    return InstaHelpDateOverride.fromMap(data);
  }

  Future<InstaHelpDateOverride> updateDateOverride(
    String id, {
    required DateTime startDate,
    required DateTime endDate,
    required bool isAvailable,
    String? customStartTime,
    String? customEndTime,
    String? notes,
  }) async {
    final data = await _supabase
        .from('instahelp_date_overrides')
        .update({
          'start_date': startDate.toIso8601String().substring(0, 10),
          'end_date': endDate.toIso8601String().substring(0, 10),
          'is_available': isAvailable,
          'custom_start_time': customStartTime,
          'custom_end_time': customEndTime,
          'notes': notes,
        })
        .eq('id', id)
        .select()
        .single();
    return InstaHelpDateOverride.fromMap(data);
  }

  Future<void> deleteDateOverride(String id) async {
    await _supabase.from('instahelp_date_overrides').delete().eq('id', id);
  }

  // ── InstaHelp Orders ──────────────────────────────────────────────────────

  Future<List<InstaHelpOrder>> fetchInstaHelpOrders() async {
    final data = await _supabase
        .from('bookings')
        .select(_ordersSelect)
        .order('created_at', ascending: false);

    final orders = (data as List<dynamic>)
        .map((r) => InstaHelpOrder.fromBookingMap(r as Map<String, dynamic>))
        .toList();

    final bookingIds = orders.map((o) => o.booking.id).toList();
    if (bookingIds.isEmpty) return orders;

    try {
      final addonData = await _supabase
          .from('booking_addons')
          .select('booking_id, addon_id, addon_name, addon_price, quantity, is_global')
          .inFilter('booking_id', bookingIds);

      final addonMap = <String, List<Map<String, dynamic>>>{};
      for (final row in addonData as List<dynamic>) {
        final m = row as Map<String, dynamic>;
        final bid = m['booking_id'] as String;
        addonMap.putIfAbsent(bid, () => []).add(m);
      }

      return orders.map((o) {
        final raw = addonMap[o.booking.id];
        if (raw == null) return o;
        final addons = raw.map(BookingAddon.fromMap).toList();
        return o.copyWith(booking: o.booking.copyWith(addons: addons));
      }).toList();
    } catch (e) {
      debugPrint('[InstaHelp] Warning: addon fetch failed: $e');
      return orders;
    }
  }

}
