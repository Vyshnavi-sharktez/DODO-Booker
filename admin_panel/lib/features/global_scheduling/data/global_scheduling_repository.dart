import 'package:supabase_flutter/supabase_flutter.dart';

class GlobalSchedulingConfig {
  final String? id;
  final bool isEnabled;
  final List<int> workingDays;      // 0=Sun … 6=Sat
  final int maxBookingsPerSlot;
  final List<String> slots;         // e.g. ["09:00 AM", "11:30 AM"]

  const GlobalSchedulingConfig({
    this.id,
    required this.isEnabled,
    required this.workingDays,
    required this.maxBookingsPerSlot,
    required this.slots,
  });

  factory GlobalSchedulingConfig.defaults() => const GlobalSchedulingConfig(
        isEnabled: false,
        workingDays: [1, 2, 3, 4, 5],
        maxBookingsPerSlot: 5,
        slots: [],
      );

  factory GlobalSchedulingConfig.fromMap(Map<String, dynamic> m) =>
      GlobalSchedulingConfig(
        id: m['id'] as String?,
        isEnabled: (m['is_enabled'] as bool?) ?? false,
        workingDays: ((m['working_days'] as List?)
                ?.map((e) => (e as num).toInt())
                .toList()) ??
            [1, 2, 3, 4, 5],
        maxBookingsPerSlot: (m['max_bookings_per_slot'] as num?)?.toInt() ?? 5,
        slots: ((m['slots'] as List?)?.cast<String>()) ?? [],
      );

  Map<String, dynamic> toMap() => {
        'is_enabled': isEnabled,
        'working_days': workingDays,
        'max_bookings_per_slot': maxBookingsPerSlot,
        'slots': slots,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
}

class GlobalSchedulingRepository {
  final SupabaseClient _client;
  const GlobalSchedulingRepository(this._client);

  /// Fetches the single global scheduling row.
  /// Falls back to in-memory defaults if the table is empty (should never
  /// happen after migration, but keeps the page safe).
  Future<GlobalSchedulingConfig> fetch() async {
    final rows = await _client.from('global_scheduling').select().limit(1);
    if (rows.isEmpty) return GlobalSchedulingConfig.defaults();
    return GlobalSchedulingConfig.fromMap(rows.first);
  }

  /// Persists the config and returns the saved version.
  /// Uses UPDATE when an id is available (normal path after migration seed),
  /// INSERT otherwise (fallback if the table was somehow empty).
  Future<GlobalSchedulingConfig> save(GlobalSchedulingConfig config) async {
    final payload = config.toMap();
    if (config.id != null) {
      await _client
          .from('global_scheduling')
          .update(payload)
          .eq('id', config.id!);
      return config;
    } else {
      final row = await _client
          .from('global_scheduling')
          .insert(payload)
          .select()
          .single();
      return GlobalSchedulingConfig.fromMap(row);
    }
  }
}
