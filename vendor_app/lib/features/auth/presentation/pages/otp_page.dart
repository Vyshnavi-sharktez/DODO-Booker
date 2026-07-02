import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../shared/widgets/app_button.dart';
import '../providers/auth_controller.dart';
import '../providers/auth_state.dart';
import '../widgets/auth_loading_overlay.dart';
import '../widgets/otp_input_field.dart';

class OtpPage extends ConsumerStatefulWidget {
  const OtpPage({super.key});

  @override
  ConsumerState<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends ConsumerState<OtpPage> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();
  late final String _phone;
  int _resendSeconds = 30;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    final state = ref.read(authControllerProvider);
    _phone = state is AuthOtpSent ? state.phone : '';
    _startResendTimer();
  }

  void _startResendTimer() {
    _resendSeconds = 30;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_resendSeconds == 0) {
        t.cancel();
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void _handleVerify() {
    if (!_formKey.currentState!.validate()) return;
    ref.read(authControllerProvider.notifier).verifyOtp(
          phone: _phone,
          token: _otpController.text.trim(),
        );
  }

  void _handleResend() {
    _otpController.clear();
    ref.read(authControllerProvider.notifier).sendOtp(_phone);
    _startResendTimer();
  }

  String _maskPhone(String phone) {
    if (phone.length < 7) return phone;
    final prefix = phone.substring(0, 3);
    final suffix = phone.substring(phone.length - 4);
    return '$prefix xxxxxx$suffix';
  }

  @override
  Widget build(BuildContext context) {
    if (_phone.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.goNamed(RouteNames.login);
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next is AuthAuthenticated) {
        context.goNamed(RouteNames.dashboard);
      } else if (next is AuthUnauthenticated) {
        context.goNamed(RouteNames.login);
      } else if (next is AuthOtpSent && previous is AuthLoading) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('OTP resent successfully'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    });

    final authState = ref.watch(authControllerProvider);
    final isLoading = authState is AuthLoading;
    final errorMessage = authState is AuthError ? authState.message : null;
    final canResend = _resendSeconds == 0 && !isLoading;

    return AuthLoadingOverlay(
      isLoading: isLoading,
      child: Scaffold(
        backgroundColor: const Color(0xFF111111),
        body: SafeArea(
          child: Column(
            children: [
              // ── Back button ────────────────────────────────────────────────
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    tooltip: 'Back to login',
                    onPressed: () => context.goNamed(RouteNames.login),
                  ),
                ),
              ),

              // ── Centered OTP card ──────────────────────────────────────────
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Form(
                        key: _formKey,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 40,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // ── OTP icon ───────────────────────────────────
                              Container(
                                width: 72,
                                height: 72,
                                decoration: const BoxDecoration(
                                  color: AppColors.primaryLight,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.sms_rounded,
                                  size: 34,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 20),

                              // ── Heading ────────────────────────────────────
                              const Text(
                                'Enter OTP',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),

                              // ── Subtitle ───────────────────────────────────
                              const Text(
                                'We sent a 6-digit code to',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _maskPhone(_phone),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 32),

                              // ── OTP input ──────────────────────────────────
                              OtpInputField(
                                controller: _otpController,
                                onCompleted: _handleVerify,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Enter the 6-digit OTP';
                                  }
                                  if (value.trim().length != 6) {
                                    return 'OTP must be exactly 6 digits';
                                  }
                                  return null;
                                },
                              ),

                              // ── Error banner ───────────────────────────────
                              if (errorMessage != null) ...[
                                const SizedBox(height: 14),
                                _AuthErrorBanner(message: errorMessage),
                              ],

                              const SizedBox(height: 28),

                              // ── Verify button ──────────────────────────────
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: AppButton(
                                  label: 'Verify OTP',
                                  isLoading: isLoading,
                                  onPressed: isLoading ? null : _handleVerify,
                                ),
                              ),

                              const SizedBox(height: 20),

                              // ── Resend row ─────────────────────────────────
                              _resendSeconds > 0
                                  ? RichText(
                                      text: TextSpan(
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: AppColors.textSecondary,
                                        ),
                                        children: [
                                          const TextSpan(
                                              text: 'Resend OTP in '),
                                          TextSpan(
                                            text: '${_resendSeconds}s',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Text(
                                          "Didn't receive the code?",
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: canResend
                                              ? _handleResend
                                              : null,
                                          style: TextButton.styleFrom(
                                            foregroundColor: AppColors.primary,
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 6),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                          ),
                                          child: const Text(
                                            'Resend OTP',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ],
                                    ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Error banner ──────────────────────────────────────────────────────────────

class _AuthErrorBanner extends StatelessWidget {
  const _AuthErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
