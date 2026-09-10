import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../customer_questions/application/providers/customer_questions_providers.dart';
import '../../../customer_questions/domain/models/customer_question.dart';
import '../../application/providers/service_faqs_providers.dart';
import '../../domain/models/service_faq.dart';
import 'faq_form_dialog.dart';

/// FAQs management dialog for vendor custom services.
///
/// Has two tabs: "Admin FAQs" (admin-curated Q&A) and "Customer Questions"
/// (questions submitted by customers, answered here or by the vendor).
class CustomServiceFaqsDialog extends ConsumerStatefulWidget {
  const CustomServiceFaqsDialog({
    super.key,
    required this.customServiceId,
    required this.serviceName,
    this.showQuestions = false,
  });

  final String customServiceId;
  final String serviceName;

  /// When true, opens directly on the Customer Questions tab.
  final bool showQuestions;

  static Future<void> show(
    BuildContext context, {
    required String customServiceId,
    required String serviceName,
    bool showQuestions = false,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => CustomServiceFaqsDialog(
        customServiceId: customServiceId,
        serviceName: serviceName,
        showQuestions: showQuestions,
      ),
    );
  }

  @override
  ConsumerState<CustomServiceFaqsDialog> createState() =>
      _CustomServiceFaqsDialogState();
}

class _CustomServiceFaqsDialogState
    extends ConsumerState<CustomServiceFaqsDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.showQuestions ? 1 : 0,
    );
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final faqsAsync =
        ref.watch(customServiceFaqsNotifierProvider(widget.customServiceId));
    final faqsNotifier = ref
        .read(customServiceFaqsNotifierProvider(widget.customServiceId).notifier);

    final providerKey = (
      customServiceId: widget.customServiceId,
      serviceName: widget.serviceName,
    );
    final questionsAsync =
        ref.watch(customServiceQuestionsNotifierProvider(providerKey));
    final questionsNotifier = ref
        .read(customServiceQuestionsNotifierProvider(providerKey).notifier);

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
              padding: const EdgeInsets.fromLTRB(24, 18, 16, 0),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.quiz_rounded,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'FAQs & Questions',
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
                      if (_tabController.index == 0)
                        FilledButton.icon(
                          onPressed: () => _openCreate(context, faqsNotifier),
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('Add FAQ'),
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.18),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                          ),
                        ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white70),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TabBar(
                    controller: _tabController,
                    indicatorColor: Colors.white,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white60,
                    labelStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    tabs: const [
                      Tab(text: 'Admin FAQs'),
                      Tab(text: 'Customer Questions'),
                    ],
                  ),
                ],
              ),
            ),

            // ── Body ──────────────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // ── Admin FAQs tab ─────────────────────────────────────
                  faqsAsync.when(
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium),
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
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 8),
                        itemBuilder: (ctx, i) => _FaqTile(
                          faq: faqs[i],
                          onEdit: () =>
                              _openEdit(context, faqsNotifier, faqs[i]),
                          onDelete: () =>
                              _confirmDeleteFaq(context, faqsNotifier, faqs[i]),
                        ),
                      );
                    },
                  ),

                  // ── Customer Questions tab ─────────────────────────────
                  questionsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) =>
                        Center(child: Text('Error loading questions: $e')),
                    data: (questions) {
                      if (questions.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.help_outline_rounded,
                                  size: 52,
                                  color: AppColors.textSecondary),
                              const SizedBox(height: 12),
                              Text('No customer questions yet',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium),
                              const SizedBox(height: 6),
                              const Text(
                                'Questions submitted by customers will appear here.',
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
                        itemCount: questions.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final q = questions[i];
                          return _QuestionTile(
                            question: q,
                            onDelete: () => _confirmDeleteQuestion(
                                ctx, questionsNotifier, q),
                          );
                        },
                      );
                    },
                  ),
                ],
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

  Future<void> _confirmDeleteFaq(BuildContext context,
      CustomServiceFaqsNotifier notifier, ServiceFaq faq) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete FAQ?'),
        content: Text(
            'Delete "${faq.question.length > 60 ? '${faq.question.substring(0, 60)}…' : faq.question}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await notifier.delete(faq.id);
  }

  Future<void> _confirmDeleteQuestion(
    BuildContext context,
    CustomServiceQuestionsNotifier notifier,
    CustomerQuestion question,
  ) async {
    final preview = question.question.length > 60
        ? '${question.question.substring(0, 60)}…'
        : question.question;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Question?'),
        content: Text('Delete "$preview"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await notifier.deleteQuestion(question.id);
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

// ── Question tile ─────────────────────────────────────────────────────────────

class _QuestionTile extends StatelessWidget {
  const _QuestionTile({
    required this.question,
    required this.onDelete,
  });

  final CustomerQuestion question;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isPending = question.isPending;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPending
              ? AppColors.warning.withValues(alpha: 0.5)
              : AppColors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isPending
                  ? Icons.help_outline_rounded
                  : Icons.check_circle_outline_rounded,
              size: 16,
              color: isPending ? AppColors.warning : AppColors.success,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    question.question,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (question.customerName != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      'by ${question.customerName}${question.customerPhone != null ? ' · ${question.customerPhone}' : ''}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  if (question.isAnswered && question.answer != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FAF4),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        question.answer!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
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
      ),
    );
  }
}

