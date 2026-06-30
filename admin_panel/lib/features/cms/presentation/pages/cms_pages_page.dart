import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/clickable.dart';
import '../../application/providers/cms_providers.dart';
import '../../domain/models/cms_page.dart';
import '../widgets/cms_page_form_dialog.dart';
import '../widgets/seo_setting_dialog.dart';

enum _PublishFilter { all, published, draft }

class CmsPagesPage extends ConsumerStatefulWidget {
  const CmsPagesPage({super.key});

  @override
  ConsumerState<CmsPagesPage> createState() => _CmsPagesPageState();
}

class _CmsPagesPageState extends ConsumerState<CmsPagesPage> {
  final _searchCtrl = TextEditingController();
  _PublishFilter _filter = _PublishFilter.all;

  static final _dateFmt = DateFormat('dd MMM yyyy');

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<CmsPage> _applyFilters(List<CmsPage> pages) {
    final query = _searchCtrl.text.trim().toLowerCase();
    return pages.where((p) {
      final matchesSearch = query.isEmpty ||
          p.pageTitle.toLowerCase().contains(query) ||
          p.pageSlug.toLowerCase().contains(query);
      final matchesFilter = switch (_filter) {
        _PublishFilter.all => true,
        _PublishFilter.published => p.isPublished,
        _PublishFilter.draft => !p.isPublished,
      };
      return matchesSearch && matchesFilter;
    }).toList();
  }

