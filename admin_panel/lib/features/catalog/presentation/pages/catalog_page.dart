import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../categories/application/providers/categories_providers.dart';
import '../../../categories/domain/models/category.dart';
import '../../../categories/presentation/widgets/category_form_dialog.dart';
import '../../../service_attributes/application/providers/service_attributes_providers.dart';
import '../../../services/application/providers/services_providers.dart';
import '../../../services/domain/models/service.dart';
import '../../../services/presentation/widgets/service_form_dialog.dart';
import '../../../sub_categories/application/providers/sub_categories_providers.dart';
import '../../../sub_categories/domain/models/sub_category.dart';
import '../../../sub_categories/presentation/widgets/sub_category_form_dialog.dart';
import '../widgets/catalog_callbacks.dart';
import '../widgets/category_card.dart';
import '../widgets/service_attributes_drawer.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CatalogPage
//
// Responsibilities
//   • Watch the three providers and group data into maps
//   • Manage expand/collapse state for categories and sub-categories
//   • Own all CRUD methods (open/edit/delete dialogs) and pass them down as
//     a single CatalogCallbacks bundle
//   • Pre-filter lists for search before handing them to CategoryCard
//
// Widget tree
//   CatalogPage → CategoryCard → SubCategoryTile → ServiceTile
// ═══════════════════════════════════════════════════════════════════════════════

class CatalogPage extends ConsumerStatefulWidget {
  const CatalogPage({super.key});

  @override
  ConsumerState<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends ConsumerState<CatalogPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _expandedCategories = {};
  final Set<String> _expandedSubCategories = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Expand / collapse ────────────────────────────────────────────────────────

  void _toggleCategory(String catId) {
    setState(() {
      if (_expandedCategories.contains(catId)) {
        _expandedCategories.remove(catId);
      } else {
        _expandedCategories.add(catId);
      }
    });
  }

  void _toggleSubCategory(SubCategory sub) {
    setState(() {
      if (_expandedSubCategories.contains(sub.id)) {
        _expandedSubCategories.remove(sub.id);
      } else {
        // Accordion: only one sub-category open at a time per category.
        final siblings =
            ref.read(subCategoriesNotifierProvider).valueOrNull ?? [];
        for (final s in siblings) {
          if (s.categoryId == sub.categoryId) {
            _expandedSubCategories.remove(s.id);
          }
        }
        _expandedSubCategories.add(sub.id);
      }
    });
  }

  // ── Category CRUD ─────────────────────────────────────────────────────────

