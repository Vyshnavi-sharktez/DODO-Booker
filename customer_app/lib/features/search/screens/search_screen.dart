import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/icon_registry.dart';
import '../../../models/category_model.dart';
import '../../../models/service_model.dart';
import '../../service/utils/service_detail_launcher.dart';

class SearchScreen extends StatefulWidget {
  final String initialQuery;

  const SearchScreen({super.key, this.initialQuery = ''});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  bool _loading = false;
  List<CategoryModel> _catResults = [];
  List<ServiceModel> _svcResults = [];
  String _lastQuery = '';

  static bool get _ready =>
      SupabaseConfig.supabaseUrl.isNotEmpty &&
      SupabaseConfig.supabaseAnonKey.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Set initial query BEFORE adding listener so _onChanged doesn't fire
    // for the pre-filled value — we trigger the search manually below.
    if (widget.initialQuery.isNotEmpty) {
      _controller.text = widget.initialQuery;
      _lastQuery = widget.initialQuery;
    }
    _controller.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      if (widget.initialQuery.isNotEmpty) {
        setState(() => _loading = true);
        _search(widget.initialQuery);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged() {
    final query = _controller.text.trim();
    if (query == _lastQuery) return;
    _lastQuery = query;

    _debounce?.cancel();
    if (query.length < 2) {
      setState(() {
        _catResults = [];
        _svcResults = [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce =
        Timer(const Duration(milliseconds: 300), () => _search(query));
  }

  Future<void> _search(String query) async {
    if (!mounted) return;
    if (!_ready) {
      setState(() => _loading = false);
      return;
    }
    try {
      final db = Supabase.instance.client;
      final results = await Future.wait([
        db
            .from('categories')
            .select()
            .eq('is_active', true)
            .ilike('name', '%$query%')
            .limit(5),
        db
            .from('services')
            .select('*, sub_categories(name, categories(name))')
            .eq('is_active', true)
            .ilike('name', '%$query%')
            .limit(10),
      ]);
      if (!mounted) return;
      setState(() {
        _catResults = (results[0] as List)
            .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
            .toList();
        _svcResults = (results[1] as List)
            .map((e) => ServiceModel.fromJson(e as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final query = _controller.text.trim();
    final hasQuery = query.length >= 2;
    final hasResults = _catResults.isNotEmpty || _svcResults.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          textInputAction: TextInputAction.search,
          style: tt.bodyMedium,
          decoration: InputDecoration(
            hintText: 'Search for services...',
            hintStyle:
                tt.bodyMedium?.copyWith(color: AppColors.textHint),
            border: InputBorder.none,
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (_, val, child) => val.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: _controller.clear,
                    ),
            ),
          ),
        ),
      ),
      body: _buildBody(hasQuery, hasResults, tt),
    );
  }

  Widget _buildBody(bool hasQuery, bool hasResults, TextTheme tt) {
    if (!hasQuery) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_rounded, size: 56, color: AppColors.textHint),
            SizedBox(height: 12),
            Text(
              'Search for cleaning, plumbing, AC service...',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (!hasResults) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded,
                size: 56, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(
              'No results for "${_controller.text.trim()}"',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_catResults.isNotEmpty) ...[
          Text(
            'Categories',
            style: tt.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ..._catResults.map(
            (cat) => _CategoryResult(
              category: cat,
              onTap: () =>
                  context.push('/subcategory/${cat.id}', extra: cat),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_svcResults.isNotEmpty) ...[
          Text(
            'Services',
            style: tt.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ..._svcResults.map(
            (svc) => _ServiceResult(
              service: svc,
              onTap: () => openServiceDetail(context, svc),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Category result row ───────────────────────────────────────────────────────

class _CategoryResult extends StatelessWidget {
  final CategoryModel category;
  final VoidCallback onTap;

  const _CategoryResult({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          IconRegistry.resolve(category.iconKey, category.name),
          size: 20,
          color: AppColors.primary,
        ),
      ),
      title: Text(category.name,
          style: const TextStyle(
              fontWeight: FontWeight.w500, fontSize: 14)),
      subtitle: category.description != null &&
              category.description!.isNotEmpty
          ? Text(category.description!,
              maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: const Icon(Icons.chevron_right_rounded,
          size: 18, color: AppColors.textHint),
      onTap: onTap,
    );
  }
}

// ── Service result row ────────────────────────────────────────────────────────

class _ServiceResult extends StatelessWidget {
  final ServiceModel service;
  final VoidCallback onTap;

  const _ServiceResult({required this.service, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          IconRegistry.resolve(null, service.categoryName),
          size: 20,
          color: AppColors.textSecondary,
        ),
      ),
      title: Text(service.name,
          style: const TextStyle(
              fontWeight: FontWeight.w500, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      subtitle: service.categoryName != null
          ? Text(service.categoryName!,
              style: const TextStyle(fontSize: 12))
          : null,
      trailing: Text(
        '₹${service.startingPrice.toInt()}',
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
          fontSize: 13,
        ),
      ),
      onTap: onTap,
    );
  }
}
