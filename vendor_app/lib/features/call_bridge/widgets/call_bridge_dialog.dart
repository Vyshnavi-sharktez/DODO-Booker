import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../domain/models/call_session.dart';
import '../services/call_bridge_service.dart';

class CallBridgeDialog extends ConsumerStatefulWidget {
  final String bookingId;
  final String bookingNumber;
  final String callerRole;
  final String recipientName;
  final String bookingStatus;

  const CallBridgeDialog({
    super.key,
    required this.bookingId,
    required this.bookingNumber,
    required this.callerRole,
    required this.recipientName,
    required this.bookingStatus,
  });

  static Future<void> show(
    BuildContext context, {
    required String bookingId,
    required String bookingNumber,
    required String callerRole,
    required String recipientName,
    required String bookingStatus,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CallBridgeDialog(
        bookingId: bookingId,
        bookingNumber: bookingNumber,
        callerRole: callerRole,
        recipientName: recipientName,
        bookingStatus: bookingStatus,
      ),
    );
  }

  @override
  ConsumerState<CallBridgeDialog> createState() => _CallBridgeDialogState();
}

class _CallBridgeDialogState extends ConsumerState<CallBridgeDialog> {
  CallSession? _session;
  String _statusText = 'Initiating call via Exotel…';
  bool _initiating = true;
  bool _isTerminal = false;
  String? _error;

  StreamSubscription<List<Map<String, dynamic>>>? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _initiateCall();
  }

  Future<void> _initiateCall() async {
    try {
      final service = ref.read(vendorCallBridgeServiceProvider);
      final session = await service.initiateCallSession(
        bookingId: widget.bookingId,
        callerRole: widget.callerRole,
      );

      if (!mounted) return;
      setState(() {
        _session = session;
        _initiating = false;
        _statusText = 'Your phone will ring shortly. Answer to connect.';
      });

      // Subscribe to Realtime updates on this session
      _subscribeRealtime(session.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initiating = false;
        _isTerminal = true;
        _error = e.toString().replaceAll('Exception: ', '');
        _statusText = 'Call failed';
      });
    }
  }

  void _subscribeRealtime(String sessionId) {
    _realtimeSub = Supabase.instance.client
        .from('call_sessions')
        .stream(primaryKey: ['id'])
        .eq('id', sessionId)
        .listen((rows) {
          if (!mounted || rows.isEmpty) return;
          final updated = CallSession.fromMap(rows.first);
          setState(() {
            _session = updated;
            _statusText = _statusForSession(updated);
            _isTerminal = updated.isTerminal;
          });

          if (updated.isTerminal) {
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) Navigator.of(context).pop();
            });
          }
        });
  }

  String _statusForSession(CallSession s) {
    return switch (s.status) {
      'initiated' => 'Connecting to Exotel…',
      'ringing' => 'Your phone is ringing — please answer',
      'connected' => 'Call connected',
      'ended' => 'Call ended (${s.durationFormatted})',
      'missed' => 'Call was not answered',
      'failed' => 'Call failed',
      _ => s.status,
    };
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final status = session?.status ?? 'initiated';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_rounded,
                      size: 14, color: AppColors.primary),
                  SizedBox(width: 6),
                  Text(
                    'DODO SECURE CALL — POWERED BY EXOTEL',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Avatar
            CircleAvatar(
              radius: 36,
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              child: Text(
                widget.recipientName.isNotEmpty
                    ? widget.recipientName[0].toUpperCase()
                    : 'C',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),

            const SizedBox(height: 14),

            Text(
              widget.recipientName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 4),

            Text(
              'Booking #${widget.bookingNumber}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),

            const SizedBox(height: 16),

            // Virtual number info
            if (session != null && session.virtualNumber.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.phonelink_ring_rounded,
                            size: 14, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Virtual Number: ${session.virtualNumber}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Real phone numbers are hidden from both parties.',
                      style:
                          TextStyle(fontSize: 10, color: AppColors.textHint),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // Status stepper
            _CallStatusStepper(status: status),

            const SizedBox(height: 16),

            // Status text / error
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.red),
                textAlign: TextAlign.center,
              )
            else ...[
              if (_initiating || (!_isTerminal && status != 'connected'))
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary),
                ),
              if (status == 'connected')
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                      color: Colors.green, shape: BoxShape.circle),
                ),
              const SizedBox(height: 6),
              Text(
                _statusText,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _isTerminal
                      ? (status == 'ended' ? AppColors.textSecondary : Colors.red)
                      : (status == 'connected' ? Colors.green : AppColors.primary),
                ),
                textAlign: TextAlign.center,
              ),
              if (status == 'ringing')
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Exotel is calling your registered phone number.',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],

            const SizedBox(height: 24),

            // Close / dismiss button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _isTerminal || _error != null
                    ? () => Navigator.of(context).pop()
                    : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor:
                      _isTerminal ? AppColors.primary : AppColors.textSecondary,
                  side: BorderSide(
                    color: _isTerminal
                        ? AppColors.primary
                        : AppColors.textSecondary.withValues(alpha: 0.4),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(_isTerminal || _error != null ? 'Close' : 'In Progress…'),
              ),
            ),

            if (!_isTerminal && _error == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'End the call from your phone when finished.',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textHint),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Status stepper ─────────────────────────────────────────────────────────────

class _CallStatusStepper extends StatelessWidget {
  final String status;
  const _CallStatusStepper({required this.status});

  static const _steps = ['initiated', 'ringing', 'connected', 'ended'];

  int get _currentIndex {
    return switch (status) {
      'initiated' => 0,
      'ringing' => 1,
      'connected' => 2,
      'ended' => 3,
      _ => 0,
    };
  }

  bool _isError(int idx) =>
      (status == 'missed' || status == 'failed') && idx == _currentIndex;

  @override
  Widget build(BuildContext context) {
    final ci = _currentIndex;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (int i = 0; i < _steps.length; i++) ...[
            if (i > 0)
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 10, color: Colors.grey.shade400),
            _StepDot(
              label: _steps[i],
              active: i <= ci,
              isCurrent: i == ci,
              isError: _isError(i),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final String label;
  final bool active;
  final bool isCurrent;
  final bool isError;

  const _StepDot({
    required this.label,
    required this.active,
    required this.isCurrent,
    required this.isError,
  });

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? Colors.red
        : active
            ? Colors.green
            : Colors.grey.shade400;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: isCurrent
                ? [
                    BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 4,
                        spreadRadius: 2)
                  ]
                : [],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label[0].toUpperCase() + label.substring(1),
          style: TextStyle(
            fontSize: 9,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
            color: isCurrent ? color : Colors.grey.shade500,
          ),
        ),
      ],
    );
  }
}
