import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../catalog_v2/domain/models/catalog_node.dart';
import '../../application/providers/customer_questions_providers.dart';
import '../../domain/models/customer_question.dart';

class CustomerQuestionsPanel extends ConsumerStatefulWidget {
  const CustomerQuestionsPanel({
    super.key,
    required this.node,
    this.parentNodeId,
    this.focusQuestionId,
  });

  final CatalogNode node;

  /// Scopes questions to this parent context. Null means only questions
  /// submitted without a parent context (strict IS NULL filter), matching
  /// the customer app's own fetchAnsweredQuestionsForNode behaviour.
  final String? parentNodeId;

  /// When set, the list scrolls to this question after data loads.
  final String? focusQuestionId;

  @override
  ConsumerState<CustomerQuestionsPanel> createState() =>
      _CustomerQuestionsPanelState();
}

class _CustomerQuestionsPanelState
    extends ConsumerState<CustomerQuestionsPanel> {
  final _scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = {};
  bool _didScroll = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToFocused() {
    if (_didScroll || widget.focusQuestionId == null) return;
    final key = _itemKeys[widget.focusQuestionId!];
    if (key?.currentContext == null) return;
    _didScroll = true;
    Scrollable.ensureVisible(
      key!.currentContext!,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final providerKey = (
      serviceId: widget.node.id,
      serviceName: widget.node.name,
      parentNodeId: widget.parentNodeId,
    );
    final questionsAsync =
        ref.watch(customerQuestionsNotifierProvider(providerKey));
    final notifier =
        ref.read(customerQuestionsNotifierProvider(providerKey).notifier);

    return questionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (questions) {
        if (widget.focusQuestionId != null) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _scrollToFocused());
        }
        if (questions.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.help_outline_rounded,
                    size: 52, color: AppColors.textSecondary),
                const SizedBox(height: 12),
                Text(
                  'No customer questions yet',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Questions submitted by customers will appear here.',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          );
        }
        return ListView.separated(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: questions.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) {
            final q = questions[i];
            final itemKey =
                _itemKeys.putIfAbsent(q.id, () => GlobalKey());
            return KeyedSubtree(
              key: itemKey,
              child: _QuestionTile(
                question: q,
                onAnswer: () => _openAnswerDialog(ctx, notifier, q),
                onDelete: () => _confirmDelete(ctx, notifier, q),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openAnswerDialog(
    BuildContext context,
    CustomerQuestionsNotifier notifier,
    CustomerQuestion question,
  ) async {
    final ctrl = TextEditingController(text: question.answer ?? '');
    final confirmed = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AnswerDialog(
        question: question,
        controller: ctrl,
      ),
    );
    ctrl.dispose();
    if (confirmed != null) {
      await notifier.answerQuestion(question, answer: confirmed);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    CustomerQuestionsNotifier notifier,
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
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await notifier.deleteQuestion(question.id);
  }
}

// ── Question tile ─────────────────────────────────────────────────────────────

class _QuestionTile extends StatelessWidget {
  const _QuestionTile({
    required this.question,
    required this.onAnswer,
    required this.onDelete,
  });

  final CustomerQuestion question;
  final VoidCallback onAnswer;
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isPending
                      ? Icons.help_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 16,
                  color: isPending
                      ? AppColors.warning
                      : AppColors.success,
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
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        isPending
                            ? Icons.reply_rounded
                            : Icons.edit_outlined,
                        size: 16,
                      ),
                      tooltip: isPending ? 'Answer' : 'Edit Answer',
                      color: AppColors.primary,
                      visualDensity: VisualDensity.compact,
                      onPressed: onAnswer,
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
          ],
        ),
      ),
    );
  }
}

// ── Answer dialog ─────────────────────────────────────────────────────────────

class _AnswerDialog extends StatelessWidget {
  const _AnswerDialog({
    required this.question,
    required this.controller,
  });

  final CustomerQuestion question;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('Answer Question'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                question.question,
                style: tt.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: 'Answer',
                hintText: 'Write a clear and helpful answer...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final answer = controller.text.trim();
            if (answer.isEmpty) return;
            Navigator.of(context).pop(answer);
          },
          child: const Text('Publish Answer'),
        ),
      ],
    );
  }
}
