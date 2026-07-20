import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/service_availability_areas_providers.dart';
import '../../domain/models/service_availability_area.dart';
import '../widgets/service_availability_area_dialog.dart';

class ServiceAvailabilityAreasPage extends ConsumerStatefulWidget {
  const ServiceAvailabilityAreasPage({super.key});

  @override
  ConsumerState<ServiceAvailabilityAreasPage> createState() =>
      _ServiceAvailabilityAreasPageState();
}

class _ServiceAvailabilityAreasPageState
    extends ConsumerState<ServiceAvailabilityAreasPage> {
  String _search = '';
  bool? _filterActive; // null = all, true = active, false = inactive

  List<ServiceAvailabilityArea> _apply(List<ServiceAvailabilityArea> all) {
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
    final result = await showDialog<ServiceAvailabilityArea>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ServiceAvailabilityAreaDialog(),
    );
    if (result == null || !mounted) return;
    try {
      await ref
          .read(serviceAvailabilityAreasRepositoryProvider)
          .create(result);
      ref.invalidate(serviceAvailabilityAreasProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('"${result.name}" added successfully.'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to add: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _openEdit(ServiceAvailabilityArea area) async {
    final result = await showDialog<ServiceAvailabilityArea>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ServiceAvailabilityAreaDialog(existing: area),
    );
    if (result == null || !mounted) return;
    try {
      await ref
          .read(serviceAvailabilityAreasRepositoryProvider)
          .update(area.id, result);
      ref.invalidate(serviceAvailabilityAreasProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('"${result.name}" updated.'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to update: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _toggleActive(ServiceAvailabilityArea area) async {
    try {
      await ref
          .read(serviceAvailabilityAreasRepositoryProvider)
          .setActive(area.id, active: !area.isActive);
      ref.invalidate(serviceAvailabilityAreasProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _confirmDelete(ServiceAvailabilityArea area) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Service Area?'),
        content: Text('Delete "${area.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref
          .read(serviceAvailabilityAreasRepositoryProvider)
          .delete(area.id);
      ref.invalidate(serviceAvailabilityAreasProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('"${area.name}" deleted.'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to delete: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final areasAsync = ref.watch(serviceAvailabilityAreasProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────────
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Service Availability Areas',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'Defines where DODO Booker currently accepts bookings',
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
          const SizedBox(height: 16),

          // ── Info banner ───────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withAlpha(60)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'When no active areas are configured, all locations are '
                    'serviceable (opt-in feature). Add areas to restrict bookings '
                    'to specific zones.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Filters ───────────────────────────────────────────────────────────
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

          // ── Content ───────────────────────────────────────────────────────────
          Expanded(
            child: areasAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
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
                          ref.invalidate(serviceAvailabilityAreasProvider),
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
                        Text(
                          'No service areas configured',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'All locations are currently serviceable.\n'
                          'Add areas to restrict bookings to specific zones.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
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
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _AreaCard(
                    area: areas[i],
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
          border: Border.all(color: selected ? c : AppColors.border),
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
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });
  final ServiceAvailabilityArea area;
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
              Icons.map_rounded,
              size: 22,
              color: area.isActive
                  ? AppColors.primary
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 14),

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
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.radio_button_unchecked_rounded,
                        size: 12, color: AppColors.accent),
                    const SizedBox(width: 4),
                    Text(
                      '${area.radiusKm.toStringAsFixed(1)} km radius',
                      style:
                          TextStyle(fontSize: 11, color: AppColors.accent),
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
              ],
            ),
          ),

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
