import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/widgets/admin_search_bar.dart';
import '../../application/providers/catalog_node_providers.dart';
import '../../domain/models/catalog_node.dart';
import '../../../service_scheduling/presentation/widgets/service_scheduling_dialog.dart';
import '../widgets/catalog_node_attributes_drawer.dart';
import '../widgets/catalog_node_form_dialog.dart';
import '../widgets/catalog_node_move_dialog.dart';
import '../widgets/catalog_node_tile.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CatalogV2Page
//
// Responsibilities
//   • Load ALL catalog nodes in one query and build an in-memory tree
//   • Manage expand/collapse state (Set<String> of expanded node IDs)
//   • Own all CRUD + toggle methods and pass them as NodeCallbacks
//   • Pre-compute the visible set during search (matching nodes + ancestors)
//
// Widget tree
//   CatalogV2Page → ListView → CatalogNodeTile (recursive, unlimited depth)
// ═══════════════════════════════════════════════════════════════════════════════

class CatalogV2Page extends ConsumerStatefulWidget {
  const CatalogV2Page({super.key});

  @override
  ConsumerState<CatalogV2Page> createState() => _CatalogV2PageState();
}

class _CatalogV2PageState extends ConsumerState<CatalogV2Page> {
  String _searchQuery = '';
  final Set<String> _expandedIds = {};

  // ── Expand / collapse ────────────────────────────────────────────────────────

