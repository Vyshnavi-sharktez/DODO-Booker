import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/widgets/highlighted_text.dart';
import '../../application/providers/catalog_node_providers.dart';
import '../../domain/models/catalog_node.dart';

/// Callbacks passed from [CatalogV2Page] down to each tile.
class NodeCallbacks {
  const NodeCallbacks({
    required this.onAddChild,
    required this.onEdit,
    required this.onManageParents,
    required this.onRemoveFromParent,
    required this.onDelete,
    required this.onSetAvailability,
    required this.onToggleBookable,
    required this.onOpenScheduling,
    required this.onOpenConfig,
    required this.onOpenAmcPlans,
    required this.onOpenFaqs,
    required this.onOpenShowcaseImages,
  });

  final void Function(CatalogNode parent) onAddChild;
  final void Function(CatalogNode node, bool hasChildren) onEdit;

  /// Opens the "Manage Categories" dialog for this item.
  final void Function(CatalogNode node) onManageParents;

  /// Removes this item from a specific parent category.
  /// [parentId] is the category it is currently rendered under.
  final void Function(CatalogNode node, String parentId) onRemoveFromParent;

  final void Function(CatalogNode node) onDelete;

  /// Opens the availability dialog for [node] accessed via [parentIdContext].
  /// [parentIdContext] is null for root nodes — the change is then node-scoped.
  final void Function(CatalogNode node, String? parentIdContext) onSetAvailability;
  final void Function(CatalogNode node, bool isBookable) onToggleBookable;
  final void Function(CatalogNode node) onOpenScheduling;

  /// Opens the module configuration dialog (Tax/Loyalty/Scheduling/Commission).
  /// [parentIdContext] is passed so the dialog can offer relationship-scoped config.
  final void Function(CatalogNode node, String? parentIdContext) onOpenConfig;

  /// Opens the AMC Plans linking dialog for this bookable leaf node.
  final void Function(CatalogNode node) onOpenAmcPlans;

  /// Opens the FAQs & Customer Questions dialog for this bookable leaf node.
  /// [parentIdContext] scopes customer questions to this parent relationship.
  final void Function(CatalogNode node, String? parentIdContext) onOpenFaqs;

  /// Opens the showcase photos dialog for this bookable leaf node.
  final void Function(CatalogNode node) onOpenShowcaseImages;
}

/// Renders a single catalog item row and recursively renders its children
/// when expanded.  Indentation is purely visual (depth × 28 px).
///
/// [parentIdContext] is the ID of the category this tile is rendered under
/// (null for top-level tiles).  It is used to offer "Remove from this
/// category" when the item is cross-listed.
class CatalogNodeTile extends StatelessWidget {
  const CatalogNodeTile({
    super.key,
    required this.node,
    required this.children,
    required this.allByParent,
    required this.depth,
    required this.expandedIds,
    required this.onToggleExpand,
    required this.callbacks,
    this.parentIdContext,
    this.searchQuery = '',
  });

  final CatalogNode node;

  /// Direct children pre-filtered by the parent page.
  final List<CatalogNode> children;

  /// Full parent→children map for recursive rendering.
  final Map<String?, List<CatalogNode>> allByParent;

  final int depth;
  final Set<String> expandedIds;
  final void Function(String nodeId) onToggleExpand;
  final NodeCallbacks callbacks;

  /// The parent category ID this tile is rendered under; null for root tiles.
  final String? parentIdContext;

  final String searchQuery;

