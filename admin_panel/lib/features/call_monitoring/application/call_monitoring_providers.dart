import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/call_monitoring_repository.dart';
import '../domain/models/admin_call_session.dart';

final callMonitoringRepositoryProvider = Provider<CallMonitoringRepository>((ref) {
  return CallMonitoringRepository(Supabase.instance.client);
});

final adminCallSessionsProvider = FutureProvider<List<AdminCallSession>>((ref) {
  return ref.watch(callMonitoringRepositoryProvider).fetchCallSessions();
});

final adminCallSessionsStreamProvider = StreamProvider.autoDispose<List<AdminCallSession>>((ref) {
  return ref.watch(callMonitoringRepositoryProvider).streamCallSessions();
});
