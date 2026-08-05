import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/admin_call_session.dart';

class CallMonitoringRepository {
  final SupabaseClient _client;

  CallMonitoringRepository(this._client);

  Future<List<AdminCallSession>> fetchCallSessions() async {
    try {
      final response = await _client
          .from('call_sessions')
          .select('''
            *,
            bookings!booking_id(booking_number)
          ''')
          .order('initiated_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(response as List);
      return list.map(AdminCallSession.fromMap).toList();
    } catch (e) {
      debugPrint('[DODO][CallMonitoringRepository] Fetch call_sessions error: $e');
      return [];
    }
  }

  Stream<List<AdminCallSession>> streamCallSessions() {
    final controller = StreamController<List<AdminCallSession>>();

    fetchCallSessions().then((data) {
      if (!controller.isClosed) controller.add(data);
    });

    final channel = _client.channel('public:call_sessions_monitoring').onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'call_sessions',
      callback: (_) async {
        final updated = await fetchCallSessions();
        if (!controller.isClosed) controller.add(updated);
      },
    ).subscribe();

    controller.onCancel = () {
      _client.removeChannel(channel);
      controller.close();
    };

    return controller.stream;
  }
}
