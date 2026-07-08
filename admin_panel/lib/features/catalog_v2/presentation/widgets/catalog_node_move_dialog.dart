import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../domain/models/catalog_node.dart';

/// Lets the admin pick a new parent for [node].
/// All descendants of [node] are excluded (would form a cycle).
/// "No parent (root)" is always available.
class CatalogNodeMoveDialog extends StatefulWidget {
  const CatalogNodeMoveDialog({
    super.key,
    required this.node,
    required this.allNodes,
    required this.onMove,
  });

  final CatalogNode node;

  /// The complete flat list of all catalog nodes (loaded by the page).
  final List<CatalogNode> allNodes;

  /// Called with the chosen [newParentId] (null = make root).
  final Future<void> Function(String? newParentId) onMove;

  @override
  State<CatalogNodeMoveDialog> createState() => _CatalogNodeMoveDialogState();
}

class _CatalogNodeMoveDialogState extends State<CatalogNodeMoveDialog> {
  String _search = '';
  String? _selectedParentId; // sentinel: _unset means "not chosen yet"
  bool _selectedIsRoot = false;
  bool _saving = false;

  static const _unset = '__unset__';
  String _chosen = _unset;

  /// IDs that must be excluded from the picker: the node itself + all descendants.
  late final Set<String> _excluded = _computeExcluded();

  /// Valid choices: all nodes except excluded ones.
  late final List<CatalogNode> _candidates = widget.allNodes
      .where((n) => !_excluded.contains(n.id))
      .toList();

  /// Breadcrumb path map: nodeId → "A › B › C"
  late final Map<String, String> _paths = _buildPaths();

  Set<String> _computeExcluded() {
    final byParent = <String?, List<String>>{};
    for (final n in widget.allNodes) {
      byParent.putIfAbsent(n.parentId, () => []).add(n.id);
    }
    final result = <String>{widget.node.id};
    final queue = [widget.node.id];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      for (final childId in byParent[current] ?? []) {
        result.add(childId);
        queue.add(childId);
      }
    }
    return result;
  }

  Map<String, String> _buildPaths() {
    final byId = {for (final n in widget.allNodes) n.id: n};
    String pathFor(String id) {
      final parts = <String>[];
      String? cursor = id;
      while (cursor != null) {
        final n = byId[cursor];
        if (n == null) break;
        parts.insert(0, n.name);
        cursor = n.parentId;
      }
      return parts.join(' › ');
    }

    return {for (final n in widget.allNodes) n.id: pathFor(n.id)};
  }

  List<CatalogNode> get _filtered {
    final q = _search.toLowerCase();
    if (q.isEmpty) return _candidates;
    return _candidates
        .where((n) =>
            n.name.toLowerCase().contains(q) ||
            (_paths[n.id] ?? '').toLowerCase().contains(q))
        .toList();
  }

  Future<void> _submit() async {
    if (_chosen == _unset) return;
    setState(() => _saving = true);
    try {
      await widget.onMove(_selectedIsRoot ? null : _selectedParentId);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Move failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final hasChoice = _chosen != _unset;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.drive_file_move_outlined,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Move Node',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          widget.node.name,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // ── Search ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search nodes...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),

            // ── List ─────────────────────────────────────────────────────────
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                children: [
                  // "No parent" option — make a root node
                  _ChoiceRow(
                    icon: Icons.account_tree_outlined,
                    title: 'No parent (make root)',
                    subtitle: 'Move to the top level',
                    isSelected: _selectedIsRoot && _chosen != _unset,
                    onTap: () => setState(() {
                      _selectedIsRoot = true;
                      _selectedParentId = null;
                      _chosen = '__root__';
                    }),
                  ),
                  const Divider(height: 16),

                  if (filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('No matching nodes.',
                            style: TextStyle(
                                color: AppColors.textSecondary)),
                      ),
                    ),

                  for (final n in filtered)
                    _ChoiceRow(
                      icon: Icons.folder_open_outlined,
                      title: n.name,
                      subtitle: _paths[n.id] ?? '',
                      isSelected:
                          !_selectedIsRoot && _selectedParentId == n.id,
                      onTap: () => setState(() {
                        _selectedIsRoot = false;
                        _selectedParentId = n.id;
                        _chosen = n.id;
                      }),
                    ),
                ],
              ),
            ),

            // ── Footer ───────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              decoration: const BoxDecoration(
                border:
                    Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: (!hasChoice || _saving) ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 12),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Move Here'),
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

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accent.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? AppColors.accent.withValues(alpha: 0.4)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 18,
                color: isSelected
                    ? AppColors.accent
                    : AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isSelected
                          ? AppColors.accent
                          : AppColors.textPrimary,
                    ),
                  ),
                  if (subtitle.isNotEmpty && subtitle != title)
                    Text(
                      subtitle,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded,
                  size: 18, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}
