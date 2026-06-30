import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/clickable.dart';
import '../../application/providers/coupons_providers.dart';
import '../../domain/models/coupon.dart';
import '../widgets/coupon_form_dialog.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const _discountTypeConfig = <String, (String, Color)>{
  'percentage': ('% Off', Color(0xFF805AD5)),
  'flat': ('₹ Off', Color(0xFF3182CE)),
};

final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
final _dateFmt = DateFormat('dd MMM yyyy');

// ── Filter enum ───────────────────────────────────────────────────────────────

enum _StatusFilter { all, active, inactive, expired }

// ── Page ──────────────────────────────────────────────────────────────────────

class CouponsPage extends ConsumerStatefulWidget {
  const CouponsPage({super.key});

  @override
  ConsumerState<CouponsPage> createState() => _CouponsPageState();
}

class _CouponsPageState extends ConsumerState<CouponsPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  _StatusFilter _statusFilter = _StatusFilter.all;
  String? _typeFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Coupon> _applyFilters(List<Coupon> all) {
    var result = all;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toUpperCase();
      result = result.where((c) => c.code.contains(q)).toList();
    }
    switch (_statusFilter) {
      case _StatusFilter.active:
        result = result.where((c) => c.isActive && !c.isExpired).toList();
      case _StatusFilter.inactive:
        result = result.where((c) => !c.isActive).toList();
      case _StatusFilter.expired:
        result = result.where((c) => c.isExpired).toList();
      case _StatusFilter.all:
        break;
    }
    if (_typeFilter != null) {
      result =
          result.where((c) => c.discountType == _typeFilter).toList();
    }
    return result;
  }

  bool get _hasFilters =>
      _statusFilter != _StatusFilter.all || _typeFilter != null;

  void _openCreate() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CouponFormDialog(
        onSave: ({
          required code,
          description,
          required discountType,
          required discountValue,
          minOrderAmount,
          maxDiscountAmount,
          usageLimit,
          validFrom,
          validTo,
          required isActive,
        }) async {
          await ref.read(couponsNotifierProvider.notifier).createCoupon(
                code: code,
                description: description,
                discountType: discountType,
                discountValue: discountValue,
                minOrderAmount: minOrderAmount,
                maxDiscountAmount: maxDiscountAmount,
                usageLimit: usageLimit,
                validFrom: validFrom,
                validTo: validTo,
                isActive: isActive,
              );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Coupon created successfully')),
            );
          }
        },
      ),
    );
  }

  void _openEdit(Coupon coupon) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CouponFormDialog(
        existing: coupon,
        onSave: ({
          required code,
          description,
          required discountType,
          required discountValue,
          minOrderAmount,
          maxDiscountAmount,
          usageLimit,
          validFrom,
          validTo,
          required isActive,
        }) async {
          await ref.read(couponsNotifierProvider.notifier).updateCoupon(
                coupon.id,
                code: code,
                description: description,
                discountType: discountType,
                discountValue: discountValue,
                minOrderAmount: minOrderAmount,
                maxDiscountAmount: maxDiscountAmount,
                usageLimit: usageLimit,
                validFrom: validFrom,
                validTo: validTo,
                isActive: isActive,
              );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Coupon updated successfully')),
            );
          }
        },
      ),
    );
  }

  Future<void> _confirmDelete(Coupon coupon) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Coupon'),
        content: Text(
          'Are you sure you want to delete coupon "${coupon.code}"?\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(couponsNotifierProvider.notifier)
          .deleteCoupon(coupon.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Coupon deleted')),
        );
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

  Future<void> _toggle(Coupon coupon) async {
    try {
      await ref
          .read(couponsNotifierProvider.notifier)
          .toggleActive(coupon.id, currentIsActive: coupon.isActive);
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
    final state = ref.watch(couponsNotifierProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Coupons',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Create and manage promotional coupons',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _openCreate,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New Coupon'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                ),
              ),
            ],
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
                  width: 240,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search coupon code…',
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

                // Status filter chips
                _FilterChip(
                  label: 'All',
                  selected: _statusFilter == _StatusFilter.all,
                  onTap: () =>
                      setState(() => _statusFilter = _StatusFilter.all),
                ),
                _FilterChip(
                  label: 'Active',
                  selected: _statusFilter == _StatusFilter.active,
                  color: const Color(0xFF38A169),
                  onTap: () =>
                      setState(() => _statusFilter = _StatusFilter.active),
                ),
                _FilterChip(
                  label: 'Inactive',
                  selected: _statusFilter == _StatusFilter.inactive,
                  color: const Color(0xFF718096),
                  onTap: () => setState(
                      () => _statusFilter = _StatusFilter.inactive),
                ),
                _FilterChip(
                  label: 'Expired',
                  selected: _statusFilter == _StatusFilter.expired,
                  color: const Color(0xFFE53E3E),
                  onTap: () => setState(
                      () => _statusFilter = _StatusFilter.expired),
                ),

                // Discount type filter
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: _typeFilter,
                    decoration: const InputDecoration(
                      hintText: 'Discount Type',
                      prefixIcon: Icon(Icons.percent_rounded, size: 18),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('All Types')),
                      ..._discountTypeConfig.entries.map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value.$1),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _typeFilter = v),
                  ),
                ),

                if (_hasFilters)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _statusFilter = _StatusFilter.all;
                      _typeFilter = null;
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
                      'Failed to load coupons',
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
                          .read(couponsNotifierProvider.notifier)
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
                    message: 'No coupons yet',
                    sub: 'Click "New Coupon" to create the first one.',
                    onAdd: _openCreate,
                  );
                }
                if (filtered.isEmpty) {
                  return const _EmptyState(
                    message: 'No coupons match your filters',
                    sub: 'Try adjusting your search or filters.',
                  );
                }
                return _CouponsTable(
                  coupons: filtered,
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

// ── Filter chip ────────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    this.color = const Color(0xFF4A90D9),
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Clickable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.12)
              : AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.5)
                : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? color : AppColors.textSecondary,
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ── Table ──────────────────────────────────────────────────────────────────────

