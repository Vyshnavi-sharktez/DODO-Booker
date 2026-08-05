import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/call_session.dart';

abstract class CallBridgeService {
  Future<CallSession> initiateCallSession({
    required String bookingId,
    required String callerId,
    required String calleeId,
    required String callerRole,
    required String bookingStatus,
  });

  Future<CallSession?> getCallSession(String sessionId);

  Future<List<CallSession>> getBookingCallSessions(String bookingId);

  Future<CallSession> updateCallStatus(
    String sessionId,
    String status, {
    int? durationSeconds,
    DateTime? endedAt,
  });

  Future<void> terminateCallSession(String sessionId, {int? durationSeconds});
}

class MockCallBridgeService implements CallBridgeService {
  final SupabaseClient? _client;
  final List<CallSession> _inMemorySessions = [];

  MockCallBridgeService([this._client]);

  static const _allowedStatuses = [
    'assigned',
    'assigned_to_dodo_team',
    'accepted',
    'en_route',
    'in_progress',
    'started',
    'awaiting_verification',
  ];

  String _toValidUuid(String input) {
    final clean = input.trim();
    if (clean.isEmpty) return '00000000-0000-0000-0000-000000000000';
    final uuidRegex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    if (uuidRegex.hasMatch(clean)) return clean;
    final hex = clean.codeUnits
        .map((c) => c.toRadixString(16).padLeft(2, '0'))
        .join();
    final padded = hex.padRight(32, '0').substring(0, 32);
    return '${padded.substring(0, 8)}-${padded.substring(8, 12)}-${padded.substring(12, 16)}-${padded.substring(16, 20)}-${padded.substring(20, 32)}';
  }

  @override
  Future<CallSession> initiateCallSession({
    required String bookingId,
    required String callerId,
    required String calleeId,
    required String callerRole,
    required String bookingStatus,
  }) async {
    final statusLower = bookingStatus.toLowerCase();
    if (!_allowedStatuses.contains(statusLower)) {
      throw StateError(
        'Call bridge is only active for assigned, accepted, or in-progress bookings.',
      );
    }

    final now = DateTime.now();
    final validBookingId = _toValidUuid(bookingId);
    final validCallerId = _toValidUuid(callerId);
    final validCalleeId = _toValidUuid(calleeId);

    if (_client != null) {
      String targetBookingId = validBookingId;
      try {
        final existingBooking = await _client
            .from('bookings')
            .select('id')
            .eq('id', validBookingId)
            .maybeSingle();

        if (existingBooking == null) {
          final firstBooking = await _client
              .from('bookings')
              .select('id')
              .limit(1)
              .maybeSingle();
          if (firstBooking != null && firstBooking['id'] != null) {
            targetBookingId = firstBooking['id'] as String;
          }
        }
      } catch (e) {
        debugPrint('[DODO][VendorCallBridgeService] Booking FK lookup warning: $e');
      }

      final payload = {
        'booking_id': targetBookingId,
        'caller_id': validCallerId,
        'callee_id': validCalleeId,
        'caller_role': callerRole,
        'virtual_number': '+91-80000-DODO1',
        'status': 'initiated',
        'initiated_at': now.toIso8601String(),
      };

      try {
        final response = await _client
            .from('call_sessions')
            .insert(payload)
            .select()
            .single();

        debugPrint(
          '[DODO][VendorCallBridgeService] Persisted call session in Supabase with ID: ${response['id']} (caller_role: $callerRole)',
        );
        return CallSession.fromMap(response);
      } catch (e, st) {
        debugPrint(
          '[DODO][VendorCallBridgeService] ERROR persisting call session in Supabase: $e\n$st',
        );
        throw Exception('Failed to persist call session in Supabase: $e');
      }
    }

    final newSession = CallSession(
      id: 'session_${now.millisecondsSinceEpoch}',
      bookingId: validBookingId,
      callerId: validCallerId,
      calleeId: validCalleeId,
      callerRole: callerRole,
      virtualNumber: '+91-80000-DODO1',
      status: 'initiated',
      initiatedAt: now,
      createdAt: now,
      updatedAt: now,
    );

    _inMemorySessions.add(newSession);
    return newSession;
  }

