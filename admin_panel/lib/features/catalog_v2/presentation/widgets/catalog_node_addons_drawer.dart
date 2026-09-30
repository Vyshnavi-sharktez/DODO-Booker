import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../service_addons/application/providers/service_addons_providers.dart';
import '../../../service_addons/data/service_addons_repository.dart';
import '../../../service_addons/domain/models/service_addon.dart';
import '../../../service_addons/presentation/widgets/addon_form_dialog.dart';

class CatalogNodeAddonsDrawer extends ConsumerStatefulWidget {
  final String nodeId;
  final String nodeName;

  const CatalogNodeAddonsDrawer({
    super.key,
    required this.nodeId,
    required this.nodeName,
  });

  @override
  ConsumerState<CatalogNodeAddonsDrawer> createState() =>
      _CatalogNodeAddonsDrawerState();
}

class _CatalogNodeAddonsDrawerState
    extends ConsumerState<CatalogNodeAddonsDrawer> {
  static final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  bool _loading = true;
  List<ServiceAddon> _ownAddons = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  ServiceAddonsRepository get _repo =>
      ref.read(serviceAddonsRepositoryProvider);

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final addons = await _repo.fetchNodeAddons(widget.nodeId);
      if (mounted) {
        setState(() {
          _ownAddons = addons;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showSnack('Failed to load add-ons: $e', isError: true);
      }
    }
  }

  // ── Create & assign ───────────────────────────────────────────────────────────

  void _openCreateAddon() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddonFormDialog(
        onSave: ({
          required name,
          String? description,
          required price,
          required isActive,
          String discountType = 'percentage',
          double discountValue = 0,
        }) async {
          final newAddon = await _repo.create(
            name: name,
            description: description,
            price: price,
            isActive: isActive,
            discountType: discountType,
            discountValue: discountValue,
          );
          await _repo.assignAddon(widget.nodeId, newAddon.id);
          ref.invalidate(allAddonsNotifierProvider);
          await _load();
        },
      ),
    );
  }

  // ── Assign existing ───────────────────────────────────────────────────────────

  Future<void> _openAssignExisting() async {
    final allAsync = ref.read(allAddonsNotifierProvider);
    final all = allAsync.valueOrNull ?? [];
    final assignedIds = _ownAddons.map((a) => a.id).toSet();
    final available = all.where((a) => !assignedIds.contains(a.id)).toList();

    if (available.isEmpty) {
      _showSnack('All add-ons are already assigned to this node.');
      return;
    }

    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => _AddonPickerDialog(addons: available),
    );

    if (selected == null || selected.isEmpty || !mounted) return;

    setState(() => _loading = true);
    try {
      for (final id in selected) {
        await _repo.assignAddon(widget.nodeId, id);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showSnack('Failed to assign: $e', isError: true);
      }
    }
  }

  // ── Edit ──────────────────────────────────────────────────────────────────────

  void _openEditAddon(ServiceAddon addon) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddonFormDialog(
        existing: addon,
        onSave: ({
          required name,
          String? description,
          required price,
          required isActive,
          String discountType = 'percentage',
          double discountValue = 0,
        }) async {
          await _repo.update(
            addon.id,
            name: name,
            description: description,
            price: price,
            isActive: isActive,
            discountType: discountType,
            discountValue: discountValue,
          );
          ref.invalidate(allAddonsNotifierProvider);
          await _load();
        },
      ),
    );
  }

  // ── Unassign ──────────────────────────────────────────────────────────────────

  Future<void> _unassignAddon(ServiceAddon addon) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Remove Add-on?'),
        content: Text(
            'Remove "${addon.name}" from this node? The add-on definition will be kept.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await _repo.unassignAddon(widget.nodeId, addon.id);
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showSnack('Failed to remove: $e', isError: true);
      }
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Pre-load all addons so assign picker is instant
    ref.watch(allAddonsNotifierProvider);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildOwnAddonsSection(),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.extension_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add-ons',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  widget.nodeName,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
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

  Widget _buildOwnAddonsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Own Add-ons',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _openAssignExisting,
              icon: const Icon(Icons.link_rounded, size: 14),
              label: const Text('Assign', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _openCreateAddon,
              icon: const Icon(Icons.add_rounded, size: 14),
              label: const Text('New', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_ownAddons.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: const Column(
              children: [
                Icon(Icons.extension_off_rounded,
                    size: 32, color: AppColors.textSecondary),
                SizedBox(height: 8),
                Text(
                  'No add-ons assigned to this node',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          )
        else
          ...(_ownAddons.map((addon) => _buildAddonRow(addon))),
      ],
    );
  }

  Widget _buildAddonRow(ServiceAddon addon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  addon.isActive ? AppColors.success : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  addon.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (addon.hasDiscount)
                  Row(
                    children: [
                      Text(
                        _currency.format(addon.price),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _currency.format(addon.finalPrice),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    _currency.format(addon.price),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 15),
            tooltip: 'Edit',
            color: AppColors.textSecondary,
            visualDensity: VisualDensity.compact,
            onPressed: () => _openEditAddon(addon),
          ),
          IconButton(
            icon: const Icon(Icons.link_off_rounded, size: 15),
            tooltip: 'Remove from node',
            color: AppColors.error,
            visualDensity: VisualDensity.compact,
            onPressed: () => _unassignAddon(addon),
          ),
        ],
      ),
    );
  }

}

// ── Assign existing addon picker ───────────────────────────────────────────────

class _AddonPickerDialog extends StatefulWidget {
  final List<ServiceAddon> addons;

  const _AddonPickerDialog({required this.addons});

  @override
  State<_AddonPickerDialog> createState() => _AddonPickerDialogState();
}

class _AddonPickerDialogState extends State<_AddonPickerDialog> {
  static final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Assign Existing Add-ons',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70, size: 18),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // List
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: widget.addons.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final addon = widget.addons[i];
                  final checked = _selected.contains(addon.id);
                  return InkWell(
                    onTap: () => setState(() {
                      if (checked) {
                        _selected.remove(addon.id);
                      } else {
                        _selected.add(addon.id);
                      }
                    }),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: checked
                            ? AppColors.primary.withValues(alpha: 0.06)
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: checked
                              ? AppColors.primary
                              : AppColors.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Checkbox(
                            value: checked,
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _selected.add(addon.id);
                              } else {
                                _selected.remove(addon.id);
                              }
                            }),
                            activeColor: AppColors.primary,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              addon.name,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            _currency.format(addon.finalPrice),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.border))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(_selected),
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary),
                    child: Text(
                      _selected.isEmpty
                          ? 'Assign'
                          : 'Assign ${_selected.length}',
                    ),
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
