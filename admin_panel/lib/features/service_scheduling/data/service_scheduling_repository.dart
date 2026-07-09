import 'package:supabase_flutter/supabase_flutter.dart';

class ServiceSchedulingConfig {
  final String serviceId;
  final bool isEnabled;
  final List<int> workingDays;      // 0=Sun … 6=Sat
  final int maxBookingsPerSlot;
  final List<String> slots;         // e.g. ["09:00 AM", "11:30 AM", "02:00 PM"]

  const ServiceSchedulingConfig({
    required this.serviceId,
    required this.isEnabled,
    required this.workingDays,
    required this.maxBookingsPerSlot,
    required this.slots,
  });

  factory ServiceSchedulingConfig.defaults(String serviceId) =>
      ServiceSchedulingConfig(
        serviceId: serviceId,
        isEnabled: true,
        workingDays: [1, 2, 3, 4, 5],
        maxBookingsPerSlot: 5,
        slots: [],
      );

  factory ServiceSchedulingConfig.fromMap(Map<String, dynamic> m) =>
      ServiceSchedulingConfig(
        serviceId: m['service_id'] as String,
        isEnabled: (m['is_enabled'] as bool?) ?? true,
        workingDays:
            ((m['working_days'] as List?)?.cast<int>()) ?? [1, 2, 3, 4, 5],
        maxBookingsPerSlot: (m['max_bookings_per_slot'] as int?) ?? 5,
        slots: ((m['slots'] as List?)?.cast<String>()) ?? [],
      );

  Map<String, dynamic> toUpsertMap() => {
        'service_id': serviceId,
        'is_enabled': isEnabled,
        'working_days': workingDays,
        'max_bookings_per_slot': maxBookingsPerSlot,
        'slots': slots,
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
