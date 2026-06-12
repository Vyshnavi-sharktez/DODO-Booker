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

  @override
  void initState() {
    super.initState();
    final state = ref.read(authControllerProvider);
    _phone = state is AuthOtpSent ? state.phone : '';
  }

  @override
  void dispose() {
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

    return AuthLoadingOverlay(
      isLoading: isLoading,
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(
            onPressed: () => context.goNamed(RouteNames.login),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),
                  const Icon(
                    Icons.sms_rounded,
                    size: 56,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Enter OTP',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We sent a 6-digit code to',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _phone,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 36),
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
                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),
                    _AuthErrorBanner(message: errorMessage),
                  ],
                  const SizedBox(height: 28),
                  AppButton(
                    label: 'Verify OTP',
                    isLoading: isLoading,
                    onPressed: isLoading ? null : _handleVerify,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Didn't receive the code?",
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                      TextButton(
                        onPressed: isLoading ? null : _handleResend,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Resend',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
