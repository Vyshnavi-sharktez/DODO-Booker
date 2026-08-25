import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/widgets/admin_search_bar.dart';
import '../../application/providers/catalog_node_providers.dart';
import '../../domain/models/catalog_node.dart';
import '../../../service_scheduling/presentation/widgets/service_scheduling_dialog.dart';
import '../../../catalog_configs/presentation/widgets/catalog_node_config_dialog.dart';
import '../../../amc_plans/presentation/widgets/node_amc_plans_dialog.dart';
import '../../../service_faqs/presentation/widgets/node_faqs_dialog.dart';
import '../../../service_showcase/presentation/widgets/service_showcase_dialog.dart';
import '../../../service_availability_areas/application/providers/service_availability_areas_providers.dart';
import '../widgets/catalog_node_availability_dialog.dart';
import '../widgets/catalog_node_form_dialog.dart';
import '../widgets/catalog_node_parents_dialog.dart';
import '../widgets/catalog_node_tile.dart';
import '../../../bulk_upload/data/modules/catalog_bulk_module.dart';
import '../../../bulk_upload/presentation/bulk_upload_dialog.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CatalogV2Page
//
// Responsibilities
//   • Load ALL catalog items in one query and build an in-memory tree
//   • Manage expand/collapse state (Set<String> of expanded node IDs)
//   • Own all CRUD + toggle methods and pass them as NodeCallbacks
//   • Pre-compute the visible set during search (matching nodes + ancestors)
//
// Multi-parent support
//   • An item with parentIds = ['a', 'b'] appears in both branches of the tree
//   • byParent map is built from parentIds (not from a single parent_id)
//   • Tiles get a parentIdContext so "Remove from this category" knows the context
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

  // ── Create ────────────────────────────────────────────────────────────────────

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
              const SnackBar(content: Text('Item created successfully.')),
            );
          }
        },
      ),
    );
  }

  // ── Edit ──────────────────────────────────────────────────────────────────────

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
              const SnackBar(content: Text('Item updated successfully.')),
            );
          }
        },
      ),
    );
  }

  // ── Delete ────────────────────────────────────────────────────────────────────

  Future<void> _deleteNode(CatalogNode node) async {
    int childCount = 0;
    try {
      childCount = await ref
          .read(catalogNodeRepositoryProvider)
          .countChildren(node.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Unable to validate deletion. Please try again.')),
        );
      }
      return;
    }
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Catalog Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Delete "${node.name}"? This cannot be undone.'),
            if (childCount > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFE082)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 16, color: Color(0xFFF9A825)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$childCount item${childCount == 1 ? '' : 's'} '
                        'listed under "${node.name}" will be moved to '
                        'top level or kept under their other categories.',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF795548)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.error),
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
          const SnackBar(content: Text('Item deleted.')),
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

  // ── Availability ──────────────────────────────────────────────────────────────

  Future<void> _openAvailabilityDialog(
      CatalogNode node, String? parentIdContext) async {
    if (!node.isActive) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'This item is globally disabled. Use Edit to re-enable it.')),
        );
      }
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => CatalogNodeAvailabilityDialog(
        node: node,
        parentIdContext: parentIdContext,
        fetchCurrentState: () async {
          if (parentIdContext != null) {
            return ref
                .read(catalogNodeRepositoryProvider)
                .fetchRelationshipAvailability(parentIdContext, node.id);
          }
          return (
            status: node.availabilityStatus,
            message: node.unavailabilityMessage,
          );
        },
        fetchAreas: () =>
            ref.read(serviceAvailabilityAreasRepositoryProvider).fetchAll(),
        fetchLocationRestrictions: () => ref
            .read(catalogNodeRepositoryProvider)
            .fetchLocationRestrictions(node.id, parentIdContext),
        onSave: (status, message) async {
          await ref
              .read(catalogNodeNotifierProvider.notifier)
              .setAvailability(node.id, parentIdContext, status, message);
          ref.invalidate(relAvailabilityProvider);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Availability updated.')),
            );
          }
        },
        onSaveLocationRestrictions: (areaIds) async {
          await ref
              .read(catalogNodeRepositoryProvider)
              .saveLocationRestrictions(node.id, parentIdContext, areaIds);
          ref.invalidate(locationRestrictionsProvider);
        },
      ),
    );
  }

  // ── Toggles ───────────────────────────────────────────────────────────────────

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

  // ── Manage categories ─────────────────────────────────────────────────────────

  void _manageParents(CatalogNode node) {
    final allNodes =
        ref.read(catalogNodeNotifierProvider).valueOrNull ?? [];
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CatalogNodeParentsDialog(
        node: node,
        allNodes: allNodes,
        onSave: (toAdd, toRemove) async {
          for (final parentId in toRemove) {
            await ref
                .read(catalogNodeNotifierProvider.notifier)
                .removeParent(node.id, parentId);
          }
          for (final parentId in toAdd) {
            await ref
                .read(catalogNodeNotifierProvider.notifier)
                .addParent(node.id, parentId);
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Categories updated.')),
            );
          }
        },
      ),
    );
  }

  Future<void> _removeFromParent(
      CatalogNode node, String parentId) async {
    final allNodes =
        ref.read(catalogNodeNotifierProvider).valueOrNull ?? [];
    final parentNode =
        allNodes.where((n) => n.id == parentId).firstOrNull;
    final parentName = parentNode?.name ?? 'this category';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Remove from "$parentName"?'),
        content: Text(
          node.parentIds.length == 1
              ? '"${node.name}" will become a top-level item (not under any category).'
              : '"${node.name}" will be removed from "$parentName" but will stay in its other categories.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref
          .read(catalogNodeNotifierProvider.notifier)
          .removeParent(node.id, parentId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Removed "${node.name}" from $parentName.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  // ── Scheduling / Attributes ───────────────────────────────────────────────────

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

  // ── Module config ─────────────────────────────────────────────────────────────

  void _openConfigPanel(CatalogNode node, String? parentIdContext) {
    final allNodes =
        ref.read(catalogNodeNotifierProvider).valueOrNull ?? [];
    final parentNode = parentIdContext != null
        ? allNodes.where((n) => n.id == parentIdContext).firstOrNull
        : null;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CatalogNodeConfigDialog(
        nodeId: node.id,
        nodeName: node.name,
        parentNodeId: parentIdContext,
        parentNodeName: parentNode?.name,
        hasChildren: node.childrenCount > 0,
      ),
    );
  }

  // ── FAQs ──────────────────────────────────────────────────────────────────────

  void _openFaqs(CatalogNode node, String? parentIdContext) {
    NodeFaqsDialog.show(context, node, parentId: parentIdContext);
  }

  // ── AMC Plans ─────────────────────────────────────────────────────────────────

  void _openAmcPlans(CatalogNode node) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => NodeAmcPlansDialog(
        nodeId: node.id,
        nodeName: node.name,
        nodeBasePrice: node.basePrice,
      ),
    );
  }

  // ── Showcase Photos ───────────────────────────────────────────────────────────

  void _openShowcaseImages(CatalogNode node) {
    ServiceShowcaseDialog.show(context, node);
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final nodesAsync = ref.watch(catalogNodeNotifierProvider);

    final callbacks = NodeCallbacks(
      onAddChild: (parent) => _openCreate(parent: parent),
      onEdit: (node, hasChildren) => _openEdit(node, hasChildren),
      onManageParents: _manageParents,
      onRemoveFromParent: _removeFromParent,
      onDelete: _deleteNode,
      onSetAvailability: _openAvailabilityDialog,
      onToggleBookable: _toggleBookable,
      onOpenScheduling: _openScheduling,
      onOpenConfig: _openConfigPanel,
      onOpenAmcPlans: _openAmcPlans,
      onOpenFaqs: _openFaqs,
      onOpenShowcaseImages: _openShowcaseImages,
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
                  'Unlimited nesting · cross-listed services · admin-controlled',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => BulkUploadDialog.show(
              context,
              CatalogBulkModule(),
              onComplete: () =>
                  ref.read(catalogNodeNotifierProvider.notifier).refresh(),
            ),
            icon: const Icon(Icons.upload_file_rounded, size: 16),
            label: const Text('Bulk Upload'),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: () => _openCreate(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Item'),
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
        hintText: 'Search catalog…',
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
    // An item with parentIds = ['a', 'b'] is added to BOTH byParent['a']
    // and byParent['b'], so it appears under each category in the tree.
    // Top-level items (parentIds empty) go to byParent[null].
    final byParent = <String?, List<CatalogNode>>{};
    for (final n in allNodes) {
      if (n.isRoot) {
        byParent.putIfAbsent(null, () => []).add(n);
      }
      for (final pid in n.parentIds) {
        byParent.putIfAbsent(pid, () => []).add(n);
      }
    }
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

    Set<String> matchingIds = {};
    Set<String> ancestorIds = {};
    Set<String> autoExpandIds = {};

    if (isSearching) {
      final byId = {for (final n in allNodes) n.id: n};

      void collectAncestors(String nodeId) {
        final node = byId[nodeId];
        if (node == null) return;
        for (final pid in node.parentIds) {
          if (ancestorIds.add(pid)) {
            autoExpandIds.add(pid);
            collectAncestors(pid);
          }
        }
      }

      for (final n in allNodes) {
        if (n.name.toLowerCase().contains(q)) {
          matchingIds.add(n.id);
          collectAncestors(n.id);
        }
      }
    }

    final visibleIds = {...matchingIds, ...ancestorIds};

    final effectiveExpandedIds = isSearching
        ? {..._expandedIds, ...autoExpandIds}
        : _expandedIds;

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
                  : 'No catalog items yet. Add one to get started.',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            if (!isSearching) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _openCreate(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Item'),
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
            // Root tiles have no parent context; key includes 'root' prefix
            // to distinguish from child appearances of the same node.
            key: ValueKey('root_${root.id}'),
            node: root,
            children: displayByParent[root.id] ?? [],
            allByParent: displayByParent,
            depth: 0,
            expandedIds: effectiveExpandedIds,
            onToggleExpand: _toggleExpand,
            callbacks: callbacks,
            parentIdContext: null,
            searchQuery: _searchQuery,
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}
