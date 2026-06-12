import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/category_model.dart';
import '../../../models/subcategory_model.dart';
import '../services/category_providers.dart';
import '../widgets/subcategory_card.dart';

class SubcategoryScreen extends ConsumerStatefulWidget {
  final CategoryModel category;

  const SubcategoryScreen({super.key, required this.category});

  @override
  ConsumerState<SubcategoryScreen> createState() => _SubcategoryScreenState();
}

class _SubcategoryScreenState extends ConsumerState<SubcategoryScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(
      () => setState(() => _query = _searchController.text.trim().toLowerCase()),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SubcategoryModel> _filtered(List<SubcategoryModel> all) {
    if (_query.isEmpty) return all;
    return all
        .where(
          (s) =>
              s.name.toLowerCase().contains(_query) ||
              (s.description?.toLowerCase().contains(_query) ?? false),
        )
        .toList();
  }

  Future<void> _refresh() async {
    ref.invalidate(subcategoriesProvider(widget.category.id));
    try {
      await ref.read(subcategoriesProvider(widget.category.id).future);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(subcategoriesProvider(widget.category.id));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.category.name),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(68),
          child: _SearchBar(
            controller: _searchController,
            hint: 'Search ${widget.category.name.toLowerCase()}...',
          ),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refresh,
        child: async.when(
          loading: () => const _SubcategorySkeleton(),
          error: (e, _) => _ErrorState(onRetry: _refresh),
          data: (all) {
            final list = _filtered(all);
            if (list.isEmpty) {
              return _EmptyState(
                categoryName: widget.category.name,
                isSearch: _query.isNotEmpty,
                onClear: () => _searchController.clear(),
              );
            }
            return _SubcategoryGrid(
              subcategories: list,
              categoryColorIndex: _colorIndex(widget.category.id),
            );
          },
        ),
      ),
    );
  }

  int _colorIndex(String id) {
    final n = int.tryParse(id);
    return n != null ? (n - 1) : 0;
  }
}

// ── Search bar ─────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;

  const _SearchBar({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.clear_rounded, size: 18),
                onPressed: controller.clear,
              );
            },
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }
}

// ── Responsive grid ────────────────────────────────────────────────────────────

class _SubcategoryGrid extends StatelessWidget {
  final List<SubcategoryModel> subcategories;
  final int categoryColorIndex;

  const _SubcategoryGrid({
    required this.subcategories,
    required this.categoryColorIndex,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final int cols;
        final double ratio;
        if (w < 600) {
          cols = 2;
          ratio = 0.88;
        } else if (w < 900) {
          cols = 3;
          ratio = 0.95;
        } else {
          cols = 4;
          ratio = 1.0;
        }

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          physics: const AlwaysScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: ratio,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: subcategories.length,
          itemBuilder: (context, index) {
            final sub = subcategories[index];
            return SubcategoryCard(
              subcategory: sub,
              colorIndex: categoryColorIndex,
              onTap: () => context.push('/services/${sub.id}', extra: sub),
            );
          },
        );
      },
    );
  }
}

// ── Loading skeleton ───────────────────────────────────────────────────────────

class _SubcategorySkeleton extends StatelessWidget {
  const _SubcategorySkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth < 600 ? 2 : (constraints.maxWidth < 900 ? 3 : 4);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: 0.88,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: 6,
          itemBuilder: (_, _) => Container(
            decoration: BoxDecoration(
              color: AppColors.shimmerBase,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );
      },
    );
  }
}

// ── Error state ────────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 64, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text(
              'Could not load subcategories',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Check your connection and try again',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 160,
              child: ElevatedButton(
                onPressed: onRetry,
                child: const Text('Retry'),
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
  final String categoryName;
  final bool isSearch;
  final VoidCallback onClear;

  const _EmptyState({
    required this.categoryName,
    required this.isSearch,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSearch ? Icons.search_off_rounded : Icons.category_outlined,
              size: 64,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 16),
            Text(
              isSearch
                  ? 'No results found'
                  : 'No subcategories yet',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isSearch
                  ? 'Try a different search term'
                  : '$categoryName subcategories will appear here',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (isSearch) ...[
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.clear_rounded, size: 16),
                label: const Text('Clear search'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
