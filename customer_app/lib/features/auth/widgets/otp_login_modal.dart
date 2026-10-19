import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_modal_dialog.dart';
import '../../../core/widgets/phone_input_field.dart';
import '../providers/auth_provider.dart';

/// Phone number entry modal. Pops with the full phone string (e.g. "+919876543210")
/// on successful OTP dispatch, or null if dismissed.
class OtpLoginModal extends ConsumerStatefulWidget {
  const OtpLoginModal({super.key});

  @override
  ConsumerState<OtpLoginModal> createState() => _OtpLoginModalState();
}

class _OtpLoginModalState extends ConsumerState<OtpLoginModal> {
  final _ctrl = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _isValid => _ctrl.text.trim().length == 10;

  Future<void> _sendOtp() async {
    if (!_isValid) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final fullPhone = '${PhoneInputField.dialCode}${_ctrl.text.trim()}';
      await ref.read(authServiceProvider).sendOtp(fullPhone);
      if (!mounted) return;
      Navigator.of(context).pop(fullPhone);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return AppModalDialog(
      title: 'Login / Sign Up',
      subtitle: const Text('Enter your mobile number to continue'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          PhoneInputField(
            controller: _ctrl,
            autofocus: true,
            onSubmitted: _sendOtp,
            decoration: InputDecoration(
              counterText: '',
              hintText: '9876543210',
              errorText: _error,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.outline.withAlpha(80)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.primary, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.error),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.error, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: (_isValid && !_isLoading) ? _sendOtp : null,
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
                    'Send OTP',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
          ),
          const SizedBox(height: 16),
          Text(
            'By continuing, you agree to our Terms & Privacy Policy.',
            style: tt.labelSmall?.copyWith(color: cs.onSurface.withAlpha(120)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

