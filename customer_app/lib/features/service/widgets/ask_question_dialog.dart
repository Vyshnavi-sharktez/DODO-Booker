import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../notifications/services/notification_providers.dart';
import '../../profile/services/profile_providers.dart';
import '../services/customer_question_providers.dart';

class AskQuestionDialog extends ConsumerStatefulWidget {
  const AskQuestionDialog({
    super.key,
    required this.serviceId,
    required this.serviceName,
  });

  final String serviceId;
  final String serviceName;

  static Future<void> show(
    BuildContext context, {
    required String serviceId,
    required String serviceName,
  }) {
    return showDialog(
      context: context,
      builder: (_) => AskQuestionDialog(
        serviceId: serviceId,
        serviceName: serviceName,
      ),
    );
  }

  @override
  ConsumerState<AskQuestionDialog> createState() => _AskQuestionDialogState();
}

class _AskQuestionDialogState extends ConsumerState<AskQuestionDialog> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final customerId =
          await ref.read(notificationServiceProvider).getCustomerId();
      final profile = ref.read(profileProvider).valueOrNull;
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('dodo_auth_phone');
      final name =
          (profile?.fullName.isNotEmpty == true) ? profile!.fullName : null;

      await ref.read(customerQuestionServiceProvider).submitQuestion(
            serviceId: widget.serviceId,
            serviceName: widget.serviceName,
            customerId: customerId,
            customerName: name,
            customerPhone: phone,
            question: q,
          );

      if (mounted) {
        setState(() {
          _submitted = true;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Failed to submit. Please try again.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _submitted
              ? _SuccessBody(onClose: () => Navigator.of(context).pop())
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  // stretch gives the Column a tight bounded width so the
                  // action Row's maxMainSize is finite (not double.infinity).
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Ask a Question',
                      style:
                          tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.serviceName,
                      style: tt.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _ctrl,
                      maxLines: 4,
                      maxLength: 500,
                      decoration: InputDecoration(
                        hintText: 'Type your question here...',
                        hintStyle:
                            const TextStyle(color: AppColors.textHint),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.all(14),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _error!,
                        style: const TextStyle(
                            color: AppColors.error, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 16),
                    // Row receives tight bounded width from the stretch Column.
                    // FilledButton is wrapped in Flexible(loose) so Flutter's
                    // flex second-pass gives it finite remaining-space instead
                    // of the infinite maxWidth non-flexible children always get.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          fit: FlexFit.loose,
                          child: FilledButton(
                            onPressed: _loading ? null : _submit,
                            child: _loading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Submit'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _SuccessBody extends StatelessWidget {
  final VoidCallback onClose;
  const _SuccessBody({required this.onClose});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle_rounded,
            size: 52, color: AppColors.success),
        const SizedBox(height: 16),
        Text(
          'Question Submitted!',
          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          "We'll review your question and get back to you soon.",
          style: tt.bodySmall?.copyWith(
            color: AppColors.textSecondary,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: onClose,
          child: const Text('Done'),
        ),
      ],
    );
  }
}
