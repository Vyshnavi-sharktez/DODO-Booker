import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/auth_provider.dart';

// ── Page states ───────────────────────────────────────────────────────────────

enum _PageState { waiting, form, invalidLink, success }

// ── Password strength ─────────────────────────────────────────────────────────

enum _PasswordStrength { weak, fair, strong }

_PasswordStrength _measureStrength(String p) {
  if (p.length < 8) return _PasswordStrength.weak;
  int score = 0;
  if (RegExp(r'[A-Z]').hasMatch(p)) score++;
  if (RegExp(r'[0-9]').hasMatch(p)) score++;
  if (RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(p)) score++;
  if (p.length >= 12) score++;
  if (score >= 3) return _PasswordStrength.strong;
  if (score >= 1) return _PasswordStrength.fair;
  return _PasswordStrength.fair; // >= 8 chars but no extras → fair
}

// ── Page ─────────────────────────────────────────────────────────────────────

class ResetPasswordPage extends ConsumerStatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  ConsumerState<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends ConsumerState<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  _PageState _pageState = _PageState.waiting;
  StreamSubscription<AuthState>? _authSub;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();

    // Subscribe to auth events before checking current state, so we don't
    // miss a passwordRecovery event that fires during async code exchange.
    _authSub =
        Supabase.instance.client.auth.onAuthStateChange.listen(_onAuthEvent);

    // Supabase.initialize() processes the recovery URL synchronously on web,
    // so by the first frame the session is usually already established.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pageState != _PageState.waiting) return;
      if (Supabase.instance.client.auth.currentSession != null) {
        setState(() => _pageState = _PageState.form);
        return;
      }
      // Give a brief window for async PKCE code exchange to complete.
      _timeoutTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted || _pageState != _PageState.waiting) return;
        if (Supabase.instance.client.auth.currentSession != null) {
          setState(() => _pageState = _PageState.form);
        } else {
          setState(() => _pageState = _PageState.invalidLink);
        }
      });
    });
  }

  void _onAuthEvent(AuthState data) {
    if (!mounted) return;
    if (data.event == AuthChangeEvent.passwordRecovery) {
      _timeoutTimer?.cancel();
      setState(() => _pageState = _PageState.form);
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _timeoutTimer?.cancel();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    ref.read(updatePasswordProvider.notifier).clearError();

    await ref
        .read(updatePasswordProvider.notifier)
        .update(_passwordController.text);

    if (!mounted) return;
    final updateState = ref.read(updatePasswordProvider);
    if (updateState is AsyncData) {
      setState(() => _pageState = _PageState.success);
      // Show success message on login page after sign-out triggers redirect.
      ref.read(loginSuccessMessageProvider.notifier).state =
          'Password updated successfully. Please sign in with your new password.';
      // Brief delay so the success state renders, then sign out.
      // The auth state change will trigger the router redirect to /login.
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        await Supabase.instance.client.auth.signOut();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _BrandHeader(),
                const SizedBox(height: 40),
                _buildCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(32),
      child: switch (_pageState) {
        _PageState.waiting => const _WaitingView(),
        _PageState.invalidLink => _InvalidLinkView(
            onBackToLogin: () => context.go('/login'),
          ),
        _PageState.success => const _SuccessView(),
        _PageState.form => _FormView(
            formKey: _formKey,
            passwordController: _passwordController,
            confirmController: _confirmController,
            obscurePassword: _obscurePassword,
            obscureConfirm: _obscureConfirm,
            onTogglePassword: () =>
                setState(() => _obscurePassword = !_obscurePassword),
            onToggleConfirm: () =>
                setState(() => _obscureConfirm = !_obscureConfirm),
            onSubmit: _submit,
            onBackToLogin: () => context.go('/login'),
          ),
      },
    );
  }
}

// ── Brand header (mirrors login page) ────────────────────────────────────────

class _BrandHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(
            Icons.admin_panel_settings_rounded,
            color: Colors.white,
            size: 38,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'DODO BOOKER',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Admin Panel',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 15,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

// ── Waiting view (processing recovery session) ────────────────────────────────

class _WaitingView extends StatelessWidget {
  const _WaitingView();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 16),
        CircularProgressIndicator(color: AppColors.accent),
        SizedBox(height: 24),
        Text(
          'Verifying reset link…',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Please wait while we validate your reset link.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        SizedBox(height: 16),
      ],
    );
  }
}

// ── Invalid / expired link view ───────────────────────────────────────────────

