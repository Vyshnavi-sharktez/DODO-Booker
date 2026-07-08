import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../models/catalog_node_model.dart';
import '../providers/catalog_providers.dart';
import '../utils/catalog_launcher.dart';
import '../widgets/catalog_node_card.dart';

/// Full-screen browse view showing all root catalog nodes in a searchable grid.
/// Replaces the legacy CategoryScreen in the navigation stack.
class CatalogBrowseScreen extends ConsumerStatefulWidget {
  const CatalogBrowseScreen({super.key});

  @override
  ConsumerState<CatalogBrowseScreen> createState() =>
      _CatalogBrowseScreenState();
}

class _CatalogBrowseScreenState extends ConsumerState<CatalogBrowseScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(
      () => setState(
          () => _query = _searchController.text.trim().toLowerCase()),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CatalogNodeModel> _filtered(List<CatalogNodeModel> all) {
    if (_query.isEmpty) return all;
    return all
        .where((n) => n.name.toLowerCase().contains(_query))
        .toList();
  }

  Future<void> _refresh() async {
    ref.invalidate(rootCatalogNodesProvider);
    try {
      await ref.read(rootCatalogNodesProvider.future);
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

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(rootCatalogNodesProvider);
    final width = MediaQuery.of(context).size.width;
    final cols = _cols(width);
    final hPad = _hPad(width);

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Services'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
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
              behavior: ScrollConfiguration.of(context)
                  .copyWith(scrollbars: false),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // ── Hero banner + floating title card ────────────────────
                  SliverToBoxAdapter(
                    child: _BrowseHeroHeader(
                      nodeCount: async.valueOrNull?.length,
                    ),
                  ),
                  // Space for the card that extends 48 px below the Stack
                  // plus a 16 px gap before the search bar = 64 px.
                  const SliverToBoxAdapter(child: SizedBox(height: 64)),

                  // ── Search bar ───────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding:
                          EdgeInsets.fromLTRB(hPad, 0, hPad, 8),
                      child: _SearchBar(controller: _searchController),
                    ),
                  ),

                  // ── Content ──────────────────────────────────────────────
                  async.when(
                    loading: () => _buildSkeleton(cols, hPad),
                    error: (_, _) => SliverFillRemaining(
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
                      return SliverPadding(
                        padding:
                            EdgeInsets.fromLTRB(hPad, 8, hPad, 48),
                        sliver: SliverGrid(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) => CatalogNodeCard(
                              node: list[i],
                              colorIndex: i,
                              onTap: () =>
                                  openCatalogNode(ctx, list[i]),
                            ),
                            childCount: list.length,
                          ),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            childAspectRatio: 0.75,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkeleton(int cols, double hPad) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 48),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (_, _) => Container(
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
}

// ── Browse hero banner + floating info card ───────────────────────────────────

class _BrowseHeroHeader extends StatelessWidget {
  const _BrowseHeroHeader({this.nodeCount});
  final int? nodeCount;

  @override
  Widget build(BuildContext context) {
    final topInset =
        MediaQuery.of(context).padding.top + kToolbarHeight;
    final heroHeight = topInset + 140.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Gradient background fills behind the transparent AppBar
        Container(
          height: heroHeight,
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF111111), Color(0xFF2C2C2C)],
            ),
          ),
          child: Stack(
            children: [
              // Subtle decorative icon
              Positioned(
                right: -24,
                bottom: -8,
                child: Icon(
                  Icons.home_repair_service_rounded,
                  size: 160,
                  color: Colors.white.withAlpha(12),
                ),
              ),
            ],
          ),
        ),

        // Floating info card — bottom edge 48 px below the Stack
        Positioned(
          bottom: -48,
          left: 16,
          right: 16,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(22),
                  blurRadius: 20,
                  spreadRadius: 0,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Browse Services',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Professional services at your doorstep',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                if (nodeCount != null && nodeCount! > 0) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '$nodeCount',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            height: 1.0,
                          ),
                        ),
                        const Text(
                          'categories',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Inline search bar ─────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller});
  final TextEditingController controller;

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
          builder: (_, value, child) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(Icons.clear_rounded, size: 18),
              onPressed: controller.clear,
            );
          },
        ),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppColors.border, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppColors.border, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppColors.primary, width: 1.4),
        ),
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded,
                size: 64, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text('Could not load services',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Check your connection and try again',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            SizedBox(
              width: 160,
              child: ElevatedButton(
                  onPressed: onRetry, child: const Text('Retry')),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isSearch, required this.onClear});
  final bool isSearch;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSearch
                  ? Icons.search_off_rounded
                  : Icons.grid_off_rounded,
              size: 64,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 16),
            Text(
              isSearch ? 'No results found' : 'No services yet',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isSearch
                  ? 'Try a different search term'
                  : 'Services will appear here soon',
              style: Theme.of(context).textTheme.bodyMedium,
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
