import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_modal_dialog.dart';
import '../providers/auth_provider.dart';
import '../widgets/otp_login_modal.dart';
import '../widgets/otp_verification_modal.dart';
import '../widgets/profile_completion_modal.dart';

/// Shows the OTP login + profile-completion modal chain when the user is not
/// authenticated. Returns [true] if the user is authenticated (and has a
/// complete profile) when this returns; [false] if they dismissed any step.
///
/// Safe to call when already authenticated — returns [true] immediately (or
/// after a profile-completion prompt if the profile is still incomplete).
Future<bool> requireAuth(BuildContext context, WidgetRef ref) async {
  if (!ref.read(isAuthenticatedProvider)) {
    // ── Step 1: Phone entry ─────────────────────────────────────────────────
    final phone = await AppModalDialog.show<String>(
      context: context,
      child: const OtpLoginModal(),
    );
    if (!context.mounted || phone == null) return false;

    // ── Step 2: OTP verification ────────────────────────────────────────────
    // OtpVerificationModal internally calls authNotifierProvider.setAuthenticated(true)
    // on success, so auth state is updated before we continue.
    final verified = await AppModalDialog.show<bool>(
      context: context,
      child: OtpVerificationModal(phone: phone),
    );
    if (!context.mounted || verified != true) return false;
  }

  // ── Step 3: Profile completion (if needed) ──────────────────────────────
  final profileComplete = await ref.read(authServiceProvider).isProfileComplete();
  if (!context.mounted) return false;
  if (!profileComplete) {
    final saved = await AppModalDialog.show<bool>(
      context: context,
      child: const ProfileCompletionModal(),
      barrierDismissible: false,
    );
    if (!context.mounted || saved != true) return false;
  }

  return true;
}
