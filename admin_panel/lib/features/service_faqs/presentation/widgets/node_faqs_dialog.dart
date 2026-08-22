import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../catalog_v2/domain/models/catalog_node.dart';
import '../../../customer_questions/presentation/widgets/customer_questions_panel.dart';
import '../../application/providers/service_faqs_providers.dart';
import '../../domain/models/service_faq.dart';
import 'faq_form_dialog.dart';

class NodeFaqsDialog extends ConsumerStatefulWidget {
  const NodeFaqsDialog({super.key, required this.node, this.parentId});

  final CatalogNode node;

  /// The parent node ID from which this service was opened in the catalog tree.
  /// Used to scope customer questions to this specific parent context.
  final String? parentId;

  static Future<void> show(
    BuildContext context,
    CatalogNode node, {
    String? parentId,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => NodeFaqsDialog(node: node, parentId: parentId),
    );
  }

  @override
  ConsumerState<NodeFaqsDialog> createState() => _NodeFaqsDialogState();
}

class _NodeFaqsDialogState extends ConsumerState<NodeFaqsDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  CatalogNode get node => widget.node;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final faqsAsync = ref.watch(serviceFaqsNotifierProvider(node.id));
    final notifier = ref.read(serviceFaqsNotifierProvider(node.id).notifier);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 18, 16, 12),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                              node.name,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      ListenableBuilder(
                        listenable: _tabController,
                        builder: (_, _) => _tabController.index == 0
                            ? FilledButton.icon(
                                onPressed: () =>
                                    _openCreate(context, notifier),
                                icon: const Icon(Icons.add_rounded, size: 16),
                                label: const Text('Add FAQ'),
                                style: FilledButton.styleFrom(
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.18),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                ),
                              )
                            : const SizedBox.shrink(),
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
                  const SizedBox(height: 8),
                  TabBar(
                    controller: _tabController,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white54,
                    indicatorColor: Colors.white,
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

            // ── Body ────────────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // ── Tab 1: Admin FAQs ───────────────────────────────
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
                              Text(
                                'No FAQs yet',
                                style:
                                    Theme.of(context).textTheme.titleMedium,
                              ),
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
                              _openEdit(context, notifier, faqs[i]),
                          onDelete: () =>
                              _confirmDelete(context, notifier, faqs[i]),
                        ),
                      );
                    },
                  ),

                  // ── Tab 2: Customer Questions ───────────────────────
                  CustomerQuestionsPanel(node: node, parentNodeId: widget.parentId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCreate(
      BuildContext context, ServiceFaqsNotifier notifier) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => FaqFormDialog(
        onSave: ({required question, required answer}) =>
            notifier.create(question: question, answer: answer),
      ),
    );
  }

  void _openEdit(BuildContext context, ServiceFaqsNotifier notifier,
      ServiceFaq faq) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => FaqFormDialog(
        existing: faq,
        onSave: ({required question, required answer}) =>
            notifier.update(faq.id,
                question: question,
                answer: answer,
                sortOrder: faq.sortOrder),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context,
      ServiceFaqsNotifier notifier, ServiceFaq faq) async {
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
