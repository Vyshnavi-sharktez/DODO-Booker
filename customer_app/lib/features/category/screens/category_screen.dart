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

  static int _cols(double width) {
    if (width < 480) return 2;
    if (width < 768) return 3;
    if (width < 1100) return 4;
    return 5;
  }

  static double _hPad(double width) {
    if (width < 600) return 16;
    if (width < 900) return 24;
    return 32;
  }

  Widget _buildGrid(List<CategoryModel> categories, int cols, double hPad) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 48),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final cat = categories[index];
            return CategoryCard(
              category: cat,
              colorIndex: index,
              onTap: () => context.push('/subcategory/${cat.id}', extra: cat),
            );
          },
          childCount: categories.length,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          childAspectRatio: 0.75,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
        ),
      ),
    );
  }

  Widget _buildContent(
    AsyncValue<List<CategoryModel>> async,
    int cols,
    double hPad,
  ) {
    return async.when(
      loading: () => _buildSkeleton(cols, hPad),
      error: (e, _) => SliverFillRemaining(
        child: _ErrorState(onRetry: _refresh),
      ),
      data: (all) {
        final list = _filtered(all);
        if (list.isEmpty) {
          return SliverFillRemaining(
            child: _EmptyState(
              isSearch: _query.isNotEmpty,
              onClear: _searchController.clear,
            ),
          );
        }
        return _buildGrid(list, cols, hPad);
      },
    );
  }

  Widget _buildSkeleton(int cols, double hPad) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 48),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, index) => Container(
            decoration: BoxDecoration(
              color: AppColors.shimmerBase,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          childCount: 10,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          childAspectRatio: 0.75,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(categoriesProvider);
    final width = MediaQuery.of(context).size.width;
    final cols = _cols(width);
    final hPad = _hPad(width);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Services'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.transparent,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _refresh,
            child: ScrollConfiguration(
              behavior:
                  ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // ── Search bar ─────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding:
                          EdgeInsets.fromLTRB(hPad, 16, hPad, 8),
                      child: _SearchBar(controller: _searchController),
                    ),
                  ),

                  // ── Category grid / states ─────────────────────────────
                  _buildContent(async, cols, hPad),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Inline search bar ─────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  const _SearchBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search services...',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, child) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(Icons.clear_rounded, size: 18),
              onPressed: controller.clear,
            );
          },
        ),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.primary, width: 1.4),
        ),
      ),
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
              'Could not load services',
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
              isSearch ? 'No results found' : 'No services yet',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isSearch
                  ? 'Try a different search term'
                  : 'Services will appear here soon',
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
