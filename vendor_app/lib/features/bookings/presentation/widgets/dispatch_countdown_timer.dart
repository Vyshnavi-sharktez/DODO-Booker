import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class DispatchCountdownTimer extends StatefulWidget {
  final DateTime? startTime;
  final int timeoutSeconds;
  final VoidCallback? onExpired;

  const DispatchCountdownTimer({
    super.key,
    required this.startTime,
    this.timeoutSeconds = 60,
    this.onExpired,
  });

  @override
  State<DispatchCountdownTimer> createState() => _DispatchCountdownTimerState();
}

class _DispatchCountdownTimerState extends State<DispatchCountdownTimer> {
  Timer? _timer;
  late int _remainingSeconds;

  @override
  void initState() {
    super.initState();
    _calculateRemaining();
    _startTimer();
  }

  @override
  void didUpdateWidget(DispatchCountdownTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startTime != widget.startTime ||
        oldWidget.timeoutSeconds != widget.timeoutSeconds) {
      _calculateRemaining();
    }
  }

  void _calculateRemaining() {
    if (widget.startTime == null) {
      _remainingSeconds = widget.timeoutSeconds;
      return;
    }

    final startUtc = widget.startTime!.toUtc();
    final deadlineUtc =
        startUtc.add(Duration(seconds: widget.timeoutSeconds));
    final diff = deadlineUtc.difference(DateTime.now().toUtc()).inSeconds;
    _remainingSeconds = diff > 0 ? diff : 0;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          _timer?.cancel();
          widget.onExpired?.call();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isUrgent = _remainingSeconds <= 15;
    final progress = widget.timeoutSeconds > 0
        ? (_remainingSeconds / widget.timeoutSeconds).clamp(0.0, 1.0)
        : 0.0;

    final color = _remainingSeconds == 0
        ? AppColors.textSecondary
        : (isUrgent ? AppColors.error : AppColors.primary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 2.5,
              color: color,
              backgroundColor: color.withValues(alpha: 0.2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _remainingSeconds == 0
                ? 'TIMED OUT'
                : 'OFFER EXPIRES IN ${_formatTime(_remainingSeconds)}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
