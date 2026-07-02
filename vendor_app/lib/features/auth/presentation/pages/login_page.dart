import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../shared/widgets/app_button.dart';
import '../providers/auth_controller.dart';
import '../providers/auth_state.dart';
import '../widgets/auth_loading_overlay.dart';
import '../widgets/phone_number_field.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  static const _countryCode = '+91';

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String get _fullPhone => '$_countryCode${_phoneController.text.trim()}';

  void _handleSendOtp() {
    if (!_formKey.currentState!.validate()) return;
    debugPrint('[DODO][LoginPage] raw input   : "${_phoneController.text}"');
    debugPrint('[DODO][LoginPage] countryCode : "$_countryCode"');
    debugPrint('[DODO][LoginPage] fullPhone   : "$_fullPhone"');
    debugPrint('[DODO][LoginPage] length      : ${_fullPhone.length}');
    debugPrint('[DODO][LoginPage] codeUnits   : ${_fullPhone.codeUnits}');
    ref.read(authControllerProvider.notifier).sendOtp(_fullPhone);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authControllerProvider, (_, next) {
      if (next is AuthOtpSent) {
        context.goNamed(RouteNames.otp);
      }
    });

    final authState = ref.watch(authControllerProvider);
    final isLoading = authState is AuthLoading;
    final errorMessage = authState is AuthError ? authState.message : null;

    return AuthLoadingOverlay(
      isLoading: isLoading,
      child: Scaffold(
        backgroundColor: const Color(0xFF111111),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Brand header ──────────────────────────────────────────
                    const _BrandHeader(),
                    const SizedBox(height: 36),

                    // ── Login card ────────────────────────────────────────────
                    Form(
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Sign in to continue',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Enter your registered mobile number to receive a one-time password.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 28),
                            const Text(
                              'Mobile Number',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            PhoneNumberField(
                              controller: _phoneController,
                              countryCode: _countryCode,
                              onSubmitted: _handleSendOtp,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Enter your mobile number';
                                }
                                if (value.trim().length < 10) {
                                  return 'Enter a valid 10-digit number';
                                }
                                return null;
                              },
                            ),
                            if (errorMessage != null) ...[
                              const SizedBox(height: 14),
                              _AuthErrorBanner(message: errorMessage),
                            ],
                            const SizedBox(height: 28),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: AppButton(
                                label: 'Send OTP',
                                isLoading: isLoading,
                                onPressed: isLoading ? null : _handleSendOtp,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),
                    Text(
                      '© ${DateTime.now().year} DODO Booker. All rights reserved.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Brand header ──────────────────────────────────────────────────────────────

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.asset(
          'assets/images/logo.png',
          height: 88,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stack) => Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.store_rounded,
              size: 40,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'DODO BOOKER',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Vendor Portal',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 15,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.4,
          ),
        ),
      ],
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
