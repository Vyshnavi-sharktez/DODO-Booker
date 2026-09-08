import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/service_faqs_providers.dart';
import '../../domain/models/service_faq.dart';
import 'faq_form_dialog.dart';

/// FAQs management dialog for vendor custom services.
///
/// Mirrors [NodeFaqsDialog] but operates on `custom_service_id` rows in
/// `service_faqs` instead of `service_id` rows. Only shows the Admin FAQs
/// tab — Customer Q&A for custom services is not yet supported.
class CustomServiceFaqsDialog extends ConsumerStatefulWidget {
  const CustomServiceFaqsDialog({
    super.key,
    required this.customServiceId,
    required this.serviceName,
  });

  final String customServiceId;
  final String serviceName;

  static Future<void> show(
    BuildContext context, {
    required String customServiceId,
    required String serviceName,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => CustomServiceFaqsDialog(
        customServiceId: customServiceId,
        serviceName: serviceName,
      ),
    );
  }

  @override
  ConsumerState<CustomServiceFaqsDialog> createState() =>
      _CustomServiceFaqsDialogState();
}

class _CustomServiceFaqsDialogState
    extends ConsumerState<CustomServiceFaqsDialog> {
  @override
  Widget build(BuildContext context) {
    final faqsAsync =
        ref.watch(customServiceFaqsNotifierProvider(widget.customServiceId));
    final notifier = ref
        .read(customServiceFaqsNotifierProvider(widget.customServiceId).notifier);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 18, 16, 18),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.quiz_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'FAQs',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          widget.serviceName,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _openCreate(context, notifier),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Add FAQ'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.18),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // ── Body ──────────────────────────────────────────────────────
            Expanded(
              child: faqsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text('Error loading FAQs: $e')),
                data: (faqs) {
                  if (faqs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.quiz_outlined,
                              size: 52, color: AppColors.textSecondary),
                          const SizedBox(height: 12),
                          Text('No FAQs yet',
                              style:
                                  Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 6),
                          const Text(
                            'Click "Add FAQ" to create the first one.',
                            style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: faqs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) => _FaqTile(
                      faq: faqs[i],
                      onEdit: () => _openEdit(context, notifier, faqs[i]),
                      onDelete: () =>
                          _confirmDelete(context, notifier, faqs[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCreate(
      BuildContext context, CustomServiceFaqsNotifier notifier) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => FaqFormDialog(
        onSave: ({required question, required answer}) =>
            notifier.create(question: question, answer: answer),
      ),
    );
  }

  void _openEdit(BuildContext context, CustomServiceFaqsNotifier notifier,
      ServiceFaq faq) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => FaqFormDialog(
        existing: faq,
        onSave: ({required question, required answer}) => notifier.update(
            faq.id,
            question: question,
            answer: answer,
            sortOrder: faq.sortOrder),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context,
      CustomServiceFaqsNotifier notifier, ServiceFaq faq) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete FAQ?'),
        content: Text(
            'Delete the FAQ "${faq.question.length > 60 ? '${faq.question.substring(0, 60)}…' : faq.question}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await notifier.delete(faq.id);
  }
}

// ── FAQ tile ──────────────────────────────────────────────────────────────────

class _FaqTile extends StatelessWidget {
  const _FaqTile({
    required this.faq,
    required this.onEdit,
    required this.onDelete,
  });

  final ServiceFaq faq;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.help_outline_rounded,
                  size: 16, color: AppColors.textSecondary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    faq.question,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    faq.answer,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  tooltip: 'Edit',
                  color: AppColors.textSecondary,
                  visualDensity: VisualDensity.compact,
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  tooltip: 'Delete',
                  color: AppColors.error,
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