class _InvalidLinkView extends StatelessWidget {
  const _InvalidLinkView({required this.onBackToLogin});
  final VoidCallback onBackToLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.link_off_rounded,
              color: AppColors.error, size: 32),
        ),
        const SizedBox(height: 20),
        const Text(
          'Invalid or Expired Link',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'This password reset link is invalid or has expired.\nReset links are valid for 1 hour.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onBackToLogin,
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            child: const Text('Back to Sign In'),
          ),
        ),
      ],
    );
  }
}

// ── Success view ──────────────────────────────────────────────────────────────

class _SuccessView extends StatelessWidget {
  const _SuccessView();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_outline_rounded,
              color: AppColors.success, size: 32),
        ),
        const SizedBox(height: 20),
        const Text(
          'Password Updated!',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Your password has been updated successfully.\nRedirecting you to Sign In…',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: AppColors.accent,
          ),
        ),
      ],
    );
  }
}

// ── Form view ─────────────────────────────────────────────────────────────────

class _FormView extends ConsumerStatefulWidget {
  const _FormView({
    required this.formKey,
    required this.passwordController,
    required this.confirmController,
    required this.obscurePassword,
    required this.obscureConfirm,
    required this.onTogglePassword,
    required this.onToggleConfirm,
    required this.onSubmit,
    required this.onBackToLogin,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController passwordController;
  final TextEditingController confirmController;
  final bool obscurePassword;
  final bool obscureConfirm;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirm;
  final VoidCallback onSubmit;
  final VoidCallback onBackToLogin;

  @override
  ConsumerState<_FormView> createState() => _FormViewState();
}

class _FormViewState extends ConsumerState<_FormView> {
  _PasswordStrength? _strength;

  void _onPasswordChanged(String value) {
    setState(
      () => _strength = value.isEmpty ? null : _measureStrength(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final updateState = ref.watch(updatePasswordProvider);
    final isLoading = updateState is AsyncLoading;
    final error = updateState.hasError ? updateState.error.toString() : null;

    return Form(
      key: widget.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Set New Password',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Choose a strong password for your account.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 28),

          // Error banner
          if (error != null) ...[
            _ErrorBanner(message: error),
            const SizedBox(height: 20),
          ],

          // New password field
          const Text(
            'New Password',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: widget.passwordController,
            obscureText: widget.obscurePassword,
            textInputAction: TextInputAction.next,
            enabled: !isLoading,
            onChanged: _onPasswordChanged,
            decoration: InputDecoration(
              hintText: '••••••••',
              prefixIcon:
                  const Icon(Icons.lock_outline_rounded, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  widget.obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                ),
                onPressed: widget.onTogglePassword,
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Password is required';
              if (v.length < 8) {
                return 'Password must be at least 8 characters';
              }
              return null;
            },
          ),

          // Password strength indicator
          if (_strength != null) ...[
            const SizedBox(height: 10),
            _PasswordStrengthBar(strength: _strength!),
          ],
          const SizedBox(height: 20),

          // Confirm password field
          const Text(
            'Confirm Password',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: widget.confirmController,
            obscureText: widget.obscureConfirm,
            textInputAction: TextInputAction.done,
            enabled: !isLoading,
            onFieldSubmitted: (_) => widget.onSubmit(),
            decoration: InputDecoration(
              hintText: '••••••••',
              prefixIcon:
                  const Icon(Icons.lock_outline_rounded, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  widget.obscureConfirm
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                ),
                onPressed: widget.onToggleConfirm,
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) {
                return 'Please confirm your password';
              }
              if (v != widget.passwordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
          const SizedBox(height: 28),

          // Submit button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: isLoading ? null : widget.onSubmit,
              child: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Update Password'),
            ),
          ),
          const SizedBox(height: 16),

          // Back to login
          Center(
            child: TextButton.icon(
              onPressed: isLoading ? null : widget.onBackToLogin,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back to Sign In'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Password strength bar ─────────────────────────────────────────────────────

class _PasswordStrengthBar extends StatelessWidget {
  const _PasswordStrengthBar({required this.strength});
  final _PasswordStrength strength;

  @override
  Widget build(BuildContext context) {
    final (label, color, filledSegments) = switch (strength) {
      _PasswordStrength.weak => ('Weak', AppColors.error, 1),
      _PasswordStrength.fair => ('Fair', AppColors.warning, 2),
      _PasswordStrength.strong => ('Strong', AppColors.success, 3),
    };

    return Row(
      children: [
        for (int i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 4,
              decoration: BoxDecoration(
                color: i < filledSegments
                    ? color
                    : AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ── Error banner ──────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
