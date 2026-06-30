import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_modal_dialog.dart';
import '../providers/auth_provider.dart';

/// Profile completion modal shown after first OTP login.
/// Pops with `true` when profile is saved successfully.
class ProfileCompletionModal extends ConsumerStatefulWidget {
  const ProfileCompletionModal({super.key});

  @override
  ConsumerState<ProfileCompletionModal> createState() =>
      _ProfileCompletionModalState();
}

class _ProfileCompletionModalState extends ConsumerState<ProfileCompletionModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrll = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrll.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    debugPrint('[DODO][Profile] Save button pressed');
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).updateProfile(
            fullName: _nameCtrll.text.trim(),
            email: _emailCtrl.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('[DODO][Profile] Save failed in modal: $e');
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _isLoading = false;
        _error = message;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return AppModalDialog(
      title: 'Complete Your Profile',
      subtitle: const Text('Just a few details to get started'),
      barrierDismissible: false,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),

            // Full name
            Text(
              'Full Name',
              style: tt.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _nameCtrll,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: _inputDecoration('e.g. Riya Sharma', cs),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Full name is required';
                }
                if (v.trim().length < 2) return 'Name is too short';
                return null;
              },
            ),

            const SizedBox(height: 16),

            // Email
            Text(
              'Email Address',
              style: tt.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: _inputDecoration('e.g. riya@email.com', cs),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Email is required';
                }
                final emailRe = RegExp(
                  r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
                );
                if (!emailRe.hasMatch(v.trim())) {
                  return 'Enter a valid email address';
                }
                return null;
              },
            ),

            if (_error != null) ...[
              const SizedBox(height: 14),
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

            const SizedBox(height: 24),

            FilledButton(
              onPressed: _isLoading ? null : _save,
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
                      'Save & Continue',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, ColorScheme cs) => InputDecoration(
        hintText: hint,
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
      );
}