  bool get _isExpanded => expandedIds.contains(node.id);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRow(context),
        if (_isExpanded) ...[
          for (final child in children)
            CatalogNodeTile(
              // Key encodes (parent, child) so the same node appearing
              // under two different parents gets two distinct widget keys.
              key: ValueKey('${node.id}_${child.id}'),
              node: child,
              children: allByParent[child.id] ?? [],
              allByParent: allByParent,
              depth: depth + 1,
              expandedIds: expandedIds,
              onToggleExpand: onToggleExpand,
              callbacks: callbacks,
              parentIdContext: node.id,
              searchQuery: searchQuery,
            ),
          _buildAddChildButton(),
        ],
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildRow(BuildContext context) {
    final indent = depth * 28.0;
    final hasChildren = children.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: _rowColor(depth),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: InkWell(
          onTap: hasChildren ? () => onToggleExpand(node.id) : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // Expand chevron
                SizedBox(
                  width: 20,
                  child: hasChildren
                      ? AnimatedRotation(
                          turns: _isExpanded ? 0.25 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: const Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 6),

                // Node icon
                Icon(
                  _nodeIcon(depth, hasChildren),
                  size: 16,
                  color: _nodeIconColor(depth),
                ),
                const SizedBox(width: 8),

                // Name
                Expanded(
                  child: HighlightedText(
                    text: node.name,
                    query: searchQuery,
                    style: TextStyle(
                      fontWeight:
                          depth == 0 ? FontWeight.w600 : FontWeight.w500,
                      fontSize: depth == 0 ? 14 : 13,
                      color: node.isActive
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 6),

                // Chips
                if (!hasChildren && node.isBookable) ...[
                  _Chip(
                    'Bookable',
                    AppColors.accent.withValues(alpha: 0.12),
                    AppColors.accent,
                  ),
                  const SizedBox(width: 4),
                ],
                if (!hasChildren &&
                    node.basePrice != null &&
                    node.isBookable) ...[
                  _Chip(
                    '₹${node.basePrice!.toStringAsFixed(0)}',
                    const Color(0xFFEBF8F0),
                    AppColors.success,
                  ),
                  const SizedBox(width: 4),
                ],
                if (hasChildren) ...[
                  _Chip(
                    '${children.length}',
                    AppColors.primary.withValues(alpha: 0.08),
                    AppColors.primary,
                  ),
                  const SizedBox(width: 4),
                ],
                // "Shared" badge — this item is listed under multiple categories.
                if (node.isShared) ...[
                  _Chip(
                    'Shared',
                    const Color(0xFFF3E5F5),
                    const Color(0xFF7B1FA2),
                  ),
                  const SizedBox(width: 4),
                ],

                // Availability control.
                // For non-root nodes look up the per-relationship status so
                // the icon reflects the path-scoped state, not the node-global one.
                // Also checks locationRestrictionsProvider so the 4th
                // "location-wise" icon appears without opening the dialog.
                Consumer(
                  builder: (ctx, ref, _) {
                    final relMap =
                        ref.watch(relAvailabilityProvider).valueOrNull ?? {};
                    final locationKeys =
                        ref.watch(locationRestrictionsProvider).valueOrNull ??
                            {};
                    final effectiveStatus = parentIdContext != null
                        ? (relMap['$parentIdContext|${node.id}'] ?? 'active')
                        : node.availabilityStatus;
                    final hasLocationRestriction = parentIdContext != null
                        ? locationKeys
                            .contains('rel:$parentIdContext|${node.id}')
                        : locationKeys.contains('node:${node.id}');
                    return _AvailabilityButton(
                      isGloballyDisabled: !node.isActive,
                      availabilityStatus: effectiveStatus,
                      isPathScoped: parentIdContext != null,
                      hasLocationRestriction: hasLocationRestriction,
                      onTap: () =>
                          callbacks.onSetAvailability(node, parentIdContext),
                    );
                  },
                ),

                // Bookable toggle — hidden when node has children
                if (!hasChildren)
                  Tooltip(
                    message: node.isBookable
                        ? 'Bookable — click to disable'
                        : 'Not Bookable — click to enable',
                    child: IconButton(
                      icon: Icon(
                        node.isBookable
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_outline_rounded,
                        size: 17,
                        color: node.isBookable
                            ? AppColors.accent
                            : AppColors.textSecondary,
                      ),
                      onPressed: () =>
                          callbacks.onToggleBookable(node, !node.isBookable),
                    ),
                  ),

                // Scheduling — bookable leaf nodes only
                if (!hasChildren && node.isBookable)
                  IconButton(
                    icon: const Icon(Icons.schedule_rounded, size: 17),
                    tooltip: 'Scheduling',
                    color: AppColors.accent,
                    onPressed: () => callbacks.onOpenScheduling(node),
                  ),

                // AMC Plans — bookable leaf nodes only
                if (!hasChildren && node.isBookable)
                  IconButton(
                    icon: const Icon(Icons.auto_mode_rounded, size: 17),
                    tooltip: 'AMC Plans',
                    color: AppColors.primary,
                    onPressed: () => callbacks.onOpenAmcPlans(node),
                  ),

                // FAQs — bookable leaf nodes only
                if (!hasChildren && node.isBookable)
                  IconButton(
                    icon: const Icon(Icons.quiz_rounded, size: 17),
                    tooltip: 'FAQs',
                    color: AppColors.primary,
                    onPressed: () => callbacks.onOpenFaqs(node, parentIdContext),
                  ),

                // Showcase Photos — bookable leaf nodes only
                if (!hasChildren && node.isBookable)
                  IconButton(
                    icon: const Icon(Icons.photo_library_rounded, size: 17),
                    tooltip: 'Showcase Photos',
                    color: AppColors.primary,
                    onPressed: () => callbacks.onOpenShowcaseImages(node),
                  ),

                // Module config (Tax / Loyalty / Scheduling / Commission)
                IconButton(
                  icon: const Icon(Icons.tune_rounded, size: 17),
                  tooltip: 'Configure Tax / Loyalty / Scheduling / Platform Commission',
                  color: AppColors.primary,
                  onPressed: () =>
                      callbacks.onOpenConfig(node, parentIdContext),
                ),

                // Add child
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 17),
                  tooltip: 'Add item inside',
                  color: AppColors.accent,
                  onPressed: () => callbacks.onAddChild(node),
                ),

                // Edit
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  tooltip: 'Edit',
                  color: AppColors.textSecondary,
                  onPressed: () => callbacks.onEdit(node, hasChildren),
                ),

                // Manage Categories
                IconButton(
                  icon: const Icon(Icons.category_outlined, size: 17),
                  tooltip: 'Manage Categories',
                  color: AppColors.primary,
                  onPressed: () => callbacks.onManageParents(node),
                ),

                // Remove from this category — only when rendered under a specific parent
                if (parentIdContext != null)
                  IconButton(
                    icon: const Icon(Icons.link_off_rounded, size: 17),
                    tooltip: 'Remove from this category',
                    color: AppColors.textSecondary,
                    onPressed: () =>
                        callbacks.onRemoveFromParent(node, parentIdContext!),
                  ),

                // Delete
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 17),
                  tooltip: 'Delete',
                  color: AppColors.error,
                  onPressed: () => callbacks.onDelete(node),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddChildButton() {
    return Padding(
      padding: EdgeInsets.only(left: (depth + 1) * 28.0 + 16, bottom: 4),
      child: TextButton.icon(
        onPressed: () => callbacks.onAddChild(node),
        icon: const Icon(Icons.add, size: 13),
        label: const Text('Add Item', style: TextStyle(fontSize: 12)),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        ),
      ),
    );
  }

