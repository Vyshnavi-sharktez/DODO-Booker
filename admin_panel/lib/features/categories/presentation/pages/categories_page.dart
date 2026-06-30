import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/categories_providers.dart';
import '../../domain/models/category.dart';
import '../widgets/category_form_dialog.dart';

class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});

  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Category> _applySearch(List<Category> all) {
    if (_searchQuery.isEmpty) return all;
    final q = _searchQuery.toLowerCase();
    return all
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            c.slug.toLowerCase().contains(q))
        .toList();
  }

  void _openCreate() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CategoryFormDialog(
        onSave: ({
          required name,
          required slug,
          imageUrl,
          required sortOrder,
          required isActive,
        }) async {
          await ref.read(categoriesNotifierProvider.notifier).createCategory(
                name: name,
                slug: slug,
                imageUrl: imageUrl,
                sortOrder: sortOrder,
                isActive: isActive,
              );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Category created successfully')),
            );
          }
        },
      ),
    );
  }

  void _openEdit(Category category) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CategoryFormDialog(
        existing: category,
        onSave: ({
          required name,
          required slug,
          imageUrl,
          required sortOrder,
          required isActive,
        }) async {
          await ref
              .read(categoriesNotifierProvider.notifier)
              .updateCategory(
                category.id,
                name: name,
                slug: slug,
                imageUrl: imageUrl,
                sortOrder: sortOrder,
                isActive: isActive,
              );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Category updated successfully')),
            );
          }
        },
      ),
    );
  }

  Future<void> _confirmDelete(Category category) async {
    // ── Step 1: check for dependent sub-categories and services ───────────────
    late final ({int subCategories, int services}) counts;
    try {
      counts = await ref
          .read(categoriesRepositoryProvider)
          .countDependents(category.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Unable to validate category deletion. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    // ── Step 2a: dependents exist → show blocking dialog ──────────────────────
    if (counts.subCategories > 0 || counts.services > 0) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => _CategoryBlockedDialog(
          categoryName: category.name,
          subCategoryCount: counts.subCategories,
          serviceCount: counts.services,
          onViewSubCategories: () {
            Navigator.of(ctx).pop();
            context.go(
              '/dashboard/sub-categories?categoryId=${category.id}',
            );
          },
        ),
      );
      return;
    }

    // ── Step 2b: safe to delete → standard confirmation dialog ────────────────
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Category'),
        content: Text(
          'Are you sure you want to delete "${category.name}"?\n\nThis action cannot be undone.',
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

    // ── Step 3: perform deletion ───────────────────────────────────────────────
    try {
      await ref
          .read(categoriesNotifierProvider.notifier)
          .deleteCategory(category.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Category deleted successfully.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Unable to validate category deletion. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _toggle(Category category) async {
    try {
      await ref
          .read(categoriesNotifierProvider.notifier)
          .toggleActive(category.id, isActive: !category.isActive);
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
    final state = ref.watch(categoriesNotifierProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Responsive Header ──────────────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 600;
              return Flex(
                direction: narrow ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: narrow
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Categories',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Manage service categories',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  if (narrow) const SizedBox(height: 12) else const Spacer(),
                  FilledButton.icon(
                    onPressed: _openCreate,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('New Category'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // ── Search ─────────────────────────────────────────────────────────
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by name or slug…',
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
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onChanged: (v) => setState(() => _searchQuery = v.trim()),
          ),
          const SizedBox(height: 20),

          // ── Body ────────────────────────────────────────────────────────────
          Expanded(
            child: state.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 48, color: AppColors.error),
                    const SizedBox(height: 12),
                    Text(
                      'Failed to load categories',
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
                          .read(categoriesNotifierProvider.notifier)
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
                    message: 'No categories yet',
                    sub: 'Click "New Category" to add your first one.',
                    onAdd: _openCreate,
                  );
                }
                if (filtered.isEmpty) {
                  return _EmptyState(
                    message: 'No results for "$_searchQuery"',
                    sub: 'Try a different search term.',
                  );
                }
                return _CategoriesTable(
                  categories: filtered,
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

// ── Table ─────────────────────────────────────────────────────────────────────

class _CategoriesTable extends StatelessWidget {
  final List<Category> categories;
  final void Function(Category) onEdit;
  final void Function(Category) onDelete;
  final void Function(Category) onToggle;

  const _CategoriesTable({
    required this.categories,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  static const double _minTableWidth = 700;

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
            // Scrollable section: header + rows
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tableWidth = constraints.maxWidth < _minTableWidth
                      ? _minTableWidth
                      : constraints.maxWidth;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header row
                          Container(
                            color: AppColors.background,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                _HeaderCell('Name', flex: 3),
                                _HeaderCell('Slug', flex: 3),
                                _HeaderCell('Sort', flex: 1),
                                _HeaderCell('Status', flex: 2),
                                _HeaderCell('Created', flex: 2),
                                _HeaderCell('Actions', flex: 2,
                                    align: TextAlign.center),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          // Data rows
                          Expanded(
                            child: ListView.separated(
                              itemCount: categories.length,
                              separatorBuilder: (_, i) =>
                                  const Divider(height: 1),
                              itemBuilder: (ctx, i) {
                                final cat = categories[i];
                                return _CategoryRow(
                                  category: cat,
                                  onEdit: () => onEdit(cat),
                                  onDelete: () => onDelete(cat),
                                  onToggle: () => onToggle(cat),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // Footer count — stays outside horizontal scroll
            Container(
              color: AppColors.background,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                '${categories.length} categor${categories.length == 1 ? 'y' : 'ies'}',
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

class _CategoryRow extends StatelessWidget {
  final Category category;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  const _CategoryRow({
    required this.category,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final createdStr = category.createdAt != null
        ? DateFormat('dd MMM yyyy').format(category.createdAt!)
        : '—';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Name
          Expanded(
            flex: 3,
            child: Text(
              category.name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Slug
          Expanded(
            flex: 3,
            child: Text(
              category.slug,
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
              category.sortOrder.toString(),
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),

          // Status badge
          Expanded(
            flex: 2,
            child: _StatusBadge(isActive: category.isActive),
          ),

          // Created at
          Expanded(
            flex: 2,
            child: Text(
              createdStr,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),

          // Actions
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 40,
                  height: 24,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Switch(
                      value: category.isActive,
                      onChanged: (_) => onToggle(),
                      activeThumbColor: AppColors.success,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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

// ── Deletion-blocked dialog ────────────────────────────────────────────────────
// Shown when the category still has sub-categories or services linked to it.

class _CategoryBlockedDialog extends StatelessWidget {
  final String categoryName;
  final int subCategoryCount;
  final int serviceCount;
  final VoidCallback onViewSubCategories;

  const _CategoryBlockedDialog({
    required this.categoryName,
    required this.subCategoryCount,
    required this.serviceCount,
    required this.onViewSubCategories,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text('Delete Category?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This category cannot be deleted because it still contains:',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _BulletRow(
            '$subCategoryCount Sub Categor${subCategoryCount == 1 ? 'y' : 'ies'}',
          ),
          const SizedBox(height: 6),
          _BulletRow(
            '$serviceCount Service${serviceCount == 1 ? '' : 's'}',
          ),
          const SizedBox(height: 16),
          Text(
            'You must remove or move these items before deleting this category.',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: onViewSubCategories,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
          ),
          child: const Text('View Sub Categories'),
        ),
      ],
    );
  }
}

class _BulletRow extends StatelessWidget {
  final String text;
  const _BulletRow(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            color: AppColors.textSecondary,
            shape: BoxShape.circle,
          ),
        ),
        Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
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
            Icons.category_outlined,
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
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          if (onAdd != null) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('New Category'),
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
