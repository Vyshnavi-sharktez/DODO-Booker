import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_modal_dialog.dart';
import '../providers/auth_provider.dart';
import '../../cart/providers/cart_provider.dart';

/// OTP verification modal. Takes the phone string returned by [OtpLoginModal].
/// Pops with `true` on successful verification, or null if dismissed.
class OtpVerificationModal extends ConsumerStatefulWidget {
  final String phone;

  const OtpVerificationModal({super.key, required this.phone});

  @override
  ConsumerState<OtpVerificationModal> createState() =>
      _OtpVerificationModalState();
}

class _OtpVerificationModalState extends ConsumerState<OtpVerificationModal> {
  final _ctrls = List.generate(6, (_) => TextEditingController());
  final _nodes = List.generate(6, (_) => FocusNode());
  Timer? _timer;
  int _secondsLeft = 30;
  bool _isLoading = false;
  String? _error;

  String get _otp => _ctrls.map((c) => c.text).join();
  bool get _otpComplete => _otp.length == 6;

  String get _maskedPhone {
    final digits = widget.phone.replaceAll(RegExp(r'^\+91'), '');
    if (digits.length >= 10) {
      return '+91 ·····${digits.substring(digits.length - 5)}';
    }
    return widget.phone;
  }

  @override
  void initState() {
    super.initState();
    _startTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _ctrls) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _timer?.cancel();
        return;
      }
      if (_secondsLeft == 0) {
        _timer?.cancel();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  void _onBoxChanged(int i, String val) {
    if (val.length == 1 && i < 5) {
      _nodes[i + 1].requestFocus();
    }
    setState(() => _error = null);
    if (_otpComplete) _verify();
  }

  Future<void> _verify() async {
    if (!_otpComplete || _isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).verifyOtp(widget.phone, _otp);
      if (!mounted) return;
      // Persist reactive auth state so subsequent Book Now skips the flow.
      ref.read(authNotifierProvider.notifier).setAuthenticated(true);
      // Merge Supabase cart with local cart (fire-and-forget).
      unawaited(ref.read(cartProvider.notifier).loadFromRemote());
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      for (final c in _ctrls) {
        c.clear();
      }
      _nodes[0].requestFocus();
      setState(() {
        _isLoading = false;
        _error = 'Invalid OTP. Please check and try again.';
      });
    }
  }

  Future<void> _resend() async {
    setState(() => _error = null);
    try {
      // Re-validates phone existence; OTP is pre-stored in dev_auth.
      await ref.read(authServiceProvider).checkPhone(widget.phone);
      _startTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not verify your number. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return AppModalDialog(
      title: 'Enter OTP',
      subtitle: Text('Sent to $_maskedPhone'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          _OtpBoxRow(
            ctrls: _ctrls,
            nodes: _nodes,
            onChanged: _onBoxChanged,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.error.withAlpha(18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _error!,
                style: const TextStyle(fontSize: 13, color: AppColors.error),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Didn't receive it? ",
                style: tt.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              if (_secondsLeft > 0)
                Text(
                  'Resend in ${_secondsLeft}s',
                  style: tt.bodySmall?.copyWith(color: AppColors.textHint),
                )
              else
                GestureDetector(
                  onTap: _resend,
                  child: Text(
                    'Resend OTP',
                    style: tt.bodySmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: (_otpComplete && !_isLoading) ? _verify : null,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: _isLoading
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Verify & Continue',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
          ),
        ],
      ),
    );
  }
}

class _OtpBoxRow extends StatelessWidget {
  final List<TextEditingController> ctrls;
  final List<FocusNode> nodes;
  final void Function(int index, String val) onChanged;

  const _OtpBoxRow({
    required this.ctrls,
    required this.nodes,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(6, (i) => _OtpBox(
        controller: ctrls[i],
        focusNode: nodes[i],
        prevNode: i > 0 ? nodes[i - 1] : null,
        prevCtrl: i > 0 ? ctrls[i - 1] : null,
        onChanged: (val) => onChanged(i, val),
      )),
    );
  }
}

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final FocusNode? prevNode;
  final TextEditingController? prevCtrl;
  final ValueChanged<String> onChanged;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.prevNode,
    required this.prevCtrl,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 52,
      child: Focus(
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace &&
              controller.text.isEmpty &&
              prevNode != null) {
            prevCtrl?.clear();
            prevNode!.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(1),
          ],
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            counterText: '',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
            filled: true,
            fillColor: AppColors.surfaceVariant,
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
