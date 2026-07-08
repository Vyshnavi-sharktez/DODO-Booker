import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/icon_registry.dart';
import '../../../features/catalog/models/catalog_node_model.dart';
import '../../../features/catalog/utils/catalog_launcher.dart';

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
  List<CatalogNodeModel> _results = [];
  String _lastQuery = '';

  static bool get _ready =>
      SupabaseConfig.supabaseUrl.isNotEmpty &&
      SupabaseConfig.supabaseAnonKey.isNotEmpty;

  @override
  void initState() {
    super.initState();
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
        _results = [];
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
      final data = await db
          .from('catalog_nodes_view')
          .select()
          .eq('is_active', true)
          .ilike('name', '%$query%')
          .order('sort_order', ascending: true)
          .limit(25);
      if (!mounted) return;
      setState(() {
        _results = (data as List)
            .map((e) => CatalogNodeModel.fromMap(e as Map<String, dynamic>))
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
    final hasResults = _results.isNotEmpty;

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
        Text(
          'Results',
          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ..._results.map(
          (node) => _NodeResult(
            node: node,
            onTap: () => openCatalogNode(context, node),
          ),
        ),
      ],
    );
  }
}

// ── Catalog node result row ───────────────────────────────────────────────────

class _NodeResult extends StatelessWidget {
  final CatalogNodeModel node;
  final VoidCallback onTap;

  const _NodeResult({required this.node, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: node.isBookable
              ? AppColors.surfaceVariant
              : AppColors.primaryLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          node.isBookable
              ? IconRegistry.resolve(node.iconKey, node.name)
              : Icons.folder_rounded,
          size: 20,
          color: node.isBookable
              ? AppColors.textSecondary
              : AppColors.primary,
        ),
      ),
      title: Text(
        node.name,
        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: node.parentName != null
          ? Text(
              node.parentName!,
              style: const TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: node.isLeafBookable && node.basePrice != null
          ? Text(
              '₹${node.basePrice!.toInt()}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                fontSize: 13,
              ),
            )
          : const Icon(Icons.chevron_right_rounded,
              size: 18, color: AppColors.textHint),
      onTap: onTap,
    );
  }
}
