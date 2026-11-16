import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/call_session.dart';

abstract class CallBridgeService {
  Future<CallSession> initiateCallSession({
    required String bookingId,
    required String callerRole,
  });

  Future<CallSession?> getCallSession(String sessionId);
}

class ExotelCallService implements CallBridgeService {
  final SupabaseClient _client;

  ExotelCallService(this._client);

  @override
  Future<CallSession> initiateCallSession({
    required String bookingId,
    required String callerRole,
  }) async {
    final response = await _client.functions.invoke(
      'initiate-exotel-call',
      body: {
        'booking_id': bookingId,
        'caller_role': callerRole,
      },
    );

    if (response.status != 200) {
      final data = response.data;
      String message = 'Call initiation failed';
      if (data is Map) {
        message = data['error'] as String? ?? message;
      }
      debugPrint('[ExotelCallService] initiate failed: $message (${response.status})');
      throw Exception(message);
    }

    final data = response.data as Map<String, dynamic>;
    final sessionId = data['session_id'] as String?;
    if (sessionId == null) throw Exception('No session_id returned');

    final row = await _client
        .from('call_sessions')
        .select()
        .eq('id', sessionId)
        .single();

    return CallSession.fromMap(row);
  }

  @override
  Future<CallSession?> getCallSession(String sessionId) async {
    try {
      final row = await _client
          .from('call_sessions')
          .select()
          .eq('id', sessionId)
          .maybeSingle();
      if (row == null) return null;
      return CallSession.fromMap(row);
    } catch (e) {
      debugPrint('[ExotelCallService] getCallSession error: $e');
      return null;
    }
  }
}

final callBridgeServiceProvider = Provider<ExotelCallService>((ref) {
  return ExotelCallService(Supabase.instance.client);
});

// Streams call_provider_configs via Supabase Realtime.
// Re-emits immediately whenever admin toggles is_enabled — no restart needed.
final callProviderEnabledProvider = StreamProvider<bool>((ref) {
  return Supabase.instance.client
      .from('call_provider_configs')
      .stream(primaryKey: ['id'])
      .eq('provider', 'exotel')
      .map((rows) {
        if (rows.isEmpty) return false;
        final row = rows.first;
        final enabled = row['is_enabled'] as bool? ?? false;
        final sid = row['account_sid'] as String?;
        final phone = row['exophone'] as String?;
        return enabled &&
            (sid?.isNotEmpty ?? false) &&
            (phone?.isNotEmpty ?? false);
      });
});
