import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/widgets/highlighted_text.dart';
import '../../domain/models/catalog_node.dart';

/// Callbacks passed from [CatalogV2Page] down to each tile.
/// All callbacks receive the specific [CatalogNode] they operate on.
class NodeCallbacks {
  const NodeCallbacks({
    required this.onAddChild,
    required this.onEdit,
    required this.onMove,
    required this.onDelete,
    required this.onToggleActive,
    required this.onToggleBookable,
    required this.onOpenAttributes,
  });

  final void Function(CatalogNode parent) onAddChild;
  final void Function(CatalogNode node) onEdit;
  final void Function(CatalogNode node) onMove;
  final void Function(CatalogNode node) onDelete;
  final void Function(CatalogNode node, bool isActive) onToggleActive;
  final void Function(CatalogNode node, bool isBookable) onToggleBookable;
  final void Function(CatalogNode node) onOpenAttributes;
}

/// Renders a single catalog node row and recursively renders its children
/// when expanded. Indentation is purely visual (depth × 28px).
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
    this.searchQuery = '',
  });

  final CatalogNode node;

  /// Direct children of [node], pre-filtered by the parent page.
  final List<CatalogNode> children;

  /// Full parent→children map for recursive rendering.
  final Map<String?, List<CatalogNode>> allByParent;

  final int depth;
  final Set<String> expandedIds;
  final void Function(String nodeId) onToggleExpand;
  final NodeCallbacks callbacks;
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
              key: ValueKey(child.id),
              node: child,
              children: allByParent[child.id] ?? [],
              allByParent: allByParent,
              depth: depth + 1,
              expandedIds: expandedIds,
              onToggleExpand: onToggleExpand,
              callbacks: callbacks,
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
                // Expand chevron (invisible when no children, keeps alignment)
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
                      fontWeight: depth == 0
                          ? FontWeight.w600
                          : FontWeight.w500,
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
                if (node.isBookable) ...[
                  _Chip(
                    'Bookable',
                    AppColors.accent.withValues(alpha: 0.12),
                    AppColors.accent,
                  ),
                  const SizedBox(width: 4),
                ],
                if (node.basePrice != null && node.isBookable) ...[
                  _Chip(
                    '₹${node.basePrice!.toStringAsFixed(0)}',
                    const Color(0xFFEBF8F0),
                    AppColors.success,
                  ),
                  const SizedBox(width: 4),
                ],
                if (children.isNotEmpty) ...[
                  _Chip(
                    '${children.length}',
                    AppColors.primary.withValues(alpha: 0.08),
                    AppColors.primary,
                  ),
                  const SizedBox(width: 4),
                ],

                // is_active switch
                Switch(
                  value: node.isActive,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) => callbacks.onToggleActive(node, v),
                ),

                // is_bookable icon toggle
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

                // Attributes (only for bookable nodes)
                if (node.isBookable)
                  IconButton(
                    icon: const Icon(Icons.tune_rounded, size: 17),
                    tooltip: 'Attributes',
                    color: AppColors.primary,
                    onPressed: () => callbacks.onOpenAttributes(node),
                  ),

                // Add child
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 17),
                  tooltip: 'Add Child',
                  color: AppColors.accent,
                  onPressed: () => callbacks.onAddChild(node),
                ),

                // Edit
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  tooltip: 'Edit',
                  color: AppColors.textSecondary,
                  onPressed: () => callbacks.onEdit(node),
                ),

                // Move
                IconButton(
                  icon: const Icon(Icons.drive_file_move_outlined, size: 17),
                  tooltip: 'Move',
                  color: AppColors.primary,
                  onPressed: () => callbacks.onMove(node),
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
        label: const Text('Add Child', style: TextStyle(fontSize: 12)),
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

// ── Internal badge widget ──────────────────────────────────────────────────────

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
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