  // ── Visual helpers ─────────────────────────────────────────────────────────

  Color _rowColor(int depth) {
    if (depth == 0) return AppColors.surface;
    if (depth == 1) return const Color(0xFFF0F4FF);
    if (depth == 2) return const Color(0xFFF5F7FA);
    return AppColors.surface;
  }

  IconData _nodeIcon(int depth, bool hasChildren) {
    if (hasChildren) {
      return depth == 0
          ? Icons.folder_rounded
          : Icons.folder_open_rounded;
    }
    return Icons.home_repair_service_rounded;
  }

  Color _nodeIconColor(int depth) {
    if (depth == 0) return AppColors.primary;
    if (depth == 1) return AppColors.primaryLight;
    return AppColors.textSecondary;
  }
}

// ── Availability icon button ───────────────────────────────────────────────────

class _AvailabilityButton extends StatelessWidget {
  const _AvailabilityButton({
    required this.isGloballyDisabled,
    required this.availabilityStatus,
    required this.isPathScoped,
    required this.hasLocationRestriction,
    required this.onTap,
  });

  final bool isGloballyDisabled;

  /// Effective availability status — relationship-scoped for non-root nodes,
  /// node-scoped for root nodes.
  final String availabilityStatus;

  /// True when this tile is rendered under a specific parent (non-root).
  final bool isPathScoped;

  /// True when at least one location restriction row exists for this
  /// node/path. Only shown when [availabilityStatus] is 'active' — if the
  /// node is also marked unavailable/hidden that state takes precedence.
  final bool hasLocationRestriction;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (isGloballyDisabled) {
      return Tooltip(
        message: 'Globally disabled — use Edit to re-enable',
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(Icons.block_rounded, size: 17, color: AppColors.error),
        ),
      );
    }
    final scope = isPathScoped ? 'this path' : 'globally';
    final (IconData icon, Color color, String tooltip) =
        hasLocationRestriction && availabilityStatus == 'active'
            ? (
                Icons.location_on_rounded,
                const Color(0xFF6366F1),
                'Location-wise Availability — click to change',
              )
            : switch (availabilityStatus) {
                'unavailable' => (
                    Icons.pause_circle_outline_rounded,
                    const Color(0xFFF59E0B),
                    'Temporarily unavailable ($scope) — click to change',
                  ),
                'hidden' => (
                    Icons.visibility_off_outlined,
                    AppColors.textSecondary,
                    'Hidden ($scope) — click to change',
                  ),
                _ => (
                    Icons.check_circle_outline_rounded,
                    AppColors.success,
                    'Active — click to set availability',
                  ),
              };
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 17, color: color),
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

// ── Badge chip ─────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.bg, this.fg);
  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
