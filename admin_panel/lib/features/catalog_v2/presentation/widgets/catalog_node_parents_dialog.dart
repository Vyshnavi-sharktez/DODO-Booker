import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../domain/models/catalog_node.dart';

/// Lets the admin manage which categories a catalog item is listed under.
///
/// Shows current categories as removable chips, plus a searchable picker
/// to add the item to additional categories.  Changes are staged locally
/// and committed in one batch when the admin saves.
class CatalogNodeParentsDialog extends StatefulWidget {
  const CatalogNodeParentsDialog({
    super.key,
    required this.node,
    required this.allNodes,
    required this.onSave,
  });

  final CatalogNode node;
  final List<CatalogNode> allNodes;

  /// Called with lists of parent IDs to add and to remove.
  final Future<void> Function(
    List<String> toAdd,
    List<String> toRemove,
  ) onSave;

  @override
  State<CatalogNodeParentsDialog> createState() =>
      _CatalogNodeParentsDialogState();
}

class _CatalogNodeParentsDialogState
    extends State<CatalogNodeParentsDialog> {
  late List<String> _currentParentIds;
  String _search = '';
  bool _saving = false;

  // ── Derived once ───────────────────────────────────────────────────────────

  late final Set<String> _excluded = _computeExcluded();
  late final Map<String, String> _paths = _buildPaths();
  late final Map<String, CatalogNode> _byId = {
    for (final n in widget.allNodes) n.id: n
  };

  @override
  void initState() {
    super.initState();
    _currentParentIds = List.from(widget.node.parentIds);
  }

  // ── Candidates ─────────────────────────────────────────────────────────────

  /// Nodes that cannot be a parent: the item itself + all its descendants.
  Set<String> _computeExcluded() {
    final childrenOf = <String, List<String>>{};
    for (final n in widget.allNodes) {
      for (final pid in n.parentIds) {
        childrenOf.putIfAbsent(pid, () => []).add(n.id);
      }
    }
    final excluded = <String>{widget.node.id};
    final queue = <String>[widget.node.id];
    while (queue.isNotEmpty) {
      final curr = queue.removeLast();
      for (final childId in childrenOf[curr] ?? []) {
        if (excluded.add(childId)) queue.add(childId);
      }
    }
    return excluded;
  }

  Map<String, String> _buildPaths() {
    String pathFor(String id) {
      final parts = <String>[];
      String? cursor = id;
      while (cursor != null) {
        final n = widget.allNodes
            .where((x) => x.id == cursor)
            .firstOrNull;
        if (n == null) break;
        parts.insert(0, n.name);
        cursor = n.primaryParentId;
      }
      return parts.join(' › ');
    }
    return {for (final n in widget.allNodes) n.id: pathFor(n.id)};
  }

  List<CatalogNode> get _candidates {
    final q = _search.toLowerCase();
    return widget.allNodes.where((n) {
      if (_excluded.contains(n.id)) return false;
      if (_currentParentIds.contains(n.id)) return false;
      if (q.isEmpty) return true;
      return n.name.toLowerCase().contains(q) ||
          (_paths[n.id] ?? '').toLowerCase().contains(q);
    }).toList();
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void _addParent(String parentId) {
    if (!_currentParentIds.contains(parentId)) {
      setState(() => _currentParentIds.add(parentId));
    }
  }

  void _removeParent(String parentId) {
    setState(() => _currentParentIds.remove(parentId));
  }

  void _makeTopLevel() {
    setState(() => _currentParentIds.clear());
  }

  Future<void> _save() async {
    final original = widget.node.parentIds.toSet();
    final current = _currentParentIds.toSet();
    final toAdd = current.difference(original).toList();
    final toRemove = original.difference(current).toList();

    if (toAdd.isEmpty && toRemove.isEmpty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.onSave(toAdd, toRemove);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save changes: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool get _hasChanges {
    final original = widget.node.parentIds.toSet();
    final current = _currentParentIds.toSet();
    return original != current;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 620),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                children: [
                  _buildCurrentParents(),
                  const SizedBox(height: 20),
                  _buildAddSection(),
                ],
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.category_outlined, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Manage Categories',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.node.name,
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentParents() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Currently listed under',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        if (_currentParentIds.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFE082)),
            ),
            child: Row(
              children: const [
                Icon(Icons.info_outline_rounded,
                    size: 16, color: Color(0xFFF9A825)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This item is a top-level item — visible at the root of the catalog.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF795548),
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final pid in _currentParentIds)
                _ParentChip(
                  label: _byId[pid]?.name ?? pid,
                  path: _paths[pid] ?? '',
                  onRemove: () => _removeParent(pid),
                ),
            ],
          ),
        if (_currentParentIds.isNotEmpty) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _makeTopLevel,
            child: const Text(
              'Move to top level (no category)',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAddSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Add to another category',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          autofocus: false,
          decoration: InputDecoration(
            hintText: 'Search categories…',
            prefixIcon: const Icon(Icons.search, size: 18),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: 8),
        Builder(builder: (_) {
          final candidates = _candidates;
          if (candidates.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  _search.isNotEmpty
                      ? 'No matching categories.'
                      : 'No other categories available.',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
            );
          }
          return Column(
            children: [
              for (final n in candidates)
                _CandidateRow(
                  name: n.name,
                  path: _paths[n.id] ?? '',
                  onTap: () => _addParent(n.id),
                ),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed:
                _saving ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: (!_hasChanges || _saving) ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            ),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Save Changes'),
          ),
        ],
      ),
    );
  }
}

// ── Current-parent chip ────────────────────────────────────────────────────────

class _ParentChip extends StatelessWidget {
  const _ParentChip({
    required this.label,
    required this.path,
    required this.onRemove,
  });
  final String label;
  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.folder_rounded,
              size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded,
                size: 14, color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

// ── Add-parent candidate row ───────────────────────────────────────────────────

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.name,
    required this.path,
    required this.onTap,
  });
  final String name;
  final String path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        margin: const EdgeInsets.only(bottom: 2),
        child: Row(
          children: [
            const Icon(Icons.add_circle_outline,
                size: 16, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (path.isNotEmpty && path != name)
                    Text(
                      path,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
