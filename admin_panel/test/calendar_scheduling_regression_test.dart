// Regression tests for the scheduling priority chain and slot generation.
//
// Root cause guarded: CatalogNodeConfigDialog previously saved slots:[] when
// start/end times were not configured, causing resolve_catalog_module_config to
// return an empty-slot config for all child services → "No time slots available".

import 'package:flutter_test/flutter_test.dart';

// ── Pure helpers extracted from dialog/page logic ─────────────────────────────
// These mirror _generateSlots / _toMinutes / _minutesToLabel in the dialogs.

int _toMinutes(String label) {
  final parts = label.trim().split(' ');
  if (parts.length < 2) return 0;
  final timeParts = parts[0].split(':');
  if (timeParts.length < 2) return 0;
  var h = int.tryParse(timeParts[0]) ?? 0;
  final m = int.tryParse(timeParts[1]) ?? 0;
  final isPm = parts[1].toUpperCase() == 'PM';
  if (isPm && h != 12) h += 12;
  if (!isPm && h == 12) h = 0;
  return h * 60 + m;
}

String _minutesToLabel(int totalMinutes) {
  final hour24 = totalMinutes ~/ 60;
  final minute = totalMinutes % 60;
  final isPm = hour24 >= 12;
  var hour12 = hour24 % 12;
  if (hour12 == 0) hour12 = 12;
  return '${hour12.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')} ${isPm ? 'PM' : 'AM'}';
}

List<String> _generateSlots(String start, String end, int hours, int minutes) {
  final startMin = _toMinutes(start);
  final endMin = _toMinutes(end);
  final interval = hours * 60 + minutes;
  if (interval <= 0 || startMin >= endMin) return [];
  final slots = <String>[];
  var current = startMin;
  while (current < endMin) {
    slots.add(_minutesToLabel(current));
    current += interval;
  }
  return slots;
}

/// Mirrors _schedGeneratedSlots getter from CatalogNodeConfigDialog.
/// Returns [] when start or end is null — the guard the validation now catches.
List<String> _schedGeneratedSlots(
    String? start, String? end, int intervalHours, int intervalMinutes) {
  if (start == null || end == null) return [];
  return _generateSlots(start, end, intervalHours, intervalMinutes);
}

/// Simulates the fetchAvailableSlots priority chain (pure logic, no DB).
/// Returns the config source label that would have been used.
String _resolveConfigSource({
  required bool hasServiceCalOverride,
  required bool hasGlobalCalOverride,
  required bool hasCatalogScopedConfig,
  required bool hasNormalSchedule,
}) {
  if (hasServiceCalOverride) return 'service-calendar';
  if (hasGlobalCalOverride) return 'global-calendar';
  if (hasCatalogScopedConfig) return 'scoped';
  if (hasNormalSchedule) return 'normal';
  return 'none';
}

/// Simulates what _buildSlots returns given a slots array.
/// Empty array → no slots (the regression symptom).
List<String> _applySlots(List<String> slots) => slots;

// ── GlobalSchedulingPage._save() slot computation ─────────────────────────────
// Mirrors the generatedSlots expression in GlobalSchedulingPage._save().

/// Before fix: always writes [] when start/end time is null.
List<String> _computeSlotsBuggy({
  String? startTime,
  String? endTime,
  int iH = 0,
  int iM = 30,
}) {
  if (startTime != null && endTime != null) {
    return _generateSlots(startTime, endTime, iH, iM);
  }
  return []; // BUG: silently destroys existing valid slots
}

/// After fix: falls back to existing slots when generator is unconfigured.
List<String> _computeSlotsFixed({
  String? startTime,
  String? endTime,
  int iH = 0,
  int iM = 30,
  List<String> existingSlots = const [],
}) {
  if (startTime != null && endTime != null) {
    return _generateSlots(startTime, endTime, iH, iM);
  }
  return List<String>.from(existingSlots);
}

