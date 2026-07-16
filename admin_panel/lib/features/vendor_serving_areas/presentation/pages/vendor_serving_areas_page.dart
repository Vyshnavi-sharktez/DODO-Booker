import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/vendor_serving_areas_providers.dart';
import '../../domain/models/vendor_serving_area.dart';
import '../widgets/vendor_serving_area_dialog.dart';

class VendorServingAreasPage extends ConsumerStatefulWidget {
  const VendorServingAreasPage({super.key});

  @override
  ConsumerState<VendorServingAreasPage> createState() =>
      _VendorServingAreasPageState();
}

class _VendorServingAreasPageState
    extends ConsumerState<VendorServingAreasPage> {
  String _search = '';
  bool? _filterActive; // null = all, true = active, false = inactive

  List<VendorServingArea> _apply(List<VendorServingArea> all) {
    var list = all;
    if (_filterActive != null) {
      list = list.where((a) => a.isActive == _filterActive).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list
          .where((a) =>
              a.name.toLowerCase().contains(q) ||
              a.city.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  Future<void> _openAdd() async {
    final result = await showDialog<VendorServingArea>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const VendorServingAreaDialog(),
    );
    if (result == null || !mounted) return;
    try {
      await ref.read(vendorServingAreasRepositoryProvider).create(result);
      ref.invalidate(vendorServingAreasProvider);
      ref.invalidate(areaAssignmentCountsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${result.name}" added successfully.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _openEdit(VendorServingArea area) async {
    final result = await showDialog<VendorServingArea>(
      context: context,
      barrierDismissible: false,
      builder: (_) => VendorServingAreaDialog(existing: area),
    );
    if (result == null || !mounted) return;
    try {
      await ref
          .read(vendorServingAreasRepositoryProvider)
          .update(area.id, result);
      ref.invalidate(vendorServingAreasProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${result.name}" updated.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _toggleActive(VendorServingArea area) async {
    try {
      await ref
          .read(vendorServingAreasRepositoryProvider)
          .setActive(area.id, active: !area.isActive);
      ref.invalidate(vendorServingAreasProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _confirmDelete(VendorServingArea area) async {
    final repo = ref.read(vendorServingAreasRepositoryProvider);
    final count = await repo.countAssignments(area.id);

    if (!mounted) return;

    if (count > 0) {
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Cannot Delete'),
          content: Text(
            '"${area.name}" is assigned to $count vendor${count == 1 ? '' : 's'}.\n'
            'Remove all vendor assignments before deleting this area.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Serving Area?'),
        content: Text('Delete "${area.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final result = await repo.delete(area.id);
    if (!mounted) return;

    if (result.deleted) {
      ref.invalidate(vendorServingAreasProvider);
      ref.invalidate(areaAssignmentCountsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${area.name}" deleted.'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Delete failed.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _openVendorsDialog(VendorServingArea area) {
    showDialog<void>(
      context: context,
      builder: (_) => _VendorsInAreaDialog(area: area),
    );
  }

  @override
  Widget build(BuildContext context) {
    final areasAsync = ref.watch(vendorServingAreasProvider);
    final counts = ref.watch(areaAssignmentCountsProvider).valueOrNull ?? {};

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vendor Serving Areas',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'Admin-defined geographic zones vendors can select during registration',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _openAdd,
                icon: const Icon(Icons.add_location_alt_rounded, size: 16),
                label: const Text('Add Area'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Filters ─────────────────────────────────────────────────────────
          Row(
            children: [
              SizedBox(
                width: 280,
                child: TextFormField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Search by name or city…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _FilterChip(
                label: 'All',
                selected: _filterActive == null,
                onTap: () => setState(() => _filterActive = null),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Active',
                selected: _filterActive == true,
                onTap: () => setState(() => _filterActive = true),
                color: AppColors.success,
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Inactive',
                selected: _filterActive == false,
                onTap: () => setState(() => _filterActive = false),
                color: AppColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Content ─────────────────────────────────────────────────────────
          Expanded(
            child: areasAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        color: AppColors.error, size: 40),
                    const SizedBox(height: 12),
                    Text('Failed to load: $e',
                        style: TextStyle(color: AppColors.error)),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () =>
                          ref.invalidate(vendorServingAreasProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (all) {
                final areas = _apply(all);
                if (all.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.map_outlined,
                            size: 56, color: AppColors.textSecondary),
                        const SizedBox(height: 16),
                        Text('No serving areas yet',
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 6),
                        Text('Add the first area for vendors to select.',
                            style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary)),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _openAdd,
                          icon: const Icon(Icons.add_location_alt_rounded,
                              size: 16),
                          label: const Text('Add Area'),
                          style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary),
                        ),
                      ],
                    ),
                  );
                }
                if (areas.isEmpty) {
                  return Center(
                    child: Text(
                      'No areas match the current filters.',
                      style: TextStyle(
                          fontSize: 14, color: AppColors.textSecondary),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: areas.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _AreaCard(
                    area: areas[i],
                    vendorCount: counts[areas[i].id] ?? 0,
                    onViewVendors: () => _openVendorsDialog(areas[i]),
                    onEdit: () => _openEdit(areas[i]),
                    onToggleActive: () => _toggleActive(areas[i]),
                    onDelete: () => _confirmDelete(areas[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Filter chip ───────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.withAlpha(30) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? c : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? c : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ── Area card ─────────────────────────────────────────────────────────────────

class _AreaCard extends StatelessWidget {
  const _AreaCard({
    required this.area,
    required this.vendorCount,
    required this.onViewVendors,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });
  final VendorServingArea area;
  final int vendorCount;
  final VoidCallback onViewVendors;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: area.isActive
              ? AppColors.border
              : AppColors.border.withAlpha(100),
        ),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: area.isActive
                  ? AppColors.primaryLight
                  : AppColors.border.withAlpha(60),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.location_on_rounded,
              size: 22,
              color:
                  area.isActive ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      area.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: area.isActive
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusBadge(isActive: area.isActive),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  area.city,
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.radio_button_unchecked_rounded,
                        size: 12, color: AppColors.accent),
                    const SizedBox(width: 4),
                    Text(
                      '${area.radiusKm.toStringAsFixed(1)} km radius',
                      style: TextStyle(fontSize: 11, color: AppColors.accent),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.gps_fixed_rounded,
                        size: 12, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      '${area.latitude.toStringAsFixed(4)}, '
                      '${area.longitude.toStringAsFixed(4)}',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Vendor count + view action
                Row(
                  children: [
                    Icon(Icons.group_outlined,
                        size: 13, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      '$vendorCount ${vendorCount == 1 ? 'Vendor' : 'Vendors'}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: vendorCount > 0
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: onViewVendors,
                      child: Text(
                        'View Vendors',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Management actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: area.isActive ? 'Deactivate' : 'Activate',
                child: IconButton(
                  onPressed: onToggleActive,
                  icon: Icon(
                    area.isActive
                        ? Icons.toggle_on_rounded
                        : Icons.toggle_off_rounded,
                    size: 26,
                    color: area.isActive
                        ? AppColors.success
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              Tooltip(
                message: 'Edit',
                child: IconButton(
                  onPressed: onEdit,
                  icon: Icon(Icons.edit_rounded,
                      size: 18, color: AppColors.primary),
                ),
              ),
              Tooltip(
                message: 'Delete',
                child: IconButton(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 18, color: AppColors.error),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isActive});
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.success : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

// ── Vendors in area dialog ────────────────────────────────────────────────────

class _VendorsInAreaDialog extends ConsumerWidget {
  const _VendorsInAreaDialog({required this.area});
  final VendorServingArea area;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendorsAsync = ref.watch(vendorsByAreaProvider(area.id));

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.group_rounded,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          area.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${area.city}  •  ${area.radiusKm.toStringAsFixed(1)} km radius',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
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

            // Body
            Flexible(
              child: vendorsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'Failed to load vendors: $e',
                      style: TextStyle(color: AppColors.error, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                data: (vendors) {
                  if (vendors.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.store_outlined,
                                size: 40, color: AppColors.textSecondary),
                            const SizedBox(height: 12),
                            Text(
                              'No vendors are currently serving this area.',
                              style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    shrinkWrap: true,
                    itemCount: vendors.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) =>
                        _VendorSummaryTile(vendor: vendors[i]),
                  );
                },
              ),
            ),

            // Footer
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VendorSummaryTile extends StatelessWidget {
  const _VendorSummaryTile({required this.vendor});
  final Map<String, dynamic> vendor;

  @override
  Widget build(BuildContext context) {
    final businessName = vendor['business_name'] as String? ?? '—';
    final ownerName = vendor['owner_name'] as String?;
    final phone = vendor['phone'] as String? ?? '—';
    final status = vendor['status'] as String? ?? 'pending';
    final isActive = vendor['is_active'] as bool? ?? false;

    final statusColor = switch (status) {
      'approved' => AppColors.success,
      'pending' => AppColors.warning,
      'suspended' => AppColors.error,
      _ => AppColors.textSecondary,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primaryLight,
            child: Text(
              businessName.isNotEmpty ? businessName[0].toUpperCase() : '?',
              style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 15),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  businessName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (ownerName != null && ownerName.isNotEmpty)
                  Text(
                    ownerName,
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                Text(
                  phone,
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor.withAlpha(80)),
                ),
                child: Text(
                  status[0].toUpperCase() + status.substring(1),
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: statusColor),
                ),
              ),
              if (!isActive) ...[
                const SizedBox(height: 4),
                Text(
                  'Inactive',
                  style: TextStyle(
                      fontSize: 10, color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
