import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/category_model.dart';
import '../../../models/service_model.dart';
import '../services/service_providers.dart';
import '../widgets/service_card.dart';
import '../utils/service_detail_launcher.dart';

/// Services listing screen scoped to an entire category — shows all services
/// across every subcategory that belongs to [category].
/// Reached from the Popular Categories row on the Home screen.
class CategoryServicesScreen extends ConsumerStatefulWidget {
  final CategoryModel category;

  const CategoryServicesScreen({super.key, required this.category});

  @override
  ConsumerState<CategoryServicesScreen> createState() =>
      _CategoryServicesScreenState();
}

class _CategoryServicesScreenState
    extends ConsumerState<CategoryServicesScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      if (_search.text != _query) setState(() => _query = _search.text);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ServiceModel> _filtered(List<ServiceModel> all) {
    if (_query.trim().isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((s) => s.name.toLowerCase().contains(q)).toList();
  }

  Future<void> _refresh() async {
    ref.invalidate(servicesByCategoryProvider(widget.category.id));
    try {
      await ref.read(servicesByCategoryProvider(widget.category.id).future);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final servicesAsync =
        ref.watch(servicesByCategoryProvider(widget.category.id));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.category.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Filter',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Filters coming soon')),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Sort',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Sorting coming soon')),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search in ${widget.category.name}…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: servicesAsync.when(
              loading: () => const _Loading(),
              error: (error, stack) => _Error(onRetry: _refresh),
              data: (services) {
                final filtered = _filtered(services);
                if (filtered.isEmpty) {
                  return _Empty(
                    hasQuery: _query.isNotEmpty,
                    onClear: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                  );
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => ServiceCard(
                      service: filtered[i],
                      onTap: () => openServiceDetail(context, filtered[i]),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── State widgets ─────────────────────────────────────────────────────────────

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 5,
      itemBuilder: (_, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Container(
          height: 100,
          decoration: BoxDecoration(
            color: AppColors.shimmerBase,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  final VoidCallback onRetry;

  const _Error({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 48,
            color: AppColors.error,
          ),
          const SizedBox(height: 12),
          Text(
            'Failed to load services',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final bool hasQuery;
  final VoidCallback onClear;

  const _Empty({required this.hasQuery, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.search_off_rounded,
            size: 56,
            color: AppColors.textHint,
          ),
          const SizedBox(height: 12),
          Text(
            hasQuery
                ? 'No services match your search'
                : 'No services available',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (hasQuery) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onClear,
              child: const Text('Clear Search'),
            ),
          ],
        ],
      ),
    );
  }
}
