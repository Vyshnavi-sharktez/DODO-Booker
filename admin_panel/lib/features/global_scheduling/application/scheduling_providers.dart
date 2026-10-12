import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Incremented by AdminRealtimeSync whenever calendar_schedules,
/// global_scheduling, or service_scheduling changes in the DB.
/// Scheduling widgets listen to this to reload without manual refresh.
final schedulingRefreshProvider = StateProvider<int>((ref) => 0);