  void _openCreateCategory() {
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
              const SnackBar(content: Text('Category created successfully.')),
            );
            final cats =
                ref.read(categoriesNotifierProvider).valueOrNull ?? [];
            final newCat =
                cats.where((c) => c.name == name).firstOrNull;
            if (newCat != null && mounted) {
              _showAddSubCategoryWizard(newCat);
            }
          }
        },
      ),
    );
  }

  void _openEditCategory(Category category) {
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
              const SnackBar(content: Text('Category updated successfully.')),
            );
          }
        },
      ),
    );
  }

  Future<void> _deleteCategory(Category category) async {
    ({int subCategories, int services}) counts;
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
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    if (counts.subCategories > 0 || counts.services > 0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: AppColors.warning, size: 22),
              SizedBox(width: 8),
              Text('Cannot Delete Category'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('"${category.name}" has dependencies that must be removed first:'),
              const SizedBox(height: 12),
              if (counts.subCategories > 0)
                _BulletRow(
                    '${counts.subCategories} Sub ${counts.subCategories == 1 ? "Category" : "Categories"}'),
              if (counts.services > 0)
                _BulletRow(
                    '${counts.services} ${counts.services == 1 ? "Service" : "Services"}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                context.go(
                  '/dashboard/sub-categories?categoryId=${category.id}',
                );
              },
              child: const Text('View Sub Categories'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Category'),
        content: Text(
            'Are you sure you want to delete "${category.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(categoriesNotifierProvider.notifier)
          .deleteCategory(category.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Category deleted successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _toggleCategoryActive(Category category, bool isActive) async {
    try {
      await ref
          .read(categoriesNotifierProvider.notifier)
          .toggleActive(category.id, isActive: isActive);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ── Sub-category CRUD ─────────────────────────────────────────────────────

  void _openCreateSubCategory(Category category) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => SubCategoryFormDialog(
        categoryId: category.id,
        categoryName: category.name,
        onSave: ({
          required categoryId,
          required name,
          required slug,
          required sortOrder,
          required isActive,
        }) async {
          await ref
              .read(subCategoriesNotifierProvider.notifier)
              .createSubCategory(
                categoryId: categoryId,
                name: name,
                slug: slug,
                sortOrder: sortOrder,
                isActive: isActive,
              );
          if (mounted) {
            setState(() => _expandedCategories.add(categoryId));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Sub Category created successfully.')),
            );
            final subs =
                ref.read(subCategoriesNotifierProvider).valueOrNull ?? [];
            final newSub = subs
                .where((s) => s.name == name && s.categoryId == category.id)
                .firstOrNull;
            if (newSub != null && mounted) {
              _showAddServiceWizard(newSub, category);
            }
          }
        },
      ),
    );
  }

  void _openEditSubCategory(SubCategory subCategory) {
    final cats = ref.read(categoriesNotifierProvider).valueOrNull ?? [];
    final cat =
        cats.where((c) => c.id == subCategory.categoryId).firstOrNull;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => SubCategoryFormDialog(
        existing: subCategory,
        categoryId: subCategory.categoryId,
        categoryName: cat?.name ?? '',
        onSave: ({
          required categoryId,
          required name,
          required slug,
          required sortOrder,
          required isActive,
        }) async {
          await ref
              .read(subCategoriesNotifierProvider.notifier)
              .updateSubCategory(
                subCategory.id,
                categoryId: categoryId,
                name: name,
                slug: slug,
                sortOrder: sortOrder,
                isActive: isActive,
              );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Sub Category updated successfully.')),
            );
          }
        },
      ),
    );
  }

  Future<void> _deleteSubCategory(SubCategory subCategory) async {
    int serviceCount;
    try {
      serviceCount = await ref
          .read(subCategoriesRepositoryProvider)
          .countServices(subCategory.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Unable to validate sub category deletion. Please try again.'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    if (serviceCount > 0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Delete Sub Category?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This sub category cannot be deleted because it still contains:',
                style:
                    TextStyle(fontSize: 14, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 12),
              _BulletRow(
                '$serviceCount Service${serviceCount == 1 ? '' : 's'}',
              ),
              const SizedBox(height: 16),
              Text(
                'You must remove or move these items before deleting this sub category.',
                style:
                    TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                context.go(
                    '/dashboard/services?subCategoryId=${subCategory.id}');
              },
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary),
              child: const Text('View Services'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Sub Category'),
        content: Text(
            'Are you sure you want to delete "${subCategory.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(subCategoriesNotifierProvider.notifier)
          .deleteSubCategory(subCategory.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Sub Category deleted successfully.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Sub category deletion failed. Please try again.'),
          ),
        );
      }
    }
  }

  void _toggleSubCategoryActive(SubCategory sub, bool isActive) async {
    try {
      await ref
          .read(subCategoriesNotifierProvider.notifier)
          .toggleActive(sub.id, isActive: isActive);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ── Service CRUD ─────────────────────────────────────────────────────────

  void _openCreateService(SubCategory subCategory, {Category? category}) {
    final cats = ref.read(categoriesNotifierProvider).valueOrNull ?? [];
    final cat =
        category ?? cats.where((c) => c.id == subCategory.categoryId).firstOrNull;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ServiceFormDialog(
        categoryId: subCategory.categoryId,
        categoryName: cat?.name ?? '',
        subCategoryId: subCategory.id,
        subCategoryName: subCategory.name,
        onSave: ({
          required categoryId,
          required subCategoryId,
          required name,
          required slug,
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
                basePrice: basePrice,
                estimatedDuration: estimatedDuration,
                imageUrl: imageUrl,
                isActive: isActive,
              );
          if (mounted) {
            setState(() {
              _expandedCategories.add(categoryId);
              _expandedSubCategories.add(subCategoryId);
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Service created successfully.')),
            );
            _showConfigureAttributesWizard(name);
          }
        },
      ),
    );
  }

  void _openEditService(Service service) {
    final cats = ref.read(categoriesNotifierProvider).valueOrNull ?? [];
    final subs = ref.read(subCategoriesNotifierProvider).valueOrNull ?? [];
    final cat =
        cats.where((c) => c.id == service.categoryId).firstOrNull;
    final sub =
        subs.where((s) => s.id == service.subCategoryId).firstOrNull;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ServiceFormDialog(
        existing: service,
        categoryId: service.categoryId,
        categoryName: cat?.name ?? '',
        subCategoryId: service.subCategoryId,
        subCategoryName: sub?.name ?? '',
        onSave: ({
          required categoryId,
          required subCategoryId,
          required name,
          required slug,
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
                basePrice: basePrice,
                estimatedDuration: estimatedDuration,
                imageUrl: imageUrl,
                isActive: isActive,
              );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Service updated successfully.')),
            );
          }
        },
      ),
    );
  }

  Future<void> _deleteService(Service service) async {
    int attrCount;
    try {
      attrCount = await ref
          .read(servicesRepositoryProvider)
          .countAttributes(service.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Unable to validate service deletion. Please try again.'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    if (attrCount > 0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Delete Service?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This service cannot be deleted because it still contains:',
                style:
                    TextStyle(fontSize: 14, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 12),
              _BulletRow(
                '$attrCount Service Attribute${attrCount == 1 ? '' : 's'}',
              ),
              const SizedBox(height: 16),
              Text(
                'You must remove these attributes before deleting this service.',
                style:
                    TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _openAttributesPanel(service);
              },
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary),
              child: const Text('View Attributes'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Service'),
        content: Text(
            'Are you sure you want to delete "${service.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(servicesNotifierProvider.notifier)
          .deleteService(service.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Service deleted successfully.')),
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

  void _toggleServiceActive(Service service, bool isActive) async {
    try {
      await ref
          .read(servicesNotifierProvider.notifier)
          .toggleActive(service.id, isActive: isActive);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ── Attributes panel ─────────────────────────────────────────────────────

  void _openAttributesPanel(Service service) {
    ref
        .read(serviceAttributesNotifierProvider.notifier)
        .loadForService(service.id);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        alignment: Alignment.centerRight,
        insetPadding:
            const EdgeInsets.only(top: 0, bottom: 0, right: 0, left: 120),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(left: Radius.circular(16)),
        ),
        child: SizedBox(
          width: 480,
          child: ServiceAttributesDrawer(service: service),
        ),
      ),
    );
  }

  // ── Wizard prompts ────────────────────────────────────────────────────────

  void _showAddSubCategoryWizard(Category category) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Category Created'),
        content: Text(
            'Would you like to add a Sub Category under "${category.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Not Now'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _openCreateSubCategory(category);
            },
            child: const Text('Add Sub Category'),
          ),
        ],
      ),
    );
  }

  void _showAddServiceWizard(SubCategory subCategory, Category category) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Sub Category Created'),
        content: Text(
            'Would you like to add a Service under "${subCategory.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Not Now'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _openCreateService(subCategory, category: category);
            },
            child: const Text('Add Service'),
          ),
        ],
      ),
    );
  }

  void _showConfigureAttributesWizard(String serviceName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Service Created'),
        content: Text(
            'Would you like to configure attributes for "$serviceName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Not Now'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              final services =
                  ref.read(servicesNotifierProvider).valueOrNull ?? [];
              final match =
                  services.where((s) => s.name == serviceName).firstOrNull;
              if (match != null && mounted) _openAttributesPanel(match);
            },
            child: const Text('Configure Attributes'),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final catsAsync = ref.watch(categoriesNotifierProvider);
    final subsAsync = ref.watch(subCategoriesNotifierProvider);
    final svcsAsync = ref.watch(servicesNotifierProvider);

    final callbacks = CatalogCallbacks(
      onEditCategory: _openEditCategory,
      onDeleteCategory: _deleteCategory,
      onToggleCategoryActive: _toggleCategoryActive,
      onAddSubCategory: _openCreateSubCategory,
      onEditSubCategory: _openEditSubCategory,
      onDeleteSubCategory: _deleteSubCategory,
      onToggleSubCategoryActive: _toggleSubCategoryActive,
      onAddService: (sub) => _openCreateService(sub),
      onEditService: _openEditService,
      onDeleteService: _deleteService,
      onToggleServiceActive: _toggleServiceActive,
      onOpenAttributes: _openAttributesPanel,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPageHeader(),
          _buildSearchBar(),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: _buildTree(catsAsync, subsAsync, svcsAsync, callbacks),
          ),
        ],
      ),
    );
  }

  Widget _buildPageHeader() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Catalog',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Manage categories, sub-categories and services',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: _openCreateCategory,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Category'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
      child: TextField(
        controller: _searchController,
        onChanged: (v) =>
            setState(() => _searchQuery = v.trim().toLowerCase()),
        decoration: InputDecoration(
          hintText: 'Search catalog...',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.accent),
          ),
        ),
      ),
    );
  }

  // ── Tree builder ──────────────────────────────────────────────────────────

  Widget _buildTree(
    AsyncValue<List<Category>> catsAsync,
    AsyncValue<List<SubCategory>> subsAsync,
    AsyncValue<List<Service>> svcsAsync,
    CatalogCallbacks callbacks,
  ) {
    if (catsAsync.isLoading || subsAsync.isLoading || svcsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (catsAsync.hasError) {
      return const Center(
        child: Text(
          'Error loading catalog.',
          style: TextStyle(color: AppColors.error),
        ),
      );
    }

    final cats = catsAsync.valueOrNull ?? [];
    final subs = subsAsync.valueOrNull ?? [];
    final svcs = svcsAsync.valueOrNull ?? [];
    final q = _searchQuery;
    final isSearching = q.isNotEmpty;

    // ── Group by parent ─────────────────────────────────────────────────────
    final subsByCategory = <String, List<SubCategory>>{};
    for (final sub in subs) {
      if (sub.categoryId.isNotEmpty) {
        subsByCategory.putIfAbsent(sub.categoryId, () => []).add(sub);
      }
    }
    final svcsBySubId = <String, List<Service>>{};
    for (final svc in svcs) {
      if (svc.subCategoryId.isNotEmpty) {
        svcsBySubId.putIfAbsent(svc.subCategoryId, () => []).add(svc);
      }
    }

    // ── Pre-filter for search ───────────────────────────────────────────────
    // Parent is responsible for passing the correct child list; no filtering
    // happens inside CategoryCard, SubCategoryTile, or ServiceTile.
    final Map<String, List<Service>> displaySvcsBySubId;
    final Map<String, List<SubCategory>> displaySubsByCatId;

    if (!isSearching) {
      displaySvcsBySubId = svcsBySubId;
      displaySubsByCatId = subsByCategory;
    } else {
      displaySvcsBySubId = {
        for (final e in svcsBySubId.entries)
          if (e.value.any((s) => s.name.toLowerCase().contains(q)))
            e.key: e.value
                .where((s) => s.name.toLowerCase().contains(q))
                .toList(),
      };

      displaySubsByCatId = {};
      for (final cat in cats) {
        final catSubs = subsByCategory[cat.id] ?? [];
        final visibleSubs = catSubs.where((sub) {
          if (sub.name.toLowerCase().contains(q)) return true;
          return (displaySvcsBySubId[sub.id] ?? []).isNotEmpty;
        }).toList();
        if (visibleSubs.isNotEmpty) displaySubsByCatId[cat.id] = visibleSubs;
      }
    }

    final visibleCats = cats.where((cat) {
      if (!isSearching) return true;
      if (cat.name.toLowerCase().contains(q)) return true;
      return (displaySubsByCatId[cat.id] ?? []).isNotEmpty;
    }).toList();

    // ── Empty state ─────────────────────────────────────────────────────────
    if (visibleCats.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.layers_outlined,
                size: 56, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(
              isSearching
                  ? 'No results for "$_searchQuery"'
                  : 'No categories yet. Add one to get started.',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            if (!isSearching) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _openCreateCategory,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Category'),
              ),
            ],
          ],
        ),
      );
    }

    // ── List ────────────────────────────────────────────────────────────────
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        for (final cat in visibleCats)
          CategoryCard(
            key: ValueKey(cat.id),
            category: cat,
            subCategories: displaySubsByCatId[cat.id] ?? [],
            servicesBySubId: displaySvcsBySubId,
            isExpanded:
                isSearching || _expandedCategories.contains(cat.id),
            onToggle: () => _toggleCategory(cat.id),
            isSubExpanded: (subId) =>
                isSearching || _expandedSubCategories.contains(subId),
            onToggleSub: _toggleSubCategory,
            callbacks: callbacks,
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _openCreateCategory,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add Category'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.accent,
            side: BorderSide(color: AppColors.accent.withValues(alpha: 0.5)),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _BulletRow extends StatelessWidget {
  const _BulletRow(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.textSecondary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}
