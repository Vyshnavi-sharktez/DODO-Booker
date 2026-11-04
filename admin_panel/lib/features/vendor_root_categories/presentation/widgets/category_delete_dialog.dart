import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/vendor_root_categories_repository.dart';
import '../../domain/models/vendor_root_category.dart';

class CategoryDeleteDialog extends StatefulWidget {
  const CategoryDeleteDialog({
    super.key,
    required this.category,
    required this.allCategories,
    required this.onDeleted,
  });

  final VendorRootCategory category;
  final List<VendorRootCategory> allCategories;
  final VoidCallback onDeleted;

  static Future<void> show(
    BuildContext context, {
    required VendorRootCategory category,
    required List<VendorRootCategory> allCategories,
    required VoidCallback onDeleted,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CategoryDeleteDialog(
        category: category,
        allCategories: allCategories,
        onDeleted: onDeleted,
      ),
    );
  }

  @override
  State<CategoryDeleteDialog> createState() => _CategoryDeleteDialogState();
}

class _CategoryDeleteDialogState extends State<CategoryDeleteDialog> {
  final _repo = VendorRootCategoriesRepository(Supabase.instance.client);

  // Lifecycle states
  bool _loadingDeps = true;
  bool _actioning = false;
  String? _error;

  // Dependency data
  CategoryDeps? _deps;

  // Reassignment state
  bool _showReassign = false;
  String? _targetCategoryId;

  List<VendorRootCategory> get _otherCategories =>
      widget.allCategories.where((c) => c.id != widget.category.id).toList();

  @override
  void initState() {
    super.initState();
    _loadDeps();
  }

  Future<void> _loadDeps() async {
    try {
      final deps = await _repo.checkDeps(widget.category.id);
      if (mounted) setState(() {
        _deps = deps;
        _loadingDeps = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loadingDeps = false;
      });
    }
  }

  Future<void> _reassignAndDelete() async {
    if (_targetCategoryId == null) return;
    setState(() {
      _actioning = true;
      _error = null;
    });
    try {
      await _repo.reassign(
        fromId: widget.category.id,
        toId: _targetCategoryId!,
      );
      await _repo.delete(widget.category.id);
      if (mounted) {
        Navigator.of(context).pop();
        widget.onDeleted();
      }
    } catch (e) {
      if (mounted) setState(() {
        _actioning = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _delete() async {
    setState(() {
      _actioning = true;
      _error = null;
    });
    try {
      await _repo.delete(widget.category.id);
      if (mounted) {
        Navigator.of(context).pop();
        widget.onDeleted();
      }
    } catch (e) {
      if (mounted) setState(() {
        _actioning = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Delete "${widget.category.name}"',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: _buildBody(),
      ),
      actions: _buildActions(),
    );
  }

  Widget _buildBody() {
    if (_loadingDeps) {
      return const SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final deps = _deps;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (deps != null) ...[
          _StatsRow(deps: deps),
          const SizedBox(height: 16),
          if (deps.hasDependencies) ...[
            _WarningBox(deps: deps),
            const SizedBox(height: 16),
            if (!_showReassign) ...[
              const Text(
                'You must reassign services to another category before this '
                'category can be deleted.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ] else ...[
              _ReassignSection(
                otherCategories: _otherCategories,
                selectedId: _targetCategoryId,
                onSelected: (id) => setState(() => _targetCategoryId = id),
              ),
            ],
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 16, color: AppColors.success),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No active services reference this category. '
                      'It is safe to delete.',
                      style:
                          TextStyle(fontSize: 12, color: AppColors.success),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorBox(message: _error!),
        ],
      ],
    );
  }

  List<Widget> _buildActions() {
    if (_loadingDeps) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ];
    }

    final deps = _deps;
    final hasDeps = deps?.hasDependencies ?? true;

    if (hasDeps && !_showReassign) {
      return [
        TextButton(
          onPressed: _actioning ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _actioning || _otherCategories.isEmpty
              ? null
              : () => setState(() => _showReassign = true),
          icon: const Icon(Icons.swap_horiz_rounded, size: 16),
          label: const Text('Reassign & Delete'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
        ),
      ];
    }

    if (hasDeps && _showReassign) {
      return [
        TextButton(
          onPressed: _actioning
              ? null
              : () => setState(() {
                    _showReassign = false;
                    _targetCategoryId = null;
                  }),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed:
              _actioning || _targetCategoryId == null ? null : _reassignAndDelete,
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          child: _actioning
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Reassign & Delete'),
        ),
      ];
    }

    // No deps — simple confirm delete
    return [
      TextButton(
        onPressed: _actioning ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _actioning ? null : _delete,
        style: FilledButton.styleFrom(backgroundColor: AppColors.error),
        child: _actioning
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Text('Delete'),
      ),
    ];
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.deps});
  final CategoryDeps deps;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatChip(
          label: 'Active services',
          value: deps.activeServiceCount.toString(),
          color: deps.activeServiceCount > 0
              ? AppColors.error
              : AppColors.textSecondary,
        ),
        const SizedBox(width: 8),
        _StatChip(
          label: 'Total services',
          value: deps.totalServiceCount.toString(),
          color: deps.totalServiceCount > 0
              ? const Color(0xFFB45309)
              : AppColors.textSecondary,
        ),
        const SizedBox(width: 8),
        _StatChip(
          label: 'Vendors',
          value: deps.vendorCount.toString(),
          color: AppColors.textSecondary,
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: color),
          ),
        ],
      ),
    );
  }
}

class _WarningBox extends StatelessWidget {
  const _WarningBox({required this.deps});
  final CategoryDeps deps;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[];
    if (deps.activeServiceCount > 0) {
      lines.add(
        '${deps.activeServiceCount} active service(s) will lose their category '
        'assignment and disappear from customer discovery.',
      );
    }
    lines.add(
      'Historical bookings are preserved — they reference the service directly, '
      'not the category.',
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 15, color: AppColors.error),
              SizedBox(width: 6),
              Text(
                'Dependencies detected',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...lines.map(
            (l) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '• $l',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReassignSection extends StatelessWidget {
  const _ReassignSection({
    required this.otherCategories,
    required this.selectedId,
    required this.onSelected,
  });
  final List<VendorRootCategory> otherCategories;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'All services in this category will be moved to:',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: selectedId,
          isExpanded: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Select target category',
            isDense: true,
          ),
          items: otherCategories.map((c) {
            return DropdownMenuItem(
              value: c.id,
              child: Row(
                children: [
                  Expanded(child: Text(c.name, overflow: TextOverflow.ellipsis)),
                  if (!c.isAdminCreated)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Text(
                        'vendor',
                        style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary),
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) onSelected(v);
          },
        ),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 15, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
