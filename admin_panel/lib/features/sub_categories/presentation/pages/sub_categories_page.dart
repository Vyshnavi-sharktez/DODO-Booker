import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../categories/application/providers/categories_providers.dart';
import '../../../categories/domain/models/category.dart';
import '../../application/providers/sub_categories_providers.dart';
import '../../domain/models/sub_category.dart';
import '../widgets/sub_category_form_dialog.dart';

class SubCategoriesPage extends ConsumerStatefulWidget {
  const SubCategoriesPage({super.key});

  @override
  ConsumerState<SubCategoriesPage> createState() => _SubCategoriesPageState();
}

class _SubCategoriesPageState extends ConsumerState<SubCategoriesPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SubCategory> _applySearch(List<SubCategory> all) {
    if (_searchQuery.isEmpty) return all;
    final q = _searchQuery.toLowerCase();
    return all
        .where((s) =>
            s.name.toLowerCase().contains(q) ||
            s.categoryName.toLowerCase().contains(q))
        .toList();
  }

  List<Category> _activeCategories() {
    final state = ref.read(categoriesNotifierProvider);
    return state.valueOrNull?.where((c) => c.isActive).toList() ?? [];
  }

  void _openCreate() {
    final cats = _activeCategories();
    if (cats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No active categories found. Create a category first.'),
        ),
      );
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => SubCategoryFormDialog(
        categories: cats,
        onSave: ({
          required categoryId,
          required name,
          required slug,
          description,
          required sortOrder,
          required isActive,
        }) async {
          await ref
              .read(subCategoriesNotifierProvider.notifier)
              .createSubCategory(
                categoryId: categoryId,
                name: name,
                slug: slug,
                description: description,
                sortOrder: sortOrder,
                isActive: isActive,
              );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Sub category created successfully')),
            );
          }
        },
      ),
    );
  }

  void _openEdit(SubCategory sub) {
    final cats = _activeCategories();
    // Include the sub's current category even if inactive
    final allCats = ref.read(categoriesNotifierProvider).valueOrNull ?? [];
    final current = allCats.where((c) => c.id == sub.categoryId).toList();
    final merged = [
      ...current,
      ...cats.where((c) => c.id != sub.categoryId),
    ];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => SubCategoryFormDialog(
        existing: sub,
        categories: merged,
        onSave: ({
          required categoryId,
          required name,
          required slug,
          description,
          required sortOrder,
          required isActive,
        }) async {
          await ref
              .read(subCategoriesNotifierProvider.notifier)
              .updateSubCategory(
                sub.id,
                categoryId: categoryId,
                name: name,
                slug: slug,
                description: description,
                sortOrder: sortOrder,
                isActive: isActive,
              );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Sub category updated successfully')),
            );
          }
        },
      ),
    );
  }

  Future<void> _confirmDelete(SubCategory sub) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Sub Category'),
        content: Text(
          'Are you sure you want to delete "${sub.name}"?\n\nThis action cannot be undone.',
        ),
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
    if (confirmed != true) return;
    try {
      await ref
          .read(subCategoriesNotifierProvider.notifier)
          .deleteSubCategory(sub.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sub category deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _toggle(SubCategory sub) async {
    try {
      await ref
          .read(subCategoriesNotifierProvider.notifier)
          .toggleActive(sub.id, isActive: !sub.isActive);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pre-load categories so they're ready when dialogs open
    ref.watch(categoriesNotifierProvider);

    final state = ref.watch(subCategoriesNotifierProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────────────────
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sub Categories',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Manage sub categories within each category',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _openCreate,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New Sub Category'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Search ───────────────────────────────────────────────────────
          SizedBox(
            width: 320,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name…',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
              ),
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
            ),
          ),
          const SizedBox(height: 20),

          // ── Body ─────────────────────────────────────────────────────────
          Expanded(
            child: state.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 48, color: AppColors.error),
                    const SizedBox(height: 12),
                    Text(
                      'Failed to load sub categories',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      e.toString(),
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => ref
                          .read(subCategoriesNotifierProvider.notifier)
                          .refresh(),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (all) {
                final filtered = _applySearch(all);
                if (all.isEmpty) {
                  return _EmptyState(
                    message: 'No sub categories yet',
                    sub: 'Click "New Sub Category" to add your first one.',
                    onAdd: _openCreate,
                  );
                }
                if (filtered.isEmpty) {
                  return _EmptyState(
                    message: 'No results for "$_searchQuery"',
                    sub: 'Try a different search term.',
                  );
                }
                return _SubCategoriesTable(
                  subCategories: filtered,
                  onEdit: _openEdit,
                  onDelete: _confirmDelete,
                  onToggle: _toggle,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Table ──────────────────────────────────────────────────────────────────────

class _SubCategoriesTable extends StatelessWidget {
  final List<SubCategory> subCategories;
  final void Function(SubCategory) onEdit;
  final void Function(SubCategory) onDelete;
  final void Function(SubCategory) onToggle;

  const _SubCategoriesTable({
    required this.subCategories,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              color: AppColors.background,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _HeaderCell('Name', flex: 3),
                  _HeaderCell('Category', flex: 2),
                  _HeaderCell('Slug', flex: 3),
                  _HeaderCell('Sort', flex: 1),
                  _HeaderCell('Status', flex: 2),
                  _HeaderCell('Created', flex: 2),
                  _HeaderCell('Actions', flex: 2, align: TextAlign.center),
                ],
              ),
            ),
            const Divider(height: 1),
            // Rows
            Expanded(
              child: ListView.separated(
                itemCount: subCategories.length,
                separatorBuilder: (_, i) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final sub = subCategories[i];
                  return _SubCategoryRow(
                    sub: sub,
                    onEdit: () => onEdit(sub),
                    onDelete: () => onDelete(sub),
                    onToggle: () => onToggle(sub),
                  );
                },
              ),
            ),
            // Footer
            Container(
              color: AppColors.background,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              child: Text(
                '${subCategories.length} sub categor${subCategories.length == 1 ? 'y' : 'ies'}',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  final int flex;
  final TextAlign align;

  const _HeaderCell(this.label,
      {required this.flex, this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: align,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SubCategoryRow extends StatelessWidget {
  final SubCategory sub;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  const _SubCategoryRow({
    required this.sub,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final createdStr = sub.createdAt != null
        ? DateFormat('dd MMM yyyy').format(sub.createdAt!)
        : '—';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Name
          Expanded(
            flex: 3,
            child: Text(
              sub.name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Parent Category
          Expanded(
            flex: 2,
            child: _CategoryChip(name: sub.categoryName),
          ),

          // Slug
          Expanded(
            flex: 3,
            child: Text(
              sub.slug,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Sort order
          Expanded(
            flex: 1,
            child: Text(
              sub.sortOrder.toString(),
              style:
                  TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),

          // Status
          Expanded(
            flex: 2,
            child: _StatusBadge(isActive: sub.isActive),
          ),

          // Created at
          Expanded(
            flex: 2,
            child: Text(
              createdStr,
              style:
                  TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),

          // Actions
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: sub.isActive,
                    onChanged: (_) => onToggle(),
                    activeThumbColor: AppColors.success,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                IconButton(
                  onPressed: onEdit,
                  icon: Icon(Icons.edit_rounded,
                      size: 16, color: AppColors.accent),
                  tooltip: 'Edit',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 16, color: AppColors.error),
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String name;
  const _CategoryChip({required this.name});

  @override
  Widget build(BuildContext context) {
    if (name.isEmpty) {
      return Text(
        '—',
        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
      );
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          name,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.accent,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isActive;
  const _StatusBadge({required this.isActive});

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.success : AppColors.textSecondary;
    final bg = isActive
        ? AppColors.success.withValues(alpha: 0.1)
        : AppColors.textSecondary.withValues(alpha: 0.1);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              isActive ? 'Active' : 'Inactive',
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String message;
  final String sub;
  final VoidCallback? onAdd;

  const _EmptyState({
    required this.message,
    required this.sub,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.list_alt_rounded,
            size: 56,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sub,
            style: TextStyle(
                fontSize: 13, color: AppColors.textSecondary),
          ),
          if (onAdd != null) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('New Sub Category'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
