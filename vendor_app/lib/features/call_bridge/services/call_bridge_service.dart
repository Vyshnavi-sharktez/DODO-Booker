import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/call_session.dart';

abstract class CallBridgeService {
  /// Initiates a call via the Exotel Edge Function.
  /// Returns a [CallSession] with the session ID and initial status.
  Future<CallSession> initiateCallSession({
    required String bookingId,
    required String callerRole,
  });

  Future<CallSession?> getCallSession(String sessionId);
}

class ExotelCallService implements CallBridgeService {
  final SupabaseClient _client;

  ExotelCallService(this._client);

  static const _callEligibleStatuses = ['accepted', 'en_route', 'in_progress'];

  @override
  Future<CallSession> initiateCallSession({
    required String bookingId,
    required String callerRole,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'initiate-exotel-call',
        body: {
          'booking_id': bookingId,
          'caller_role': callerRole,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final sessionId = data['session_id'] as String?;
      if (sessionId == null) throw Exception('No session_id returned');

      final row = await _client
          .from('call_sessions')
          .select()
          .eq('id', sessionId)
          .single();

      return CallSession.fromMap(row);
    } on FunctionException catch (e) {
      // functions.invoke throws FunctionException for non-2xx responses.
      // Extract the backend error message so the dialog can display it cleanly.
      String message = 'Call initiation failed';
      final details = e.details;
      if (details is Map) {
        message = details['error'] as String? ?? message;
      }
      debugPrint('[ExotelCallService] initiate failed: $message (${e.status})');
      throw Exception(message);
    }
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

  static bool isEligibleStatus(String status) =>
      _callEligibleStatuses.contains(status.toLowerCase());
}

// Provider — returns the real Exotel-backed service
final vendorCallBridgeServiceProvider = Provider<ExotelCallService>((ref) {
  return ExotelCallService(Supabase.instance.client);
});

// Lightweight provider: checks call_provider_configs.is_enabled
// Used by booking_card to gate the call button without hitting a function
final callProviderEnabledProvider = FutureProvider<bool>((ref) async {
  try {
    final row = await Supabase.instance.client
        .from('call_provider_configs')
        .select('is_enabled, account_sid, exophone')
        .eq('provider', 'exotel')
        .maybeSingle();
    if (row == null) return false;
    final enabled = row['is_enabled'] as bool? ?? false;
    final sid = row['account_sid'] as String?;
    final phone = row['exophone'] as String?;
    return enabled && (sid?.isNotEmpty ?? false) && (phone?.isNotEmpty ?? false);
  } catch (_) {
    return false;
  }
});