  @override
  Future<CallSession?> getCallSession(String sessionId) async {
    if (_client != null) {
      try {
        final res = await _client
            .from('call_sessions')
            .select('*')
            .eq('id', sessionId)
            .maybeSingle();
        if (res != null) return CallSession.fromMap(res);
      } catch (e) {
        debugPrint('[DODO][VendorCallBridgeService] Warning: getCallSession failed: $e');
      }
    }
    return _inMemorySessions.where((s) => s.id == sessionId).firstOrNull;
  }

  @override
  Future<List<CallSession>> getBookingCallSessions(String bookingId) async {
    final validBookingId = _toValidUuid(bookingId);
    if (_client != null) {
      try {
        final res = await _client
            .from('call_sessions')
            .select('*')
            .eq('booking_id', validBookingId)
            .order('initiated_at', ascending: false);
        final list = List<Map<String, dynamic>>.from(res as List);
        return list.map(CallSession.fromMap).toList();
      } catch (e) {
        debugPrint('[DODO][VendorCallBridgeService] Warning: getBookingCallSessions failed: $e');
      }
    }
    return _inMemorySessions.where((s) => s.bookingId == validBookingId).toList();
  }

  @override
  Future<CallSession> updateCallStatus(
    String sessionId,
    String status, {
    int? durationSeconds,
    DateTime? endedAt,
  }) async {
    final now = DateTime.now();
    final effectiveEndedAt = (status == 'ended' || status == 'missed' || status == 'failed')
        ? (endedAt ?? now)
        : null;

    if (_client != null) {
      try {
        final payload = <String, dynamic>{
          'status': status,
          'updated_at': now.toIso8601String(),
        };
        if (effectiveEndedAt != null) {
          payload['ended_at'] = effectiveEndedAt.toIso8601String();
        }

        int finalDuration = durationSeconds ?? 0;

        if (finalDuration <= 0 && effectiveEndedAt != null) {
          try {
            final existing = await _client
                .from('call_sessions')
                .select('initiated_at')
                .eq('id', sessionId)
                .maybeSingle();

            if (existing != null && existing['initiated_at'] != null) {
              final initiatedAt = DateTime.tryParse(existing['initiated_at'] as String);
              if (initiatedAt != null) {
                final diff = effectiveEndedAt.difference(initiatedAt).inSeconds;
                if (diff > 0) finalDuration = diff;
              }
            }
          } catch (e) {
            debugPrint('[DODO][VendorCallBridgeService] Warning calculating duration: $e');
          }
        }

        if (effectiveEndedAt != null || finalDuration > 0) {
          payload['duration_seconds'] = finalDuration;
        }

        final res = await _client
            .from('call_sessions')
            .update(payload)
            .eq('id', sessionId)
            .select()
            .single();

        debugPrint(
          '[DODO][VendorCallBridgeService] Updated call session in Supabase: $sessionId -> status=$status, duration_seconds=$finalDuration, ended_at=$effectiveEndedAt',
        );
        return CallSession.fromMap(res);
      } catch (e, st) {
        debugPrint(
          '[DODO][VendorCallBridgeService] ERROR updating call session status in Supabase: $e\n$st',
        );
        throw Exception('Failed to update call session status in Supabase: $e');
      }
    }

    final idx = _inMemorySessions.indexWhere((s) => s.id == sessionId);
    if (idx != -1) {
      final existing = _inMemorySessions[idx];
      final updated = existing.copyWith(
        status: status,
        endedAt: effectiveEndedAt ?? existing.endedAt,
        durationSeconds: durationSeconds ?? existing.durationSeconds,
        updatedAt: now,
      );
      _inMemorySessions[idx] = updated;
      return updated;
    }

    return CallSession(
      id: sessionId,
      bookingId: '',
      callerId: '',
      calleeId: '',
      callerRole: 'vendor',
      status: status,
      initiatedAt: now,
      endedAt: effectiveEndedAt,
      durationSeconds: durationSeconds ?? 0,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<void> terminateCallSession(String sessionId, {int? durationSeconds}) async {
    await updateCallStatus(sessionId, 'ended', durationSeconds: durationSeconds);
  }
}

final vendorCallBridgeServiceProvider = Provider<CallBridgeService>((ref) {
  return MockCallBridgeService(Supabase.instance.client);
});
