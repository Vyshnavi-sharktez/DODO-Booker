import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';

import '../domain/models/call_session.dart';
import '../services/call_bridge_service.dart';

class CallBridgeDialog extends ConsumerStatefulWidget {
  final String bookingId;
  final String bookingNumber;
  final String callerId;
  final String calleeId;
  final String callerRole; // 'customer' or 'vendor'
  final String recipientName;
  final String bookingStatus;

  const CallBridgeDialog({
    super.key,
    required this.bookingId,
    required this.bookingNumber,
    required this.callerId,
    required this.calleeId,
    required this.callerRole,
    required this.recipientName,
    required this.bookingStatus,
  });

  static Future<void> show(
    BuildContext context, {
    required String bookingId,
    required String bookingNumber,
    required String callerId,
    required String calleeId,
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
        callerId: callerId,
        calleeId: calleeId,
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
  String _currentLifecycleState = 'initiated'; // initiated -> ringing -> connected -> ended / missed
  String _statusText = 'Initiating DODO Call Bridge...';
  bool _isConnected = false;
  bool _isEnded = false;
  bool _isMuted = false;
  bool _isSpeaker = false;
  int _secondsElapsed = 0;

  Timer? _callTimer;
  Timer? _connectTimer;
  Timer? _ringingTimer;

  @override
  void initState() {
    super.initState();
    _startCallSession();
  }

  Future<void> _startCallSession() async {
    try {
      final service = ref.read(callBridgeServiceProvider);
      final session = await service.initiateCallSession(
        bookingId: widget.bookingId,
        callerId: widget.callerId,
        calleeId: widget.calleeId,
        callerRole: widget.callerRole,
        bookingStatus: widget.bookingStatus,
      );

      if (!mounted) return;
      setState(() {
        _session = session;
        _currentLifecycleState = 'initiated';
        _statusText = 'Initiating DODO Call Bridge...';
      });

      // 1. Transition to Ringing after 1s
      _ringingTimer = Timer(const Duration(seconds: 1), () async {
        if (!mounted || _isEnded) return;
        try {
          await service.updateCallStatus(session.id, 'ringing');
          if (mounted && !_isEnded) {
            setState(() {
              _currentLifecycleState = 'ringing';
              _statusText = 'Ringing ${widget.recipientName}...';
            });
          }
        } catch (_) {}
      });

      // 2. Transition to Connected after 2.5s
      _connectTimer = Timer(const Duration(milliseconds: 2500), () async {
        if (!mounted || _isEnded) return;
        try {
          await service.updateCallStatus(session.id, 'connected');
          if (mounted && !_isEnded) {
            setState(() {
              _currentLifecycleState = 'connected';
              _isConnected = true;
              _statusText = 'Call Connected';
            });
            _startTimer();
          }
        } catch (_) {}
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _currentLifecycleState = 'failed';
        _statusText = 'Call Failed: ${e.toString().replaceAll('StateError: ', '')}';
        _isEnded = true;
      });
    }
  }

  void _startTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _secondsElapsed++);
    });
  }

  Future<void> _endCall() async {
    _ringingTimer?.cancel();
    _connectTimer?.cancel();
    _callTimer?.cancel();

    if (_session != null) {
      try {
        final service = ref.read(callBridgeServiceProvider);
        final now = DateTime.now();
        final calculatedSecs = _secondsElapsed > 0
            ? _secondsElapsed
            : now.difference(_session!.initiatedAt).inSeconds;
        final finalSecs = calculatedSecs > 0 ? calculatedSecs : 0;

        if (_isConnected) {
          await service.terminateCallSession(_session!.id, durationSeconds: finalSecs);
        } else {
          await service.updateCallStatus(_session!.id, 'missed', durationSeconds: finalSecs);
        }
      } catch (_) {}
    }

    if (!mounted) return;
    final finalState = _isConnected ? 'ended' : 'missed';
    final finalStatus = _isConnected ? 'Call Ended' : 'Call Cancelled';
    setState(() {
      _currentLifecycleState = finalState;
      _isConnected = false;
      _isEnded = true;
      _statusText = finalStatus;
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _ringingTimer?.cancel();
    _connectTimer?.cancel();
    _callTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final virtualNum = _session?.maskedVirtualNumber ?? '+91 80000-DODO1';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Shield Security Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_rounded, size: 14, color: AppColors.primary),
                  SizedBox(width: 6),
                  Text(
                    'DODO SECURE CALL BRIDGE',
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

            // Recipient Avatar & Name
            CircleAvatar(
              radius: 36,
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              child: Text(
                widget.recipientName.isNotEmpty
                    ? widget.recipientName.substring(0, 1).toUpperCase()
                    : 'D',
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
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),

            const SizedBox(height: 16),

            // Virtual Phone Info Container
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
                      const Icon(Icons.phonelink_ring_rounded, size: 14, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Virtual Number: $virtualNum',
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
                    'Your real personal phone number is 100% hidden & protected.',
                    style: TextStyle(fontSize: 10, color: AppColors.textHint),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Live Lifecycle Stepper & Status Badge ─────────────────────
            _CallLifecycleStepper(currentState: _currentLifecycleState),

            const SizedBox(height: 16),

            // Status Indicator & Timer
            if (_isConnected)
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDuration(_secondsElapsed),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Encrypted Voice Session Active',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              )
            else
              Column(
                children: [
                  if (!_isEnded)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    _statusText,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _isEnded ? Colors.red : AppColors.primary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),

            const SizedBox(height: 24),

            // Call Action Buttons (Mute, Speaker, End Call)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: _isConnected
                      ? () => setState(() => _isMuted = !_isMuted)
                      : null,
                  icon: Icon(
                    _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    color: _isMuted ? Colors.red : AppColors.textSecondary,
                  ),
                  tooltip: _isMuted ? 'Unmute' : 'Mute',
                ),
                // End Call Red Floating Button
                GestureDetector(
                  onTap: _endCall,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.call_end_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _isConnected
                      ? () => setState(() => _isSpeaker = !_isSpeaker)
                      : null,
                  icon: Icon(
                    _isSpeaker
                        ? Icons.volume_up_rounded
                        : Icons.volume_down_rounded,
                    color: _isSpeaker ? AppColors.primary : AppColors.textSecondary,
                  ),
                  tooltip: _isSpeaker ? 'Speaker Off' : 'Speaker On',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CallLifecycleStepper extends StatelessWidget {
  final String currentState;

  const _CallLifecycleStepper({required this.currentState});

  @override
  Widget build(BuildContext context) {
    final isInitiated = true; // Always achieved first
    final isRinging = currentState == 'ringing' || currentState == 'connected' || currentState == 'ended';
    final isConnected = currentState == 'connected' || currentState == 'ended';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StepItem(label: 'Initiated', active: isInitiated, isCurrent: currentState == 'initiated', color: Colors.orange),
          const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: Colors.grey),
          _StepItem(label: 'Ringing', active: isRinging, isCurrent: currentState == 'ringing', color: Colors.blue),
          const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: Colors.grey),
          _StepItem(label: 'Connected', active: isConnected, isCurrent: currentState == 'connected', color: Colors.green),
        ],
      ),
    );
  }
}

class _StepItem extends StatelessWidget {
  final String label;
  final bool active;
  final bool isCurrent;
  final Color color;

  const _StepItem({
    required this.label,
    required this.active,
    required this.isCurrent,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = active ? color : Colors.grey.shade400;

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: activeColor,
            shape: BoxShape.circle,
            boxShadow: isCurrent
                ? [BoxShadow(color: activeColor.withValues(alpha: 0.5), blurRadius: 4, spreadRadius: 2)]
                : [],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
            color: isCurrent ? activeColor : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}
