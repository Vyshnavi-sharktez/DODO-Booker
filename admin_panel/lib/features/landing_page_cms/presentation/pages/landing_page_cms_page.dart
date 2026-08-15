import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/landing_page_cms_providers.dart';
import '../../domain/models/landing_page_section.dart';
import '../widgets/add_section_dialog.dart';
import '../widgets/preview_dialog.dart';
import '../widgets/section_edit_dialog.dart';
import '../widgets/section_list_tile.dart';

class LandingPageCmsPage extends ConsumerWidget {
  const LandingPageCmsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sectionsAsync = ref.watch(landingPageCmsNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Page header ──────────────────────────────────────────────────
          _PageHeader(
            sectionsAsync: sectionsAsync,
            onPreview: () {
              final sections = sectionsAsync.valueOrNull ?? [];
              PreviewDialog.show(context, sections);
            },
            onPublish: () => _publish(context, ref, sectionsAsync.valueOrNull),
          ),

          // ── Body ─────────────────────────────────────────────────────────
          Expanded(
            child: sectionsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AppColors.error, size: 36),
                    const SizedBox(height: 12),
                    Text('Failed to load sections: $e',
                        style: const TextStyle(color: AppColors.error)),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () =>
                          ref.invalidate(landingPageCmsNotifierProvider),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (sections) => _SectionBody(sections: sections),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _publish(
    BuildContext context,
    WidgetRef ref,
    List<LandingPageSection>? sections,
  ) async {
    if (sections == null) return;

    final enabledCount = sections.where((s) => s.isEnabled).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _PublishConfirmDialog(enabledCount: enabledCount),
    );
    if (confirmed != true || !context.mounted) return;

    await ref.read(landingPageCmsNotifierProvider.notifier).publishAll();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Landing page published successfully.'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }
}

// ── Section body with stats + reorderable list ────────────────────────────────

class _SectionBody extends ConsumerWidget {
  const _SectionBody({required this.sections});
  final List<LandingPageSection> sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(landingPageCmsNotifierProvider.notifier);
    final enabledCount = sections.where((s) => s.isEnabled).length;
    final publishedCount = sections.where((s) => s.isPublished).length;

    return Column(
      children: [
        // ── Stats bar ──────────────────────────────────────────────────────
        Container(
          color: AppColors.surface,
          padding:
              const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          child: Row(
            children: [
              _Stat(label: 'Total', value: '${sections.length}'),
              const SizedBox(width: 24),
              _Stat(
                label: 'Enabled',
                value: '$enabledCount',
                color: AppColors.success,
              ),
              const SizedBox(width: 24),
              _Stat(
                label: 'Published',
                value: '$publishedCount',
                color: AppColors.accent,
              ),
              const Spacer(),
              // ── Add section ─────────────────────────────────────────────
              FilledButton.icon(
                onPressed: () => _addSection(context, ref, sections),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Section'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.border),

        // ── Reorderable list ───────────────────────────────────────────────
        Expanded(
          child: sections.isEmpty
              ? const _EmptyState()
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.all(20),
                  itemCount: sections.length,
                  onReorder: (oldIndex, newIndex) async {
                    try {
                      await notifier.reorder(oldIndex, newIndex);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Failed to save order. Please try again.',
                            ),
                            backgroundColor: AppColors.error,
                            duration: Duration(seconds: 4),
                          ),
                        );
                      }
                    }
                  },
                  proxyDecorator: (child, index, animation) =>
                      Material(
                        elevation: 6,
                        borderRadius: BorderRadius.circular(10),
                        color: AppColors.surface,
                        child: child,
                      ),
                  itemBuilder: (context, index) {
                    final section = sections[index];
                    return SectionListTile(
                      key: ValueKey(section.id),
                      section: section,
                      index: index,
                      onToggleEnabled: (enabled) =>
                          notifier.setEnabled(section.id, enabled: enabled),
                      onEdit: () => _editSection(context, ref, section),
                      onDelete: () =>
                          _confirmDelete(context, ref, section),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _addSection(
    BuildContext context,
    WidgetRef ref,
    List<LandingPageSection> sections,
  ) async {
    final result = await showDialog<
        ({String sectionType, String sectionName, Map<String, dynamic> config})>(
      context: context,
      builder: (_) => const AddSectionDialog(),
    );
    if (result == null || !context.mounted) return;

    await ref.read(landingPageCmsNotifierProvider.notifier).createSection(
          sectionType: result.sectionType,
          sectionName: result.sectionName,
          config: result.config,
        );
  }

  Future<void> _editSection(
    BuildContext context,
    WidgetRef ref,
    LandingPageSection section,
  ) async {
    final result = await showDialog<
        ({String sectionName, Map<String, dynamic> config})>(
      context: context,
      builder: (_) => SectionEditDialog(section: section),
    );
    if (result == null || !context.mounted) return;

    await ref.read(landingPageCmsNotifierProvider.notifier).saveSection(
          section.id,
          sectionName: result.sectionName,
          config: result.config,
        );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    LandingPageSection section,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteConfirmDialog(sectionName: section.sectionName),
    );
    if (confirmed != true || !context.mounted) return;

    await ref
        .read(landingPageCmsNotifierProvider.notifier)
        .deleteSection(section.id);
  }
}

// ── Page header ───────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.sectionsAsync,
    required this.onPreview,
    required this.onPublish,
  });
  final AsyncValue<List<LandingPageSection>> sectionsAsync;
  final VoidCallback onPreview;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    final isLoading = sectionsAsync is AsyncLoading;

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.web_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Landing Page',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Manage sections, ordering, and content of the customer landing page',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Preview button
              OutlinedButton.icon(
                onPressed: isLoading ? null : onPreview,
                icon: const Icon(Icons.preview_rounded, size: 15),
                label: const Text('Preview'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.border),
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 10),
              // Publish button
              FilledButton.icon(
                onPressed: isLoading ? null : onPublish,
                icon: const Icon(Icons.publish_rounded, size: 15),
                label: const Text('Publish All'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.success,
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.border),
        ],
      ),
    );
  }
}

// ── Stat chip ─────────────────────────────────────────────────────────────────

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: color ?? AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.web_rounded,
                size: 30, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          const Text(
            'No sections yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Click "Add Section" to build your landing page.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Dialogs ───────────────────────────────────────────────────────────────────

class _PublishConfirmDialog extends StatelessWidget {
  const _PublishConfirmDialog({required this.enabledCount});
  final int enabledCount;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Publish Landing Page?'),
      content: Text(
        '$enabledCount enabled section${enabledCount == 1 ? '' : 's'} will become visible to customers. '
        'Disabled sections will be taken offline.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.success),
          child: const Text('Publish'),
        ),
      ],
    );
  }
}

class _DeleteConfirmDialog extends StatelessWidget {
  const _DeleteConfirmDialog({required this.sectionName});
  final String sectionName;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete Section?'),
      content: Text(
        '"$sectionName" will be permanently deleted and removed from the landing page.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
