import 'package:supabase_flutter/supabase_flutter.dart';

class ServiceSchedulingConfig {
  final String serviceId;
  final bool isEnabled;
  final bool useGlobalSchedule;
  final List<int> workingDays;      // 0=Sun … 6=Sat
  final int maxBookingsPerSlot;
  final List<String> slots;         // generated output, e.g. ["09:00 AM", "10:00 AM"]
  final String? slotStartTime;      // generator input, e.g. "09:00 AM"
  final String? slotEndTime;        // generator input, e.g. "06:00 PM"
  final int slotIntervalHours;      // generator input
  final int slotIntervalMinutes;    // generator input

  const ServiceSchedulingConfig({
    required this.serviceId,
    required this.isEnabled,
    this.useGlobalSchedule = false,
    required this.workingDays,
    required this.maxBookingsPerSlot,
    required this.slots,
    this.slotStartTime,
    this.slotEndTime,
    this.slotIntervalHours = 0,
    this.slotIntervalMinutes = 30,
  });

  factory ServiceSchedulingConfig.defaults(String serviceId) =>
      ServiceSchedulingConfig(
        serviceId: serviceId,
        isEnabled: true,
        useGlobalSchedule: false,
        workingDays: [1, 2, 3, 4, 5],
        maxBookingsPerSlot: 5,
        slots: [],
        slotIntervalHours: 0,
        slotIntervalMinutes: 30,
      );

  factory ServiceSchedulingConfig.fromMap(Map<String, dynamic> m) =>
      ServiceSchedulingConfig(
        serviceId: m['service_id'] as String,
        isEnabled: (m['is_enabled'] as bool?) ?? true,
        useGlobalSchedule: (m['use_global_schedule'] as bool?) ?? false,
        workingDays:
            ((m['working_days'] as List?)?.cast<int>()) ?? [1, 2, 3, 4, 5],
        maxBookingsPerSlot: (m['max_bookings_per_slot'] as int?) ?? 5,
        slots: ((m['slots'] as List?)?.cast<String>()) ?? [],
        slotStartTime: m['slot_start_time'] as String?,
        slotEndTime: m['slot_end_time'] as String?,
        slotIntervalHours: (m['slot_interval_hours'] as int?) ?? 0,
        slotIntervalMinutes: (m['slot_interval_minutes'] as int?) ?? 30,
      );

  Map<String, dynamic> toUpsertMap() => {
        'service_id': serviceId,
        'is_enabled': isEnabled,
        'use_global_schedule': useGlobalSchedule,
        'working_days': workingDays,
        'max_bookings_per_slot': maxBookingsPerSlot,
        'slots': slots,
        'slot_start_time': slotStartTime,
        'slot_end_time': slotEndTime,
        'slot_interval_hours': slotIntervalHours,
        'slot_interval_minutes': slotIntervalMinutes,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
}

class ServiceSchedulingRepository {
  final SupabaseClient _client;
  const ServiceSchedulingRepository(this._client);

  Future<ServiceSchedulingConfig?> fetchForService(String serviceId) async {
    final rows = await _client
        .from('service_scheduling')
        .select()
        .eq('service_id', serviceId);
    if (rows.isEmpty) return null;
    return ServiceSchedulingConfig.fromMap(rows.first);
  }

  Future<void> upsert(ServiceSchedulingConfig config) async {
    await _client
        .from('service_scheduling')
        .upsert(config.toUpsertMap(), onConflict: 'service_id');
  }
}