class _CouponsTable extends StatelessWidget {
  final List<Coupon> coupons;
  final int totalCount;
  final void Function(Coupon) onEdit;
  final void Function(Coupon) onDelete;
  final void Function(Coupon) onToggle;

  const _CouponsTable({
    required this.coupons,
    required this.totalCount,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

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
            // Scrollable table
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 1140,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      _TableHeader(),
                      const Divider(height: 1),
                      // Rows
                      Expanded(
                        child: ListView.separated(
                          itemCount: coupons.length,
                          separatorBuilder: (_, idx) =>
                              const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final c = coupons[i];
                            return _CouponRow(
                              coupon: c,
                              onEdit: () => onEdit(c),
                              onDelete: () => onDelete(c),
                              onToggle: () => onToggle(c),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Footer
            Container(
              color: AppColors.background,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              child: Text(
                coupons.length == totalCount
                    ? '${coupons.length} coupon${coupons.length == 1 ? '' : 's'}'
                    : '${coupons.length} of $totalCount coupon${totalCount == 1 ? '' : 's'}',
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

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: const Row(
        children: [
          _HCell('Code', width: 130),
          _HCell('Description', width: 160),
          _HCell('Type', width: 90),
          _HCell('Value', width: 80, align: TextAlign.right),
          _HCell('Min Order', width: 90, align: TextAlign.right),
          _HCell('Limit', width: 60, align: TextAlign.right),
          _HCell('Used', width: 55, align: TextAlign.right),
          _HCell('Valid From', width: 100),
          _HCell('Valid To', width: 100),
          _HCell('Status', width: 100),
          _HCell('Actions', width: 124, align: TextAlign.center),
        ],
      ),
    );
  }
}

class _HCell extends StatelessWidget {
  final String text;
  final double width;
  final TextAlign align;

  const _HCell(this.text,
      {required this.width, this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        text,
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

class _CouponRow extends StatelessWidget {
  final Coupon coupon;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  const _CouponRow({
    required this.coupon,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final typeCfg = _discountTypeConfig[coupon.discountType];
    final typeLabel = typeCfg?.$1 ?? coupon.discountType;
    final typeColor = typeCfg?.$2 ?? AppColors.textSecondary;

    final valueStr = coupon.discountType == 'percentage'
        ? '${coupon.discountValue.toStringAsFixed(coupon.discountValue % 1 == 0 ? 0 : 1)}%'
        : _currency.format(coupon.discountValue);

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          // Code
          SizedBox(
            width: 130,
            child: Text(
              coupon.code,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                letterSpacing: 0.3,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Description
          SizedBox(
            width: 160,
            child: Text(
              coupon.description ?? '—',
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Type badge
          SizedBox(
            width: 90,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                typeLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: typeColor,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          // Value
          SizedBox(
            width: 80,
            child: Text(
              valueStr,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.right,
            ),
          ),

          // Min Order
          SizedBox(
            width: 90,
            child: Text(
              coupon.minOrderAmount != null
                  ? _currency.format(coupon.minOrderAmount)
                  : '—',
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
              textAlign: TextAlign.right,
            ),
          ),

          // Limit
          SizedBox(
            width: 60,
            child: Text(
              coupon.usageLimit?.toString() ?? '∞',
              style: TextStyle(
                  fontSize: 13, color: AppColors.textPrimary),
              textAlign: TextAlign.right,
            ),
          ),

          // Used
          SizedBox(
            width: 55,
            child: Text(
              '${coupon.usedCount}',
              style: TextStyle(
                fontSize: 13,
                color: coupon.isUsageLimitReached
                    ? AppColors.error
                    : AppColors.textPrimary,
                fontWeight: coupon.isUsageLimitReached
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
              textAlign: TextAlign.right,
            ),
          ),

          // Valid From
          SizedBox(
            width: 100,
            child: Text(
              coupon.validFrom != null
                  ? _dateFmt.format(coupon.validFrom!)
                  : '—',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
          ),

          // Valid To
          SizedBox(
            width: 100,
            child: Text(
              coupon.validTo != null
                  ? _dateFmt.format(coupon.validTo!)
                  : '—',
              style: TextStyle(
                fontSize: 12,
                color: coupon.isExpired
                    ? AppColors.error
                    : AppColors.textSecondary,
                fontWeight: coupon.isExpired
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ),

          // Status
          SizedBox(
            width: 100,
            child: _StatusBadge(coupon: coupon),
          ),

          // Actions
          SizedBox(
            width: 105,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: coupon.isActive,
                    onChanged: (_) => onToggle(),
                    activeThumbColor: AppColors.success,
                    materialTapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
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

// ── Status badge ───────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final Coupon coupon;
  const _StatusBadge({required this.coupon});

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color color;
    final Color bg;

    if (coupon.isExpired) {
      label = 'Expired';
      color = const Color(0xFFE53E3E);
      bg = const Color(0xFFFFF5F5);
    } else if (!coupon.isActive) {
      label = 'Inactive';
      color = const Color(0xFF718096);
      bg = const Color(0xFFF7FAFC);
    } else if (coupon.isUsageLimitReached) {
      label = 'Exhausted';
      color = const Color(0xFFDD6B20);
      bg = const Color(0xFFFEEBC8);
    } else {
      label = 'Active';
      color = const Color(0xFF38A169);
      bg = const Color(0xFFF0FFF4);
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
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
                fontSize: 11,
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
            Icons.local_offer_outlined,
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
              label: const Text('New Coupon'),
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary),
            ),
          ],
        ],
      ),
    );
  }
}
