import 'package:supabase_flutter/supabase_flutter.dart';

class CalendarScheduleEntry {
  final String? id;
  final String? serviceId; // null = global override
  final DateTime scheduleDate;
  final List<String> slots;
  final int maxBookingsPerSlot;
  final bool isEnabled;
  final String? slotStartTime;
  final String? slotEndTime;
  final int slotIntervalHours;
  final int slotIntervalMinutes;

  const CalendarScheduleEntry({
    this.id,
    this.serviceId,
    required this.scheduleDate,
    required this.slots,
    this.maxBookingsPerSlot = 5,
    this.isEnabled = true,
    this.slotStartTime,
    this.slotEndTime,
    this.slotIntervalHours = 0,
    this.slotIntervalMinutes = 30,
  });

  factory CalendarScheduleEntry.fromMap(Map<String, dynamic> m) =>
      CalendarScheduleEntry(
        id: m['id'] as String?,
        serviceId: m['service_id'] as String?,
        scheduleDate: DateTime.parse(m['schedule_date'] as String),
        slots: ((m['slots'] as List?)?.cast<String>()) ?? [],
        maxBookingsPerSlot: (m['max_bookings_per_slot'] as num?)?.toInt() ?? 5,
        isEnabled: (m['is_enabled'] as bool?) ?? true,
        slotStartTime: m['slot_start_time'] as String?,
        slotEndTime: m['slot_end_time'] as String?,
        slotIntervalHours: (m['slot_interval_hours'] as num?)?.toInt() ?? 0,
        slotIntervalMinutes: (m['slot_interval_minutes'] as num?)?.toInt() ?? 30,
      );

  Map<String, dynamic> _baseMap() => {
        'slots': slots,
        'max_bookings_per_slot': maxBookingsPerSlot,
        'is_enabled': isEnabled,
        'slot_start_time': slotStartTime,
        'slot_end_time': slotEndTime,
        'slot_interval_hours': slotIntervalHours,
        'slot_interval_minutes': slotIntervalMinutes,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
}

class CalendarScheduleRepository {
  final SupabaseClient _client;
  const CalendarScheduleRepository(this._client);

  Future<List<CalendarScheduleEntry>> fetchGlobal() async {
    final rows = await _client
        .from('calendar_schedules')
        .select()
        .isFilter('service_id', null)
        .order('schedule_date');
    return rows.map((r) => CalendarScheduleEntry.fromMap(r)).toList();
  }

  Future<List<CalendarScheduleEntry>> fetchForService(String serviceId) async {
    final rows = await _client
        .from('calendar_schedules')
        .select()
        .eq('service_id', serviceId)
        .order('schedule_date');
    return rows.map((r) => CalendarScheduleEntry.fromMap(r)).toList();
  }

  Future<CalendarScheduleEntry> save(CalendarScheduleEntry entry) async {
    if (entry.id != null) {
      final rows = await _client
          .from('calendar_schedules')
          .update(entry._baseMap())
          .eq('id', entry.id!)
          .select();
      if (rows.isNotEmpty) return CalendarScheduleEntry.fromMap(rows.first);
    }
    final dateStr = entry.scheduleDate.toIso8601String().split('T').first;
    final insertMap = <String, dynamic>{
      ...entry._baseMap(),
      'schedule_date': dateStr,
      if (entry.serviceId != null) 'service_id': entry.serviceId,
    };
    final rows = await _client
        .from('calendar_schedules')
        .insert(insertMap)
        .select();
    return CalendarScheduleEntry.fromMap(rows.first);
  }

  Future<void> delete(String id) async {
    await _client.from('calendar_schedules').delete().eq('id', id);
  }
}
