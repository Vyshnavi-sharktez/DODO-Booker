import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../categories/application/providers/categories_providers.dart';
import '../../../categories/domain/models/category.dart';
import '../../../sub_categories/application/providers/sub_categories_providers.dart';
import '../../../sub_categories/domain/models/sub_category.dart';
import '../../application/providers/services_providers.dart';
import '../../domain/models/service.dart';
import '../widgets/service_form_dialog.dart';

class ServicesPage extends ConsumerStatefulWidget {
  const ServicesPage({super.key});

  @override
  ConsumerState<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends ConsumerState<ServicesPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Service> _applySearch(List<Service> all) {
    if (_searchQuery.isEmpty) return all;
    final q = _searchQuery.toLowerCase();
    return all
        .where((s) => s.name.toLowerCase().contains(q))
        .toList();
  }

  List<Category> _categoriesForDialog() {
    final all = ref.read(categoriesNotifierProvider).valueOrNull ?? [];
    return all.where((c) => c.isActive).toList();
  }

  List<Category> _categoriesForEdit(Service service) {
    final all = ref.read(categoriesNotifierProvider).valueOrNull ?? [];
    final active = all.where((c) => c.isActive).toList();
    final current = all.where((c) => c.id == service.categoryId).toList();
    return [
      ...current,
      ...active.where((c) => c.id != service.categoryId),
    ];
  }

  List<SubCategory> _allSubCategories() {
    return ref.read(subCategoriesNotifierProvider).valueOrNull ?? [];
  }

  void _openCreate() {
    final cats = _categoriesForDialog();
    if (cats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('No active categories found. Create a category first.'),
        ),
      );
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ServiceFormDialog(
        categories: cats,
        allSubCategories: _allSubCategories(),
        onSave: ({
          required categoryId,
          required subCategoryId,
          required name,
          required slug,
          description,
          required basePrice,
          required estimatedDuration,
          imageUrl,
          required isActive,
        }) async {
          await ref.read(servicesNotifierProvider.notifier).createService(
                categoryId: categoryId,
                subCategoryId: subCategoryId,
                name: name,
                slug: slug,
                description: description,
                basePrice: basePrice,
                estimatedDuration: estimatedDuration,
                imageUrl: imageUrl,
                isActive: isActive,
              );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Service created successfully')),
            );
          }
        },
      ),
    );
  }

  void _openEdit(Service service) {
    final cats = _categoriesForEdit(service);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ServiceFormDialog(
        existing: service,
        categories: cats,
        allSubCategories: _allSubCategories(),
        onSave: ({
          required categoryId,
          required subCategoryId,
          required name,
          required slug,
          description,
          required basePrice,
          required estimatedDuration,
          imageUrl,
          required isActive,
        }) async {
          await ref.read(servicesNotifierProvider.notifier).updateService(
                service.id,
                categoryId: categoryId,
                subCategoryId: subCategoryId,
                name: name,
                slug: slug,
                description: description,
                basePrice: basePrice,
                estimatedDuration: estimatedDuration,
                imageUrl: imageUrl,
                isActive: isActive,
              );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Service updated successfully')),
            );
          }
        },
      ),
    );
  }

  Future<void> _confirmDelete(Service service) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Service'),
        content: Text(
          'Are you sure you want to delete "${service.name}"?\n\nThis action cannot be undone.',
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
          .read(servicesNotifierProvider.notifier)
          .deleteService(service.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Service deleted')),
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

  Future<void> _toggle(Service service) async {
    try {
      await ref
          .read(servicesNotifierProvider.notifier)
          .toggleActive(service.id, isActive: !service.isActive);
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
    // Pre-load so dropdowns are ready when dialogs open
    ref.watch(categoriesNotifierProvider);
    ref.watch(subCategoriesNotifierProvider);

    final state = ref.watch(servicesNotifierProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Services',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Manage bookable services',
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
                label: const Text('New Service'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Search ────────────────────────────────────────────────────────
          SizedBox(
            width: 320,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by service name…',
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

          // ── Body ──────────────────────────────────────────────────────────
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
                      'Failed to load services',
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
                          .read(servicesNotifierProvider.notifier)
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
                    message: 'No services yet',
                    sub: 'Click "New Service" to add your first one.',
                    onAdd: _openCreate,
                  );
                }
                if (filtered.isEmpty) {
                  return _EmptyState(
                    message: 'No results for "$_searchQuery"',
                    sub: 'Try a different search term.',
                  );
                }
                return _ServicesTable(
                  services: filtered,
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

class _ServicesTable extends StatelessWidget {
  final List<Service> services;
  final void Function(Service) onEdit;
  final void Function(Service) onDelete;
  final void Function(Service) onToggle;

  const _ServicesTable({
    required this.services,
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
              child: const Row(
                children: [
                  _HeaderCell('Service Name', flex: 3),
                  _HeaderCell('Category', flex: 2),
                  _HeaderCell('Sub Category', flex: 2),
                  _HeaderCell('Base Price', flex: 2),
                  _HeaderCell('Duration', flex: 2),
                  _HeaderCell('Status', flex: 2),
                  _HeaderCell('Actions', flex: 2, align: TextAlign.center),
                ],
              ),
            ),
            const Divider(height: 1),
            // Rows
            Expanded(
              child: ListView.separated(
                itemCount: services.length,
                separatorBuilder: (_, i) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final svc = services[i];
                  return _ServiceRow(
                    service: svc,
                    onEdit: () => onEdit(svc),
                    onDelete: () => onDelete(svc),
                    onToggle: () => onToggle(svc),
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
                '${services.length} service${services.length == 1 ? '' : 's'}',
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

class _ServiceRow extends StatelessWidget {
  final Service service;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  const _ServiceRow({
    required this.service,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  String _formatDuration(int minutes) {
    if (minutes <= 0) return '—';
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final priceStr =
        NumberFormat.currency(symbol: '₹', decimalDigits: 2)
            .format(service.basePrice);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Service Name
          Expanded(
            flex: 3,
            child: Text(
              service.name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Category
          Expanded(
            flex: 2,
            child: _Chip(
              name: service.categoryName,
              color: AppColors.primary,
            ),
          ),

          // Sub Category
          Expanded(
            flex: 2,
            child: _Chip(
              name: service.subCategoryName,
              color: AppColors.accent,
            ),
          ),

          // Base Price
          Expanded(
            flex: 2,
            child: Text(
              priceStr,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),

          // Duration
          Expanded(
            flex: 2,
            child: Text(
              _formatDuration(service.estimatedDuration),
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
          ),

          // Status
          Expanded(
            flex: 2,
            child: _StatusBadge(isActive: service.isActive),
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
                    value: service.isActive,
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

class _Chip extends StatelessWidget {
  final String name;
  final Color color;
  const _Chip({required this.name, required this.color});

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
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          name,
          style: TextStyle(
            fontSize: 12,
            color: color,
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
            Icons.home_repair_service_outlined,
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
            style:
                TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          if (onAdd != null) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('New Service'),
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
