import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/vendors_providers.dart';
import '../../domain/models/vendor.dart';
import '../widgets/vendor_form_dialog.dart';

// ── Status display config ─────────────────────────────────────────────────────

const _statusConfig = <String, (String, Color, Color)>{
  'active': ('Active', Color(0xFF38A169), Color(0xFFF0FFF4)),
  'inactive': ('Inactive', Color(0xFF718096), Color(0xFFF7FAFC)),
  'pending': ('Pending', Color(0xFFDD6B20), Color(0xFFFEEBC8)),
  'suspended': ('Suspended', Color(0xFFE53E3E), Color(0xFFFFF5F5)),
};

const _allStatuses = ['active', 'inactive', 'pending', 'suspended'];

class VendorsPage extends ConsumerStatefulWidget {
  const VendorsPage({super.key});

  @override
  ConsumerState<VendorsPage> createState() => _VendorsPageState();
}

class _VendorsPageState extends ConsumerState<VendorsPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _cityFilter;
  String? _statusFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Vendor> _applyFilters(List<Vendor> all) {
    var result = all;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where((v) =>
              v.businessName.toLowerCase().contains(q) ||
              (v.ownerName?.toLowerCase().contains(q) ?? false) ||
              v.phone.contains(q) ||
              v.email.toLowerCase().contains(q))
          .toList();
    }
    if (_cityFilter != null) {
      result = result.where((v) => v.city == _cityFilter).toList();
    }
    if (_statusFilter != null) {
      result = result.where((v) => v.status == _statusFilter).toList();
    }
    return result;
  }

  List<String> _uniqueCities(List<Vendor> vendors) {
    return vendors
        .map((v) => v.city)
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  void _openCreate() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => VendorFormDialog(
        onSave: ({
          required businessName,
          ownerName,
          required phone,
          required email,
          required city,
          address,
          required status,
          required isActive,
          rating,
          walletBalance,
        }) async {
          await ref.read(vendorsNotifierProvider.notifier).createVendor(
                businessName: businessName,
                ownerName: ownerName,
                phone: phone,
                email: email,
                city: city,
                address: address,
                status: status,
                isActive: isActive,
                rating: rating,
                walletBalance: walletBalance ?? 0.0,
              );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Vendor added successfully')),
            );
          }
        },
      ),
    );
  }

  void _openEdit(Vendor vendor) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => VendorFormDialog(
        existing: vendor,
        onSave: ({
          required businessName,
          ownerName,
          required phone,
          required email,
          required city,
          address,
          required status,
          required isActive,
          rating,
          walletBalance,
        }) async {
          await ref.read(vendorsNotifierProvider.notifier).updateVendor(
                vendor.id,
                businessName: businessName,
                ownerName: ownerName,
                phone: phone,
                email: email,
                city: city,
                address: address,
                status: status,
                isActive: isActive,
                rating: rating,
                walletBalance: walletBalance,
              );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Vendor updated successfully')),
            );
          }
        },
      ),
    );
  }

  Future<void> _confirmDelete(Vendor vendor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Vendor'),
        content: Text(
          'Are you sure you want to delete "${vendor.businessName}"?\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(vendorsNotifierProvider.notifier)
          .deleteVendor(vendor.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Vendor deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _toggle(Vendor vendor) async {
    try {
      await ref
          .read(vendorsNotifierProvider.notifier)
          .toggleActive(vendor.id, currentIsActive: vendor.isActive);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vendorsNotifierProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Responsive Header ─────────────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 600;
              return Flex(
                direction: narrow ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: narrow
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vendors',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Manage vendor onboarding and lifecycle',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  if (narrow) const SizedBox(height: 12) else const Spacer(),
                  FilledButton.icon(
                    onPressed: _openCreate,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add Vendor'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // ── Search + Filters ──────────────────────────────────────────────
          state.when(
            loading: () => const SizedBox.shrink(),
            error: (err, st) => const SizedBox.shrink(),
            data: (all) => Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Search
                SizedBox(
                  width: 280,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search name, phone, email…',
                      prefixIcon:
                          const Icon(Icons.search_rounded, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded,
                                  size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    onChanged: (v) =>
                        setState(() => _searchQuery = v.trim()),
                  ),
                ),

                // City filter
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: _cityFilter,
                    decoration: const InputDecoration(
                      hintText: 'All Cities',
                      prefixIcon:
                          Icon(Icons.location_city_rounded, size: 18),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All Cities'),
                      ),
                      ..._uniqueCities(all).map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(c),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _cityFilter = v),
                    isExpanded: true,
                  ),
                ),

                // Status filter
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: _statusFilter,
                    decoration: const InputDecoration(
                      hintText: 'All Statuses',
                      prefixIcon: Icon(Icons.flag_rounded, size: 18),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All Statuses'),
                      ),
                      ..._allStatuses.map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(
                            _statusConfig[s]?.$1 ??
                                s[0].toUpperCase() + s.substring(1),
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _statusFilter = v),
                    isExpanded: true,
                  ),
                ),

                // Clear filters button
                if (_cityFilter != null || _statusFilter != null)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _cityFilter = null;
                      _statusFilter = null;
                    }),
                    icon: const Icon(Icons.filter_alt_off_rounded,
                        size: 16),
                    label: const Text('Clear'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Body ──────────────────────────────────────────────────────────
          Expanded(
            child: state.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 48, color: AppColors.error),
                    const SizedBox(height: 12),
                    Text(
                      'Failed to load vendors',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      e.toString(),
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => ref
                          .read(vendorsNotifierProvider.notifier)
                          .refresh(),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (all) {
                final filtered = _applyFilters(all);
                if (all.isEmpty) {
                  return _EmptyState(
                    message: 'No vendors yet',
                    sub:
                        'Click "Add Vendor" to register the first one.',
                    onAdd: _openCreate,
                  );
                }
                if (filtered.isEmpty) {
                  return _EmptyState(
                    message: 'No vendors match your filters',
                    sub: 'Try adjusting your search or filters.',
                  );
                }
                return _VendorsTable(
                  vendors: filtered,
                  totalCount: all.length,
                  onEdit: _openEdit,
                  onDelete: _confirmDelete,
                  onToggle: _toggle,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Table ──────────────────────────────────────────────────────────────────────

class _VendorsTable extends StatelessWidget {
  final List<Vendor> vendors;
  final int totalCount;
  final void Function(Vendor) onEdit;
  final void Function(Vendor) onDelete;
  final void Function(Vendor) onToggle;

  const _VendorsTable({
    required this.vendors,
    required this.totalCount,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  static const double _minTableWidth = 800;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tableWidth = constraints.maxWidth < _minTableWidth
                      ? _minTableWidth
                      : constraints.maxWidth;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            color: AppColors.background,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: const Row(
                              children: [
                                _HeaderCell('Name', flex: 3),
                                _HeaderCell('Phone', flex: 2),
                                _HeaderCell('Email', flex: 3),
                                _HeaderCell('City', flex: 2),
                                _HeaderCell('Status', flex: 2),
                                _HeaderCell('Rating', flex: 1),
                                _HeaderCell('Created', flex: 2),
                                _HeaderCell('Actions', flex: 2,
                                    align: TextAlign.center),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: ListView.separated(
                              itemCount: vendors.length,
                              separatorBuilder: (_, idx) =>
                                  const Divider(height: 1),
                              itemBuilder: (ctx, i) {
                                final v = vendors[i];
                                return _VendorRow(
                                  vendor: v,
                                  onEdit: () => onEdit(v),
                                  onDelete: () => onDelete(v),
                                  onToggle: () => onToggle(v),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              color: AppColors.background,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              child: Text(
                vendors.length == totalCount
                    ? '${vendors.length} vendor${vendors.length == 1 ? '' : 's'}'
                    : '${vendors.length} of $totalCount vendor${totalCount == 1 ? '' : 's'}',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  final int flex;
  final TextAlign align;

  const _HeaderCell(this.label,
      {required this.flex, this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: align,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _VendorRow extends StatelessWidget {
  final Vendor vendor;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  const _VendorRow({
    required this.vendor,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final createdStr = vendor.createdAt != null
        ? DateFormat('dd MMM yyyy').format(vendor.createdAt!)
        : '—';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Avatar + Business Name + Owner Name
          Expanded(
            flex: 3,
            child: Row(
              children: [
                _VendorAvatar(
                  imageUrl: vendor.profileImageUrl,
                  initials: _initials(vendor.businessName),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vendor.businessName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (vendor.ownerName != null &&
                          vendor.ownerName!.isNotEmpty)
                        Text(
                          vendor.ownerName!,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Phone
          Expanded(
            flex: 2,
            child: Text(
              vendor.phone,
              style: TextStyle(
                  fontSize: 13, color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Email
          Expanded(
            flex: 3,
            child: Text(
              vendor.email,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.accent,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // City
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Icon(Icons.location_on_rounded,
                    size: 13, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    vendor.city,
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Status
          Expanded(
            flex: 2,
            child: _StatusBadge(status: vendor.status),
          ),

          // Rating
          Expanded(
            flex: 1,
            child: vendor.rating != null
                ? Row(
                    children: [
                      Icon(Icons.star_rounded,
                          size: 14, color: Colors.amber.shade600),
                      const SizedBox(width: 3),
                      Text(
                        vendor.rating!.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  )
                : Text(
                    '—',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
          ),

          // Created
          Expanded(
            flex: 2,
            child: Text(
              createdStr,
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
          ),

          // Actions
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: vendor.isActive,
                    onChanged: (_) => onToggle(),
                    activeThumbColor: AppColors.success,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                IconButton(
                  onPressed: onEdit,
                  icon: Icon(Icons.edit_rounded,
                      size: 16, color: AppColors.accent),
                  tooltip: 'Edit',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 16, color: AppColors.error),
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VendorAvatar extends StatelessWidget {
  const _VendorAvatar({required this.imageUrl, required this.initials});
  final String? imageUrl;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 18,
      backgroundColor: AppColors.primaryLight,
      backgroundImage: imageUrl != null ? NetworkImage(imageUrl!) : null,
      onBackgroundImageError: imageUrl != null ? (err, st) {} : null,
      child: imageUrl == null
          ? Text(
              initials,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            )
          : null,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final cfg = _statusConfig[status];
    final label = cfg?.$1 ?? status;
    final color = cfg?.$2 ?? AppColors.textSecondary;
    final bg = cfg?.$3 ?? AppColors.background;

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String message;
  final String sub;
  final VoidCallback? onAdd;

  const _EmptyState({
    required this.message,
    required this.sub,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.store_outlined,
            size: 56,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sub,
            style: TextStyle(
                fontSize: 13, color: AppColors.textSecondary),
          ),
          if (onAdd != null) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add Vendor'),
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary),
            ),
          ],
        ],
      ),
    );
  }
}
