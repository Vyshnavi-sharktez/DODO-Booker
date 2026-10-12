import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fetches available time-slot labels for a service on a given date.
///
/// Resolution order (matches customer app):
///   1. service_scheduling row → if use_global_schedule=true, fall back to (2)
///   2. global_scheduling row
///
/// Then: filter by working_days, check check_availability_block RPC,
/// return the slot labels that are neither blocked nor full.
class AdminSlotService {
  static Future<List<String>> fetchSlots(
    SupabaseClient client,
    String serviceId,
    DateTime date,
  ) async {
    final dateStr = date.toIso8601String().split('T').first;

    // 0. Check calendar overrides for this specific date (highest priority)
    // Service-level override takes priority over global.
    if (serviceId.isNotEmpty) {
      try {
        final calRows = await client
            .from('calendar_schedules')
            .select()
            .eq('service_id', serviceId)
            .eq('schedule_date', dateStr);
        if (calRows.isNotEmpty) {
          final calCfg = Map<String, dynamic>.from(calRows.first);
          if ((calCfg['is_enabled'] as bool?) != true) return [];
          return (calCfg['slots'] as List?)
                  ?.map((e) => (e as String).trim())
                  .where((s) => s.isNotEmpty)
                  .toList() ??
              [];
        }
      } catch (e) {
        debugPrint('[AdminSlotService] service calendar check failed (non-fatal): $e');
      }
    }
    try {
      final globalCalRows = await client
          .from('calendar_schedules')
          .select()
          .isFilter('service_id', null)
          .eq('schedule_date', dateStr);
      if (globalCalRows.isNotEmpty) {
        final calCfg = Map<String, dynamic>.from(globalCalRows.first);
        if ((calCfg['is_enabled'] as bool?) != true) return [];
        return (calCfg['slots'] as List?)
                ?.map((e) => (e as String).trim())
                .where((s) => s.isNotEmpty)
                .toList() ??
            [];
      }
    } catch (e) {
      debugPrint('[AdminSlotService] global calendar check failed (non-fatal): $e');
    }

    Map<String, dynamic>? scheduleCfg;
    bool isEnabled = true;

    // 1. Load scheduling config
    if (serviceId.isNotEmpty) {
      try {
        final rows = await client
            .from('service_scheduling')
            .select()
            .eq('service_id', serviceId);
        if (rows.isNotEmpty) {
          final svcCfg = Map<String, dynamic>.from(rows.first);
          isEnabled = (svcCfg['is_enabled'] as bool?) ?? true;
          final useGlobal = (svcCfg['use_global_schedule'] as bool?) ?? false;
          if (useGlobal) {
            final globalRows = await client
                .from('global_scheduling')
                .select()
                .order('updated_at', ascending: false)
                .limit(1);
            if (globalRows.isNotEmpty) {
              scheduleCfg = Map<String, dynamic>.from(globalRows.first);
              isEnabled = (scheduleCfg['is_enabled'] as bool?) ?? false;
            }
          } else {
            scheduleCfg = svcCfg;
          }
        }
      } catch (e) {
        debugPrint('[AdminSlotService] service_scheduling query failed: $e');
      }
    }

    // Fall back to global scheduling if still no config
    if (scheduleCfg == null) {
      try {
        final globalRows = await client
            .from('global_scheduling')
            .select()
            .order('updated_at', ascending: false)
            .limit(1);
        if (globalRows.isNotEmpty) {
          scheduleCfg = Map<String, dynamic>.from(globalRows.first);
          isEnabled = (scheduleCfg['is_enabled'] as bool?) ?? false;
        }
      } catch (e) {
        debugPrint('[AdminSlotService] global_scheduling query failed: $e');
      }
    }

    if (scheduleCfg == null || !isEnabled) return [];

    // 2. Check working day (Dart weekday: Mon=1…Sun=7; DB: Sun=0…Sat=6)
    final dayOfWeek = date.weekday == 7 ? 0 : date.weekday;
    final workingDays = (scheduleCfg['working_days'] as List?)
            ?.map((e) => (e as num).toInt())
            .toList() ??
        [1, 2, 3, 4, 5];
    if (!workingDays.contains(dayOfWeek)) return [];

    // 3. Check availability blocks (non-fatal)
    var blockedSlots = <String>[];
    if (serviceId.isNotEmpty) {
      try {
        final blockResult =
            await client.rpc('check_availability_block', params: {
          'p_service_id': serviceId,
          'p_vendor_id': null,
          'p_date': dateStr,
        });
        if (blockResult is List && blockResult.isNotEmpty) {
          final row = blockResult.first as Map<String, dynamic>;
          if (row['is_full_day_blocked'] == true) return [];
          final raw = row['blocked_slots'];
          if (raw is List && raw.isNotEmpty) {
            blockedSlots = raw.cast<String>();
          }
        }
      } catch (e) {
        debugPrint(
            '[AdminSlotService] check_availability_block failed (non-fatal): $e');
      }
    }

    // 4. Return filtered slot labels
    return (scheduleCfg['slots'] as List?)
            ?.map((e) => (e as String).trim())
            .where((s) => s.isNotEmpty && !blockedSlots.contains(s))
            .toList() ??
        [];
  }
}
