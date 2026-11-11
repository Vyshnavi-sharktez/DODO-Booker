import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/instahelp_mode.dart';
import '../domain/models/instahelp_duration.dart';
import '../domain/models/instahelp_activity.dart';
import '../domain/models/instahelp_slot_config.dart';
import '../domain/models/instahelp_financial_config.dart';
import '../domain/models/instahelp_date_override.dart';

class InstaHelpVendorRepository {
  final SupabaseClient _supabase;
  const InstaHelpVendorRepository(this._supabase);

  // ── Modes ─────────────────────────────────────────────────────────────────

  Future<List<InstaHelpMode>> fetchVendorModes(String vendorId) async {
    final data = await _supabase
        .from('instahelp_modes')
        .select()
        .eq('vendor_id', vendorId)
        .order('mode_type');
    return (data as List)
        .map((r) => InstaHelpMode.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> initializeVendorModes(String vendorId) async {
    // Subscription check: vendor must have an active (or grace-period) subscription
    // with InstaHelp permission before they can enable InstaHelp.
    final eligible = await _supabase
        .rpc('check_vendor_instahelp_eligibility', params: {'p_vendor_id': vendorId});
    if (eligible != true) {
      throw Exception(
        'An active subscription with InstaHelp access is required to enable this feature. '
        'Please subscribe or contact support.',
      );
    }

    final existing = await _supabase
        .from('instahelp_modes')
        .select('mode_type')
        .eq('vendor_id', vendorId);
    final existingTypes = (existing as List).map((r) => r['mode_type'] as String).toSet();
    final toCreate = <Map<String, dynamic>>[];
    for (final type in ['scheduled', 'instant', 'car_wash']) {
      if (!existingTypes.contains(type)) {
        toCreate.add({'vendor_id': vendorId, 'mode_type': type, 'is_active': false});
      }
    }
    if (toCreate.isNotEmpty) {
      await _supabase.from('instahelp_modes').insert(toCreate);
    }
  }

  Future<bool> checkEligibility(String vendorId) async {
    final result = await _supabase.rpc(
        'check_vendor_instahelp_eligibility', params: {'p_vendor_id': vendorId});
    return result == true;
  }

  Future<void> toggleModeActive(String modeId, {required bool isActive}) async {
    await _supabase
        .from('instahelp_modes')
        .update({'is_active': isActive})
        .eq('id', modeId);
  }

  // ── Durations ─────────────────────────────────────────────────────────────

  Future<List<InstaHelpDuration>> fetchDurations(String modeId) async {
    final data = await _supabase
        .from('instahelp_durations')
        .select()
        .eq('mode_id', modeId)
        .order('sort_order');
    return (data as List)
        .map((r) => InstaHelpDuration.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> createDuration({
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
    final modeRow = await _supabase.from('instahelp_modes').select('vendor_id').eq('id', modeId).single();
    final eligible = await _supabase.rpc('check_vendor_instahelp_eligibility',
        params: {'p_vendor_id': modeRow['vendor_id']});
    if (eligible != true) {
      throw Exception('An active InstaHelp subscription is required to add services.');
    }
    await _supabase.from('instahelp_durations').insert({
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
    });
  }

  Future<void> updateDuration(
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
    await _supabase.from('instahelp_durations').update({
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
    }).eq('id', id);
  }

  Future<void> toggleDurationActive(String id, {required bool isActive}) async {
    await _supabase
        .from('instahelp_durations')
        .update({'is_active': isActive})
        .eq('id', id);
  }

  Future<void> deleteDuration(String id) async {
    await _supabase.from('instahelp_durations').delete().eq('id', id);
  }

  Future<void> reorderDurations(List<({String id, int sortOrder})> items) async {
    for (final item in items) {
      await _supabase
          .from('instahelp_durations')
          .update({'sort_order': item.sortOrder})
          .eq('id', item.id);
    }
  }

  // ── Activities ────────────────────────────────────────────────────────────

  Future<List<InstaHelpActivity>> fetchActivities(String modeId) async {
    final data = await _supabase
        .from('instahelp_activities')
        .select()
        .eq('mode_id', modeId)
        .order('sort_order');
    return (data as List)
        .map((r) => InstaHelpActivity.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> createActivity(
    String modeId, {
    required String title,
    required List<String> includedItems,
    required List<String> excludedItems,
    required bool isActive,
    required int sortOrder,
  }) async {
    final modeRow = await _supabase.from('instahelp_modes').select('vendor_id').eq('id', modeId).single();
    final eligible = await _supabase.rpc('check_vendor_instahelp_eligibility',
        params: {'p_vendor_id': modeRow['vendor_id']});
    if (eligible != true) {
      throw Exception('An active InstaHelp subscription is required to add services.');
    }
    await _supabase.from('instahelp_activities').insert({
      'mode_id': modeId,
      'title': title,
      'included_items': includedItems,
      'excluded_items': excludedItems,
      'is_active': isActive,
      'sort_order': sortOrder,
    });
  }

  Future<void> updateActivity(
    String id, {
    required String title,
    required List<String> includedItems,
    required List<String> excludedItems,
    required bool isActive,
  }) async {
    await _supabase.from('instahelp_activities').update({
      'title': title,
      'included_items': includedItems,
      'excluded_items': excludedItems,
      'is_active': isActive,
    }).eq('id', id);
  }

  Future<void> toggleActivityActive(String id, {required bool isActive}) async {
    await _supabase
        .from('instahelp_activities')
        .update({'is_active': isActive})
        .eq('id', id);
  }

  Future<void> deleteActivity(String id) async {
    await _supabase.from('instahelp_activities').delete().eq('id', id);
  }

  Future<void> reorderActivities(List<({String id, int sortOrder})> items) async {
    for (final item in items) {
      await _supabase
          .from('instahelp_activities')
          .update({'sort_order': item.sortOrder})
          .eq('id', item.id);
    }
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

  Future<void> upsertSlotConfig(
    String modeId, {
    required List<int> workingDays,
    required String startTime,
    required String endTime,
    required int slotIntervalMinutes,
    required int maxBookingsPerSlot,
    required bool isActive,
  }) async {
    await _supabase.from('instahelp_slot_config').upsert({
      'mode_id': modeId,
      'working_days': workingDays,
      'start_time': startTime,
      'end_time': endTime,
      'slot_interval_minutes': slotIntervalMinutes,
      'max_bookings_per_slot': maxBookingsPerSlot,
      'is_active': isActive,
    }, onConflict: 'mode_id');
  }

  // ── Financial Config ──────────────────────────────────────────────────────────

  Future<InstaHelpFinancialConfig?> fetchFinancialConfig(String modeId) async {
    final data = await _supabase
        .from('instahelp_financial_config')
        .select()
        .eq('mode_id', modeId)
        .maybeSingle();
    if (data == null) return null;
    return InstaHelpFinancialConfig.fromMap(data);
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

  Future<void> upsertFinancialConfig(
    String modeId, {
    required double gstPercent,
    required bool surgeFeeEnabled,
    required String surgeFeeType,
    required double surgeFeeValue,
    required bool serviceChargeEnabled,
    required String serviceChargeType,
    required double serviceChargeValue,
  }) async {
    await _supabase.from('instahelp_financial_config').upsert({
      'mode_id': modeId,
      'gst_percent': gstPercent,
      'surge_fee_enabled': surgeFeeEnabled,
      'surge_fee_type': surgeFeeType,
      'surge_fee_value': surgeFeeValue,
      'service_charge_enabled': serviceChargeEnabled,
      'service_charge_type': serviceChargeType,
      'service_charge_value': serviceChargeValue,
    }, onConflict: 'mode_id');
  }
}
