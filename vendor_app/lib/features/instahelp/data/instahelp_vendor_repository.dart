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
        .order('sort_order', ascending: true);
    return (data as List)
        .map((r) => InstaHelpMode.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> reorderModes(List<({String id, int sortOrder})> items) async {
    for (final item in items) {
      await _supabase
          .from('instahelp_modes')
          .update({'sort_order': item.sortOrder})
          .eq('id', item.id);
    }
  }

  Future<void> initializeVendorModes(String vendorId) async {
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
    const modeSortOrders = {'scheduled': 0, 'instant': 1, 'car_wash': 2};
    final toCreate = <Map<String, dynamic>>[];
    for (final type in ['scheduled', 'instant', 'car_wash']) {
      if (!existingTypes.contains(type)) {
        toCreate.add({'vendor_id': vendorId, 'mode_type': type, 'is_active': false, 'sort_order': modeSortOrders[type] ?? 0});
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

  // ── Dismiss rejected request ──────────────────────────────────────────────

  Future<void> dismissRejectedRequest(String id) async {
    await _supabase
        .from('vendor_service_requests')
        .delete()
        .eq('id', id)
        .eq('status', 'rejected');
  }

  // ── Requests (pending + rejected) ─────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchModeRequests(String modeId) async {
    final data = await _supabase
        .from('vendor_service_requests')
        .select('id, request_type, service_name, status, rejection_reason, instahelp_resource_id, request_data, created_at')
        .eq('mode_id', modeId)
        .inFilter('status', ['pending', 'rejected'])
        .order('created_at');
    return List<Map<String, dynamic>>.from(data as List);
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
    final modeRow = await _supabase
        .from('instahelp_modes')
        .select('vendor_id')
        .eq('id', modeId)
        .single();
    final vendorId = modeRow['vendor_id'] as String;

    final eligible = await _supabase.rpc(
        'check_vendor_instahelp_eligibility', params: {'p_vendor_id': vendorId});
    if (eligible != true) {
      throw Exception('An active InstaHelp subscription is required to add services.');
    }

    await _supabase.from('vendor_service_requests').insert({
      'vendor_id': vendorId,
      'mode_id': modeId,
      'service_name': label,
      'request_type': 'instahelp_new_duration',
      'status': 'pending',
      'request_data': {
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
      },
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
    final existing = await _supabase
        .from('vendor_service_requests')
        .select('id')
        .eq('instahelp_resource_id', id)
        .eq('status', 'pending')
        .maybeSingle();
    if (existing != null) {
      throw Exception('A change is already pending approval for this duration.');
    }

    final row = await _supabase
        .from('instahelp_durations')
        .select('mode_id, sort_order, instahelp_modes!inner(vendor_id)')
        .eq('id', id)
        .single();

    await _supabase.from('vendor_service_requests').insert({
      'vendor_id': (row['instahelp_modes'] as Map)['vendor_id'],
      'mode_id': row['mode_id'],
      'instahelp_resource_id': id,
      'service_name': label,
      'request_type': 'instahelp_edit_duration',
      'status': 'pending',
      'request_data': {
        'label': label,
        'duration_minutes': durationMinutes,
        'price': price,
        'discount_type': discountType,
        'discount_value': discountValue,
        'is_active': isActive,
        'sort_order': row['sort_order'] ?? 0,
        'slot_start_time': slotStartTime,
        'slot_end_time': slotEndTime,
        'slot_interval_minutes': slotIntervalMinutes,
        'max_bookings_per_slot': maxBookingsPerSlot,
      },
    });
  }

  Future<void> toggleDurationActive(String id, {required bool isActive}) async {
    final existing = await _supabase
        .from('vendor_service_requests')
        .select('id')
        .eq('instahelp_resource_id', id)
        .eq('status', 'pending')
        .maybeSingle();
    if (existing != null) {
      throw Exception('A change is already pending approval for this duration.');
    }

    final row = await _supabase
        .from('instahelp_durations')
        .select('*, instahelp_modes!inner(vendor_id)')
        .eq('id', id)
        .single();

    await _supabase.from('vendor_service_requests').insert({
      'vendor_id': (row['instahelp_modes'] as Map)['vendor_id'],
      'mode_id': row['mode_id'],
      'instahelp_resource_id': id,
      'service_name': row['label'],
      'request_type': 'instahelp_edit_duration',
      'status': 'pending',
      'request_data': {
        'label': row['label'],
        'duration_minutes': row['duration_minutes'],
        'price': row['price'],
        'discount_type': row['discount_type'] ?? 'none',
        'discount_value': row['discount_value'] ?? 0,
        'is_active': isActive,
        'sort_order': row['sort_order'] ?? 0,
        'slot_start_time': row['slot_start_time'] ?? '08:00',
        'slot_end_time': row['slot_end_time'] ?? '20:00',
        'slot_interval_minutes': row['slot_interval_minutes'] ?? 60,
        'max_bookings_per_slot': row['max_bookings_per_slot'] ?? 10,
      },
    });
  }

  Future<void> deleteDuration(String id) async {
    final existing = await _supabase
        .from('vendor_service_requests')
        .select('id')
        .eq('instahelp_resource_id', id)
        .eq('status', 'pending')
        .maybeSingle();
    if (existing != null) {
      throw Exception('A change is already pending approval for this duration.');
    }

    final row = await _supabase
        .from('instahelp_durations')
        .select('mode_id, label, instahelp_modes!inner(vendor_id)')
        .eq('id', id)
        .single();

    await _supabase.from('vendor_service_requests').insert({
      'vendor_id': (row['instahelp_modes'] as Map)['vendor_id'],
      'mode_id': row['mode_id'],
      'instahelp_resource_id': id,
      'service_name': row['label'],
      'request_type': 'instahelp_delete_duration',
      'status': 'pending',
      'request_data': <String, dynamic>{},
    });
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
        .order('sort_order', ascending: true);
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
    final modeRow = await _supabase
        .from('instahelp_modes')
        .select('vendor_id')
        .eq('id', modeId)
        .single();
    final vendorId = modeRow['vendor_id'] as String;

    final eligible = await _supabase.rpc(
        'check_vendor_instahelp_eligibility', params: {'p_vendor_id': vendorId});
    if (eligible != true) {
      throw Exception('An active InstaHelp subscription is required to add services.');
    }

    await _supabase.from('vendor_service_requests').insert({
      'vendor_id': vendorId,
      'mode_id': modeId,
      'service_name': title,
      'request_type': 'instahelp_new_activity',
      'status': 'pending',
      'request_data': {
        'title': title,
        'included_items': includedItems,
        'excluded_items': excludedItems,
        'is_active': isActive,
        'sort_order': sortOrder,
      },
    });
  }

  Future<void> updateActivity(
    String id, {
    required String title,
    required List<String> includedItems,
    required List<String> excludedItems,
    required bool isActive,
  }) async {
    final existing = await _supabase
        .from('vendor_service_requests')
        .select('id')
        .eq('instahelp_resource_id', id)
        .eq('status', 'pending')
        .maybeSingle();
    if (existing != null) {
      throw Exception('A change is already pending approval for this activity.');
    }

    final row = await _supabase
        .from('instahelp_activities')
        .select('mode_id, sort_order, instahelp_modes!inner(vendor_id)')
        .eq('id', id)
        .single();

    await _supabase.from('vendor_service_requests').insert({
      'vendor_id': (row['instahelp_modes'] as Map)['vendor_id'],
      'mode_id': row['mode_id'],
      'instahelp_resource_id': id,
      'service_name': title,
      'request_type': 'instahelp_edit_activity',
      'status': 'pending',
      'request_data': {
        'title': title,
        'included_items': includedItems,
        'excluded_items': excludedItems,
        'is_active': isActive,
        'sort_order': row['sort_order'] ?? 0,
      },
    });
  }

  Future<void> toggleActivityActive(String id, {required bool isActive}) async {
    final existing = await _supabase
        .from('vendor_service_requests')
        .select('id')
        .eq('instahelp_resource_id', id)
        .eq('status', 'pending')
        .maybeSingle();
    if (existing != null) {
      throw Exception('A change is already pending approval for this activity.');
    }

    final row = await _supabase
        .from('instahelp_activities')
        .select('*, instahelp_modes!inner(vendor_id)')
        .eq('id', id)
        .single();

    await _supabase.from('vendor_service_requests').insert({
      'vendor_id': (row['instahelp_modes'] as Map)['vendor_id'],
      'mode_id': row['mode_id'],
      'instahelp_resource_id': id,
      'service_name': row['title'],
      'request_type': 'instahelp_edit_activity',
      'status': 'pending',
      'request_data': {
        'title': row['title'],
        'included_items': (row['included_items'] as List?)?.cast<String>() ?? [],
        'excluded_items': (row['excluded_items'] as List?)?.cast<String>() ?? [],
        'is_active': isActive,
        'sort_order': row['sort_order'] ?? 0,
      },
    });
  }

  Future<void> deleteActivity(String id) async {
    final existing = await _supabase
        .from('vendor_service_requests')
        .select('id')
        .eq('instahelp_resource_id', id)
        .eq('status', 'pending')
        .maybeSingle();
    if (existing != null) {
      throw Exception('A change is already pending approval for this activity.');
    }

    final row = await _supabase
        .from('instahelp_activities')
        .select('mode_id, title, instahelp_modes!inner(vendor_id)')
        .eq('id', id)
        .single();

    await _supabase.from('vendor_service_requests').insert({
      'vendor_id': (row['instahelp_modes'] as Map)['vendor_id'],
      'mode_id': row['mode_id'],
      'instahelp_resource_id': id,
      'service_name': row['title'],
      'request_type': 'instahelp_delete_activity',
      'status': 'pending',
      'request_data': <String, dynamic>{},
    });
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
    final existing = await _supabase
        .from('vendor_service_requests')
        .select('id')
        .eq('mode_id', modeId)
        .eq('request_type', 'instahelp_slot_config')
        .eq('status', 'pending')
        .maybeSingle();
    if (existing != null) {
      throw Exception('A slot configuration change is already pending approval.');
    }

    final modeRow = await _supabase
        .from('instahelp_modes')
        .select('vendor_id')
        .eq('id', modeId)
        .single();

    await _supabase.from('vendor_service_requests').insert({
      'vendor_id': modeRow['vendor_id'],
      'mode_id': modeId,
      'service_name': 'Slot Configuration',
      'request_type': 'instahelp_slot_config',
      'status': 'pending',
      'request_data': {
        'working_days': workingDays,
        'start_time': startTime,
        'end_time': endTime,
        'slot_interval_minutes': slotIntervalMinutes,
        'max_bookings_per_slot': maxBookingsPerSlot,
        'is_active': isActive,
      },
    });
  }

  Future<void> deleteSlotConfig(String modeId) async {
    final existing = await _supabase
        .from('vendor_service_requests')
        .select('id')
        .eq('mode_id', modeId)
        .inFilter('request_type', ['instahelp_slot_config', 'instahelp_delete_slot_config'])
        .eq('status', 'pending')
        .maybeSingle();
    if (existing != null) {
      throw Exception('A slot configuration change is already pending approval.');
    }

    final modeRow = await _supabase
        .from('instahelp_modes')
        .select('vendor_id')
        .eq('id', modeId)
        .single();

    await _supabase.from('vendor_service_requests').insert({
      'vendor_id': modeRow['vendor_id'],
      'mode_id': modeId,
      'service_name': 'Slot Configuration',
      'request_type': 'instahelp_delete_slot_config',
      'status': 'pending',
      'request_data': <String, dynamic>{},
    });
  }

  // ── Financial Config ──────────────────────────────────────────────────────

  Future<InstaHelpFinancialConfig?> fetchFinancialConfig(String modeId) async {
    final data = await _supabase
        .from('instahelp_financial_config')
        .select()
        .eq('mode_id', modeId)
        .maybeSingle();
    if (data == null) return null;
    return InstaHelpFinancialConfig.fromMap(data);
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
    final existing = await _supabase
        .from('vendor_service_requests')
        .select('id')
        .eq('mode_id', modeId)
        .eq('request_type', 'instahelp_financial_config')
        .eq('status', 'pending')
        .maybeSingle();
    if (existing != null) {
      throw Exception('A financial configuration change is already pending approval.');
    }

    final modeRow = await _supabase
        .from('instahelp_modes')
        .select('vendor_id')
        .eq('id', modeId)
        .single();

    await _supabase.from('vendor_service_requests').insert({
      'vendor_id': modeRow['vendor_id'],
      'mode_id': modeId,
      'service_name': 'Financial Configuration',
      'request_type': 'instahelp_financial_config',
      'status': 'pending',
      'request_data': {
        'gst_percent': gstPercent,
        'surge_fee_enabled': surgeFeeEnabled,
        'surge_fee_type': surgeFeeType,
        'surge_fee_value': surgeFeeValue,
        'service_charge_enabled': serviceChargeEnabled,
        'service_charge_type': serviceChargeType,
        'service_charge_value': serviceChargeValue,
      },
    });
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
}