  void _toggleExpand(String nodeId) {
    setState(() {
      if (_expandedIds.contains(nodeId)) {
        _expandedIds.remove(nodeId);
      } else {
        _expandedIds.add(nodeId);
      }
    });
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────────

  void _openCreate({CatalogNode? parent}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CatalogNodeFormDialog(
        parentNode: parent,
        onSave: ({
          required name,
          required slug,
          description,
          imageUrl,
          iconKey,
          required sortOrder,
          required isActive,
          required isBookable,
          basePrice,
          estimatedDuration,
          minimumOrderAmount,
        }) async {
          await ref.read(catalogNodeNotifierProvider.notifier).createNode(
                parentId: parent?.id,
                name: name,
                slug: slug,
                description: description,
                imageUrl: imageUrl,
                iconKey: iconKey,
                sortOrder: sortOrder,
                isActive: isActive,
                isBookable: isBookable,
                basePrice: basePrice,
                estimatedDuration: estimatedDuration,
                minimumOrderAmount: minimumOrderAmount,
              );
          if (mounted && parent != null) {
            setState(() => _expandedIds.add(parent.id));
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Node created successfully.')),
            );
          }
        },
      ),
    );
  }

  void _openEdit(CatalogNode node, bool hasChildren) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CatalogNodeFormDialog(
        existing: node,
        hasChildren: hasChildren,
        onSave: ({
          required name,
          required slug,
          description,
          imageUrl,
          iconKey,
          required sortOrder,
          required isActive,
          required isBookable,
          basePrice,
          estimatedDuration,
          minimumOrderAmount,
        }) async {
          await ref.read(catalogNodeNotifierProvider.notifier).updateNode(
                node.id,
                parentId: node.parentId,
                name: name,
                slug: slug,
                description: description,
                imageUrl: imageUrl,
                iconKey: iconKey,
                sortOrder: sortOrder,
                isActive: isActive,
                isBookable: isBookable,
                basePrice: basePrice,
                estimatedDuration: estimatedDuration,
                minimumOrderAmount: minimumOrderAmount,
              );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Node updated successfully.')),
            );
          }
        },
      ),
    );
  }

  Future<void> _deleteNode(CatalogNode node) async {
    // Check for children first so we can show a descriptive error.
    int childCount;
    try {
      childCount = await ref
          .read(catalogNodeRepositoryProvider)
          .countChildren(node.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Unable to validate deletion. Please try again.')),
        );
      }
      return;
    }
    if (!mounted) return;

    if (childCount > 0) {
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
              Text('Cannot Delete Node'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('"${node.name}" has $childCount '
                  'child node${childCount == 1 ? "" : "s"}. '
                  'Remove or move them first.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
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
        title: const Text('Delete Node'),
        content: Text(
            'Delete "${node.name}"? This cannot be undone.'),
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
          .read(catalogNodeNotifierProvider.notifier)
          .deleteNode(node.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Node deleted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Delete failed: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _toggleActive(CatalogNode node, bool isActive) async {
    try {
      await ref
          .read(catalogNodeNotifierProvider.notifier)
          .toggleActive(node.id, isActive: isActive);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _toggleBookable(CatalogNode node, bool isBookable) async {
    try {
      await ref
          .read(catalogNodeNotifierProvider.notifier)
          .toggleBookable(node.id, isBookable: isBookable);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _moveNode(CatalogNode node) {
    // Read current node list from the notifier — fresh at the moment of the tap.
    final allNodes =
        ref.read(catalogNodeNotifierProvider).valueOrNull ?? [];
    showDialog(
      context: context,
      builder: (_) => CatalogNodeMoveDialog(
        node: node,
        allNodes: allNodes,
        onMove: (newParentId) async {
          await ref
              .read(catalogNodeNotifierProvider.notifier)
              .moveNode(node.id, newParentId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Node moved successfully.')),
            );
          }
        },
      ),
    );
  }

  void _openScheduling(CatalogNode node) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ServiceSchedulingDialog(
        serviceId: node.id,
        serviceName: node.name,
      ),
    );
  }

  void _openAttributes(CatalogNode node) {
    ref
        .read(catalogNodeAttributesNotifierProvider.notifier)
        .loadForNode(node.id);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        alignment: Alignment.centerRight,
        insetPadding:
            const EdgeInsets.only(top: 0, bottom: 0, right: 0, left: 120),
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.horizontal(left: Radius.circular(16)),
        ),
        child: SizedBox(
          width: 480,
          child: CatalogNodeAttributesDrawer(node: node),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final nodesAsync = ref.watch(catalogNodeNotifierProvider);

    final callbacks = NodeCallbacks(
      onAddChild: (parent) => _openCreate(parent: parent),
      onEdit: (node, hasChildren) => _openEdit(node, hasChildren),
      onMove: _moveNode,
      onDelete: _deleteNode,
      onToggleActive: _toggleActive,
      onToggleBookable: _toggleBookable,
      onOpenAttributes: _openAttributes,
      onOpenScheduling: _openScheduling,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          _buildSearchBar(),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: _buildTree(nodesAsync, callbacks),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
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
                  'Dynamic catalog tree — unlimited levels, admin-controlled',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: () => _openCreate(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Root Node'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
      child: AdminSearchBar(
        hintText: 'Search catalog...',
        width: double.infinity,
        onChanged: (q) => setState(() => _searchQuery = q.toLowerCase()),
      ),
    );
  }

  // ── Tree builder ───────────────────────────────────────────────────────────────

  Widget _buildTree(
    AsyncValue<List<CatalogNode>> nodesAsync,
    NodeCallbacks callbacks,
  ) {
    if (nodesAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (nodesAsync.hasError) {
      return const Center(
        child: Text('Error loading catalog.',
            style: TextStyle(color: AppColors.error)),
      );
    }

    final allNodes = nodesAsync.valueOrNull ?? [];

    // ── Build parent → children map ──────────────────────────────────────────
    final byParent = <String?, List<CatalogNode>>{};
    for (final n in allNodes) {
      byParent.putIfAbsent(n.parentId, () => []).add(n);
    }
    // Sort each group by sort_order then name (they arrive sorted from DB,
    // but rebuild here ensures stability after optimistic updates).
    byParent.forEach((_, list) {
      list.sort((a, b) {
        final so = a.sortOrder.compareTo(b.sortOrder);
        return so != 0 ? so : a.name.compareTo(b.name);
      });
    });

    final roots = byParent[null] ?? [];

    // ── Search ───────────────────────────────────────────────────────────────
    final q = _searchQuery;
    final isSearching = q.isNotEmpty;

    // IDs of nodes whose name matches.
    Set<String> matchingIds = {};
    // IDs of ancestors of matching nodes (shown for context).
    Set<String> ancestorIds = {};
    // IDs that should be auto-expanded during search.
    Set<String> autoExpandIds = {};

    if (isSearching) {
      // Build a quick id→node lookup.
      final byId = {for (final n in allNodes) n.id: n};

      for (final n in allNodes) {
        if (n.name.toLowerCase().contains(q)) {
          matchingIds.add(n.id);
          // Walk up to collect all ancestors.
          String? pid = n.parentId;
          while (pid != null) {
            ancestorIds.add(pid);
            autoExpandIds.add(pid);
            pid = byId[pid]?.parentId;
          }
        }
      }
    }

    final visibleIds = {...matchingIds, ...ancestorIds};

    // Build the active expand set for this render pass.
    final effectiveExpandedIds = isSearching
        ? {..._expandedIds, ...autoExpandIds}
        : _expandedIds;

    // Filter root list for search.
    final visibleRoots = isSearching
        ? roots.where((n) => visibleIds.contains(n.id)).toList()
        : roots;

    // ── Empty state ───────────────────────────────────────────────────────────
    if (visibleRoots.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_tree_outlined,
                size: 56, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(
              isSearching
                  ? 'No results for "$_searchQuery"'
                  : 'No catalog nodes yet. Add one to get started.',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            if (!isSearching) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _openCreate(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Root Node'),
              ),
            ],
          ],
        ),
      );
    }

    // ── Build filtered byParent for search ────────────────────────────────────
    final displayByParent = isSearching
        ? <String?, List<CatalogNode>>{
            for (final entry in byParent.entries)
              if (entry.key == null || visibleIds.contains(entry.key))
                entry.key: entry.value
                    .where((n) => visibleIds.contains(n.id))
                    .toList(),
          }
        : byParent;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        for (final root in visibleRoots)
          CatalogNodeTile(
            key: ValueKey(root.id),
            node: root,
            children: displayByParent[root.id] ?? [],
            allByParent: displayByParent,
            depth: 0,
            expandedIds: effectiveExpandedIds,
            onToggleExpand: _toggleExpand,
            callbacks: callbacks,
            searchQuery: _searchQuery,
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _openCreate(),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add Root Node'),
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