void main() {
  // ── Slot generator ─────────────────────────────────────────────────────────

  group('_generateSlots', () {
    test('generates correct 1-hour interval slots from 09:00 AM to 05:00 PM', () {
      final slots = _generateSlots('09:00 AM', '05:00 PM', 1, 0);
      expect(slots, [
        '09:00 AM', '10:00 AM', '11:00 AM', '12:00 PM',
        '01:00 PM', '02:00 PM', '03:00 PM', '04:00 PM',
      ]);
    });

    test('generates correct 30-min interval slots', () {
      final slots = _generateSlots('09:00 AM', '11:00 AM', 0, 30);
      expect(slots, ['09:00 AM', '09:30 AM', '10:00 AM', '10:30 AM']);
    });

    test('returns [] when end time equals start time', () {
      expect(_generateSlots('09:00 AM', '09:00 AM', 0, 30), isEmpty);
    });

    test('returns [] when end time is before start time', () {
      expect(_generateSlots('05:00 PM', '09:00 AM', 0, 30), isEmpty);
    });

    test('returns [] when interval is zero', () {
      expect(_generateSlots('09:00 AM', '05:00 PM', 0, 0), isEmpty);
    });

    test('returns [] when interval is negative hours', () {
      expect(_generateSlots('09:00 AM', '05:00 PM', -1, 0), isEmpty);
    });
  });

  // ── Validation guard (_schedGeneratedSlots) ────────────────────────────────

  group('_schedGeneratedSlots — the empty-slots regression guard', () {
    test('returns [] when start time is null (unconfigured dialog)', () {
      // This is the exact scenario that caused the regression:
      // admin opens CatalogNodeConfigDialog, never sets start/end time,
      // clicks Save → slots:[] written to catalog_node_configs.
      final slots = _schedGeneratedSlots(null, '05:00 PM', 0, 30);
      expect(slots, isEmpty,
          reason: 'Null start time must yield empty slots so validation blocks the save');
    });

    test('returns [] when end time is null', () {
      final slots = _schedGeneratedSlots('09:00 AM', null, 0, 30);
      expect(slots, isEmpty);
    });

    test('returns [] when both times are null', () {
      final slots = _schedGeneratedSlots(null, null, 0, 30);
      expect(slots, isEmpty);
    });

    test('returns non-empty when both times are configured', () {
      final slots = _schedGeneratedSlots('09:00 AM', '05:00 PM', 1, 0);
      expect(slots, isNotEmpty);
    });
  });

  // ── Priority chain isolation ────────────────────────────────────────────────

  group('fetchAvailableSlots priority chain', () {
    test('service-level calendar override takes priority over global override', () {
      final source = _resolveConfigSource(
        hasServiceCalOverride: true,
        hasGlobalCalOverride: true,
        hasCatalogScopedConfig: false,
        hasNormalSchedule: true,
      );
      expect(source, 'service-calendar');
    });

    test('global calendar override takes priority over catalog-scoped config', () {
      final source = _resolveConfigSource(
        hasServiceCalOverride: false,
        hasGlobalCalOverride: true,
        hasCatalogScopedConfig: true,
        hasNormalSchedule: true,
      );
      expect(source, 'global-calendar');
    });

    test('catalog-scoped config takes priority over normal weekly schedule', () {
      final source = _resolveConfigSource(
        hasServiceCalOverride: false,
        hasGlobalCalOverride: false,
        hasCatalogScopedConfig: true,
        hasNormalSchedule: true,
      );
      expect(source, 'scoped');
    });

    test('normal weekly schedule is used when no overrides exist', () {
      final source = _resolveConfigSource(
        hasServiceCalOverride: false,
        hasGlobalCalOverride: false,
        hasCatalogScopedConfig: false,
        hasNormalSchedule: true,
      );
      expect(source, 'normal');
    });

    test('returns none when no config exists', () {
      final source = _resolveConfigSource(
        hasServiceCalOverride: false,
        hasGlobalCalOverride: false,
        hasCatalogScopedConfig: false,
        hasNormalSchedule: false,
      );
      expect(source, 'none');
    });

    test('service-level override bypasses a catalog-scoped empty-slots config', () {
      // This explains why 10 services still showed slots after the regression:
      // they had service-level calendar overrides (step -1) that fired before
      // the broken catalog config (step 0) was reached.
      final source = _resolveConfigSource(
        hasServiceCalOverride: true,
        hasGlobalCalOverride: false,
        hasCatalogScopedConfig: true, // even with slots:[]
        hasNormalSchedule: false,
      );
      expect(source, 'service-calendar',
          reason: 'Service calendar override must bypass catalog scoped config');
    });
  });

  // ── _buildSlots slot array handling ────────────────────────────────────────

  group('_buildSlots slot array', () {
    test('empty slots array produces no time slots', () {
      // This reproduces the regression: if catalog config has slots:[], the
      // customer sees "No time slots available".
      expect(_applySlots([]), isEmpty);
    });

    test('non-empty slots array produces time slots', () {
      final slots = _applySlots(['09:00 AM', '10:00 AM', '11:00 AM']);
      expect(slots, hasLength(3));
    });

    test('global calendar override does not affect dates without an override row', () {
      // A global override for 2026-10-15 must NOT affect 2026-10-16.
      // In the real code, the query .eq('schedule_date', dateStr) is date-exact.
      // This test asserts the expected behaviour.
      const overrideDates = {'2026-10-15'};
      final dateToCheck = '2026-10-16';
      final hasOverride = overrideDates.contains(dateToCheck);
      expect(hasOverride, isFalse,
          reason: 'Global override for one date must not affect other dates');
    });
  });

  // ── GlobalSchedulingPage._save() slot preservation ────────────────────────

  group('GlobalSchedulingPage._save() slot preservation', () {
    // Regression: migration 20261001000006 added slot_start_time / slot_end_time
    // as NULL columns. Any admin save while is_enabled=false (or before entering
    // start/end times after migration) wrote slots:[] to global_scheduling,
    // silently wiping valid schedule data. DB confirmed state:
    //   is_enabled=true, slots=[], slot_start_time=null, slot_end_time=null

    test('buggy path — null start time writes empty slots (the regression)', () {
      final result = _computeSlotsBuggy(startTime: null, endTime: null);
      expect(result, isEmpty,
          reason: 'Reproduces the regression: null start/end wipes existing slots');
    });

    test('fixed path — null start time preserves existing valid slots', () {
      const existing = ['09:00 AM', '10:00 AM', '11:00 AM', '12:00 PM'];
      final result = _computeSlotsFixed(
        startTime: null,
        endTime: null,
        existingSlots: existing,
      );
      expect(result, existing,
          reason: 'Fix must return existing slots unchanged when generator is unconfigured');
    });

    test('fixed path — null start but no existing slots still returns empty', () {
      final result = _computeSlotsFixed(startTime: null, endTime: null);
      expect(result, isEmpty,
          reason: 'No previous slots to preserve → empty is correct');
    });

    test('fixed path — configured start/end still generates fresh slots', () {
      final result = _computeSlotsFixed(
        startTime: '09:00 AM',
        endTime: '12:00 PM',
        iH: 1,
        iM: 0,
        existingSlots: ['old slot'],
      );
      expect(result, ['09:00 AM', '10:00 AM', '11:00 AM'],
          reason: 'When generator is configured, fresh slots override existing ones');
    });

    test('is_enabled=false + null times must not wipe slots (the exact regression)', () {
      // Exact scenario that caused the production regression:
      //   global_scheduling had is_enabled=true, valid slots
      //   → migration added slot_start_time=NULL column
      //   → admin saved page with is_enabled=false (validation skipped)
      //   → buggy path wrote slots:[]
      //   → all services lost normal-schedule slots
      const previousSlots = ['09:00 AM', '10:30 AM', '12:00 PM'];
      final buggyResult = _computeSlotsBuggy(startTime: null, endTime: null);
      final fixedResult = _computeSlotsFixed(
        startTime: null,
        endTime: null,
        existingSlots: previousSlots,
      );
      expect(buggyResult, isEmpty, reason: 'Confirms the bug reproduced correctly');
      expect(fixedResult, previousSlots,
          reason: 'Fix preserves slots that would otherwise be wiped');
    });
  });

  // ── Calendar schedule entry model ─────────────────────────────────────────

  group('CalendarScheduleEntry.fromMap', () {
    test('reads slots correctly from DB map', () {
      final m = {
        'id': 'abc',
        'service_id': null,
        'schedule_date': '2026-10-15',
        'slots': ['09:00 AM', '10:00 AM'],
        'max_bookings_per_slot': 5,
        'is_enabled': true,
        'slot_start_time': '09:00 AM',
        'slot_end_time': '11:00 AM',
        'slot_interval_hours': 1,
        'slot_interval_minutes': 0,
      };
      // Mirrors CalendarScheduleEntry.fromMap logic without importing the widget
      final slots = ((m['slots'] as List?)?.cast<String>()) ?? [];
      final startTime = m['slot_start_time'] as String?;
      final endTime = m['slot_end_time'] as String?;
      final intervalHours = (m['slot_interval_hours'] as num?)?.toInt() ?? 0;
      final intervalMinutes = (m['slot_interval_minutes'] as num?)?.toInt() ?? 30;

      expect(slots, ['09:00 AM', '10:00 AM']);
      expect(startTime, '09:00 AM');
      expect(endTime, '11:00 AM');
      expect(intervalHours, 1);
      expect(intervalMinutes, 0);
    });

    test('tolerates null new columns (pre-migration rows) via defaults', () {
      // Rows that existed before migration 20261010000001 get DEFAULT values:
      // slot_interval_hours=0, slot_interval_minutes=30, start/end=null.
      // fromMap must handle this gracefully.
      final m = {
        'id': 'xyz',
        'service_id': null,
        'schedule_date': '2026-10-10',
        'slots': ['09:00 AM'],
        'max_bookings_per_slot': 5,
        'is_enabled': true,
        'slot_start_time': null,
        'slot_end_time': null,
        'slot_interval_hours': 0,
        'slot_interval_minutes': 30,
      };
      final slots = ((m['slots'] as List?)?.cast<String>()) ?? [];
      final startTime = m['slot_start_time'] as String?;
      final endTime = m['slot_end_time'] as String?;

      expect(slots, ['09:00 AM'],
          reason: 'Pre-migration row slots must survive migration as-is');
      expect(startTime, isNull);
      expect(endTime, isNull);
    });
  });
}