  Future<void> _openCreateDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const CmsPageFormDialog(),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Page created successfully'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _openEditDialog(CmsPage page) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => CmsPageFormDialog(page: page),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Page updated successfully'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _openSeoDialog(CmsPage page) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => SeoSettingDialog(
        pageSlug: page.pageSlug,
        pageTitle: page.pageTitle,
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SEO settings saved'),
          backgroundColor: Color(0xFF805AD5),
        ),
      );
    }
  }

  Future<void> _togglePublish(CmsPage page) async {
    try {
      await ref
          .read(cmsPagesNotifierProvider.notifier)
          .togglePublished(page.id, currentIsPublished: page.isPublished);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              page.isPublished
                  ? '"${page.pageTitle}" unpublished'
                  : '"${page.pageTitle}" published',
            ),
            backgroundColor:
                page.isPublished ? AppColors.warning : AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete(CmsPage page) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Page'),
        content: Text(
          'Delete "${page.pageTitle}"? This action cannot be undone.',
        ),
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
    if (confirmed != true) return;
    try {
      await ref.read(cmsPagesNotifierProvider.notifier).deletePage(page.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Page deleted'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting page: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pagesAsync = ref.watch(cmsPagesNotifierProvider);

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Stats ──────────────────────────────────────────────────────
          pagesAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (e, st) => const SizedBox.shrink(),
            data: (pages) => _StatsRow(pages: pages),
          ),
          const SizedBox(height: 24),

          // ── Main panel ─────────────────────────────────────────────────
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  // Toolbar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final narrow = constraints.maxWidth < 640;
                        return Flex(
                          direction:
                              narrow ? Axis.vertical : Axis.horizontal,
                          crossAxisAlignment: narrow
                              ? CrossAxisAlignment.start
                              : CrossAxisAlignment.center,
                          children: [
                            const Text(
                              'CMS Pages',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (!narrow) const Spacer(),
                            if (narrow) const SizedBox(height: 10),
                            // Search + chips + button row (wrap on narrow)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                SizedBox(
                                  width: 200,
                                  height: 36,
                                  child: TextField(
                                    controller: _searchCtrl,
                                    onChanged: (_) => setState(() {}),
                                    decoration: InputDecoration(
                                      hintText: 'Search title or slug…',
                                      prefixIcon: const Icon(
                                          Icons.search,
                                          size: 18),
                                      contentPadding: EdgeInsets.zero,
                                      border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                            color: AppColors.border),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                            color: AppColors.border),
                                      ),
                                    ),
                                  ),
                                ),
                                _FilterChip(
                                  label: 'All',
                                  selected:
                                      _filter == _PublishFilter.all,
                                  onTap: () => setState(
                                      () => _filter = _PublishFilter.all),
                                ),
                                _FilterChip(
                                  label: 'Published',
                                  selected:
                                      _filter == _PublishFilter.published,
                                  color: AppColors.success,
                                  onTap: () => setState(() =>
                                      _filter = _PublishFilter.published),
                                ),
                                _FilterChip(
                                  label: 'Draft',
                                  selected:
                                      _filter == _PublishFilter.draft,
                                  color: AppColors.textSecondary,
                                  onTap: () => setState(() =>
                                      _filter = _PublishFilter.draft),
                                ),
                                FilledButton.icon(
                                  onPressed: _openCreateDialog,
                                  icon: const Icon(Icons.add_rounded,
                                      size: 18),
                                  label: const Text('New Page'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.border),

                  // Table
                  Expanded(
                    child: pagesAsync.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      error: (e, _) => Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 40,
                              color: AppColors.error,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Error loading pages: $e',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextButton.icon(
                              onPressed: () => ref
                                  .read(cmsPagesNotifierProvider.notifier)
                                  .refresh(),
                              icon: const Icon(Icons.refresh_rounded,
                                  size: 16),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                      data: (pages) {
                        final filtered = _applyFilters(pages);
                        if (filtered.isEmpty) {
                          return _EmptyState(
                            hasPages: pages.isNotEmpty,
                            onCreatePage: _openCreateDialog,
                          );
                        }
                        return _PagesTable(
                          pages: filtered,
                          dateFmt: _dateFmt,
                          onEdit: _openEditDialog,
                          onSeo: _openSeoDialog,
                          onTogglePublish: _togglePublish,
                          onDelete: _confirmDelete,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stats Row ──────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.pages});
  final List<CmsPage> pages;

  @override
  Widget build(BuildContext context) {
    final published = pages.where((p) => p.isPublished).length;
    final draft = pages.length - published;

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Total Pages',
            value: pages.length.toString(),
            icon: Icons.article_rounded,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _StatCard(
            label: 'Published',
            value: published.toString(),
            icon: Icons.visibility_rounded,
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _StatCard(
            label: 'Draft',
            value: draft.toString(),
            icon: Icons.drafts_rounded,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Pages Table ───────────────────────────────────────────────────────────────

class _PagesTable extends StatelessWidget {
  const _PagesTable({
    required this.pages,
    required this.dateFmt,
    required this.onEdit,
    required this.onSeo,
    required this.onTogglePublish,
    required this.onDelete,
  });
  final List<CmsPage> pages;
  final DateFormat dateFmt;
  final void Function(CmsPage) onEdit;
  final void Function(CmsPage) onSeo;
  final void Function(CmsPage) onTogglePublish;
  final void Function(CmsPage) onDelete;

  static const double _minTableWidth = 700;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth < _minTableWidth
            ? _minTableWidth
            : constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: SingleChildScrollView(child: Table(
        columnWidths: const {
          0: FlexColumnWidth(3),
          1: FlexColumnWidth(2),
          2: FlexColumnWidth(1.5),
          3: FlexColumnWidth(1.5),
          4: FlexColumnWidth(1.5),
          5: FlexColumnWidth(2.5),
        },
        children: [
          TableRow(
            decoration: const BoxDecoration(color: AppColors.background),
            children: const [
              _TH('Title'),
              _TH('Slug'),
              _TH('Status'),
              _TH('Created'),
              _TH('Updated'),
              _TH('Actions'),
            ],
          ),
          for (final page in pages)
            TableRow(
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.border, width: 0.5),
                ),
              ),
              children: [
                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Text(
                    page.pageTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                // Slug
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      '/${page.pageSlug}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
                // Status
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: _StatusBadge(isPublished: page.isPublished),
                ),
                // Created
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Text(
                    page.createdAt != null
                        ? dateFmt.format(page.createdAt!)
                        : '—',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                // Updated
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Text(
                    page.updatedAt != null
                        ? dateFmt.format(page.updatedAt!)
                        : '—',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                // Actions
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ActionIconButton(
                        icon: Icons.edit_rounded,
                        tooltip: 'Edit',
                        color: AppColors.primary,
                        onTap: () => onEdit(page),
                      ),
                      const SizedBox(width: 4),
                      _ActionIconButton(
                        icon: Icons.manage_search_rounded,
                        tooltip: 'SEO Settings',
                        color: const Color(0xFF805AD5),
                        onTap: () => onSeo(page),
                      ),
                      const SizedBox(width: 4),
                      _ActionIconButton(
                        icon: page.isPublished
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        tooltip:
                            page.isPublished ? 'Unpublish' : 'Publish',
                        color: page.isPublished
                            ? AppColors.warning
                            : AppColors.success,
                        onTap: () => onTogglePublish(page),
                      ),
                      const SizedBox(width: 4),
                      _ActionIconButton(
                        icon: Icons.delete_outline_rounded,
                        tooltip: 'Delete',
                        color: AppColors.error,
                        onTap: () => onDelete(page),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
        )),
          ),
        );
      },
    );
  }
}

class _TH extends StatelessWidget {
  const _TH(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isPublished});
  final bool isPublished;

  @override
  Widget build(BuildContext context) {
    final color = isPublished ? AppColors.success : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            isPublished ? 'Published' : 'Draft',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionIconButton extends StatefulWidget {
  const _ActionIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_ActionIconButton> createState() => _ActionIconButtonState();
}

class _ActionIconButtonState extends State<_ActionIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: Clickable(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _hovered
                  ? widget.color.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(widget.icon, size: 17, color: widget.color),
          ),
        ),
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.hasPages,
    required this.onCreatePage,
  });
  final bool hasPages;
  final VoidCallback onCreatePage;

  @override
  Widget build(BuildContext context) {
    if (hasPages) {
      // There are pages but the search/filter returned nothing
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 40, color: AppColors.border),
            SizedBox(height: 12),
            Text(
              'No pages match your search',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    // No pages at all — show default page suggestions
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.article_outlined,
              size: 32,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No pages yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create your first CMS page or start with a default page below.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 28),
          const Text(
            'DEFAULT PAGES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              for (final (title, slug) in kCmsDefaultPages)
                _DefaultPageCard(
                  title: title,
                  slug: slug,
                  onTap: onCreatePage,
                ),
            ],
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: onCreatePage,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Create a New Page'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _DefaultPageCard extends StatefulWidget {
  const _DefaultPageCard({
    required this.title,
    required this.slug,
    required this.onTap,
  });
  final String title;
  final String slug;
  final VoidCallback onTap;

  @override
  State<_DefaultPageCard> createState() => _DefaultPageCardState();
}

class _DefaultPageCardState extends State<_DefaultPageCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: Clickable(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.primary.withValues(alpha: 0.06)
                : AppColors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Column(
            children: [
              const Icon(Icons.article_rounded,
                  size: 24, color: AppColors.primary),
              const SizedBox(height: 6),
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '/${widget.slug}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Filter chip ────────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    this.color = AppColors.primary,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Clickable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.12)
              : AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? color : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
