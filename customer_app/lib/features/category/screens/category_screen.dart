import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/category_model.dart';
import '../services/category_providers.dart';
import '../widgets/category_card.dart';

class CategoryScreen extends ConsumerStatefulWidget {
  const CategoryScreen({super.key});

  @override
  ConsumerState<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends ConsumerState<CategoryScreen> {
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

  List<CategoryModel> _filtered(List<CategoryModel> all) {
    if (_query.isEmpty) return all;
    return all.where((c) => c.name.toLowerCase().contains(_query)).toList();
  }

  Future<void> _refresh() async {
    ref.invalidate(categoriesProvider);
    try {
      await ref.read(categoriesProvider.future);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(categoriesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Categories'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(68),
          child: _SearchBar(controller: _searchController),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refresh,
        child: async.when(
          loading: () => const _CategorySkeleton(),
          error: (e, _) => _ErrorState(onRetry: _refresh),
          data: (all) {
            final list = _filtered(all);
            if (list.isEmpty) {
              return _EmptyState(
                isSearch: _query.isNotEmpty,
                onClear: () => _searchController.clear(),
              );
            }
            return _CategoryGrid(categories: list);
          },
        ),
      ),
    );
  }
}

// ── Search bar (inside AppBar bottom) ─────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  const _SearchBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search categories...',
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

// ── Responsive grid ───────────────────────────────────────────────────────────

class _CategoryGrid extends StatelessWidget {
  final List<CategoryModel> categories;
  const _CategoryGrid({required this.categories});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final int cols;
        final double ratio;
        if (w < 600) {
          cols = 2;
          ratio = 0.95;
        } else if (w < 900) {
          cols = 3;
          ratio = 1.05;
        } else {
          cols = 4;
          ratio = 1.1;
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
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final cat = categories[index];
            return CategoryCard(
              category: cat,
              colorIndex: index,
              onTap: () => context.push(
                '/subcategory/${cat.id}',
                extra: cat,
              ),
            );
          },
        );
      },
    );
  }
}

// ── Loading skeleton ───────────────────────────────────────────────────────────

class _CategorySkeleton extends StatelessWidget {
  const _CategorySkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth < 600 ? 2 : (constraints.maxWidth < 900 ? 3 : 4);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: 0.95,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: 8,
          itemBuilder: (_, _) => Container(
            decoration: BoxDecoration(
              color: AppColors.shimmerBase,
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        );
      },
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

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
              'Could not load categories',
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

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool isSearch;
  final VoidCallback onClear;

  const _EmptyState({required this.isSearch, required this.onClear});

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
              isSearch ? Icons.search_off_rounded : Icons.grid_off_rounded,
              size: 64,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 16),
            Text(
              isSearch ? 'No results found' : 'No categories yet',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isSearch
                  ? 'Try a different search term'
                  : 'Categories will appear here soon',
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
