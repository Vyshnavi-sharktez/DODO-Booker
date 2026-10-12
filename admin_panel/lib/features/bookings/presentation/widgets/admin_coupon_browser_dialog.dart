import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../coupons/application/providers/coupons_providers.dart';
import '../../../coupons/domain/models/coupon.dart';

final _priceFmt = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

String? adminValidateCoupon(
    Coupon c, double subtotal, List<String> cartNodeIds) {
  if (!c.isActive) return 'Coupon is inactive';
  final now = DateTime.now();
  if (c.validFrom != null && now.isBefore(c.validFrom!)) return 'Not valid yet';
  if (c.isExpired) return 'Coupon has expired';
  if (c.isUsageLimitReached) return 'Usage limit reached';
  if (c.applicabilityType != 'all' &&
      c.applicableNodeIds.isNotEmpty &&
      cartNodeIds.isNotEmpty) {
    final ok = cartNodeIds.any((id) => c.applicableNodeIds.contains(id));
    if (!ok) return 'Not applicable to selected services';
  }
  if (c.minOrderAmount != null && subtotal < c.minOrderAmount!) {
    return 'Min order ${_priceFmt.format(c.minOrderAmount!)}';
  }
  return null;
}

bool adminIsCouponCartApplicable(Coupon c, List<String> cartNodeIds) {
  if (c.applicabilityType == 'all' ||
      c.applicableNodeIds.isEmpty ||
      cartNodeIds.isEmpty) {
    return true;
  }
  return cartNodeIds.any((id) => c.applicableNodeIds.contains(id));
}

class AdminCouponBrowserDialog extends ConsumerStatefulWidget {
  final double subtotal;
  final List<String> cartNodeIds;
  final String? selectedCouponId;

  const AdminCouponBrowserDialog({
    super.key,
    required this.subtotal,
    required this.cartNodeIds,
    this.selectedCouponId,
  });

  @override
  ConsumerState<AdminCouponBrowserDialog> createState() =>
      _AdminCouponBrowserDialogState();
}

class _AdminCouponBrowserDialogState
    extends ConsumerState<AdminCouponBrowserDialog> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(couponsNotifierProvider.notifier).refresh(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(couponsNotifierProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 520,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  const Icon(Icons.local_offer_rounded,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Text(
                    'Available Coupons',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  if (state.isLoading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            state.when(
              loading: () => const Expanded(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Expanded(
                child: Center(
                  child: Text('Failed to load coupons: $e',
                      style:
                          const TextStyle(color: AppColors.textSecondary)),
                ),
              ),
              data: (allCoupons) {
                final coupons =
                    allCoupons.where((c) => c.isActive && !c.isExpired).toList();
                if (coupons.isEmpty) {
                  return const Expanded(
                    child: Center(
                      child: Text(
                        'No active coupons available',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  );
                }
                return Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: coupons.length,
                    separatorBuilder: (context, idx) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) {
                      final c = coupons[i];
                      return _CouponBrowserCard(
                        coupon: c,
                        subtotal: widget.subtotal,
                        cartNodeIds: widget.cartNodeIds,
                        isSelected: c.id == widget.selectedCouponId,
                        onApply: () => Navigator.of(ctx).pop(c),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CouponBrowserCard extends StatelessWidget {
  final Coupon coupon;
  final double subtotal;
  final List<String> cartNodeIds;
  final bool isSelected;
  final VoidCallback onApply;

  const _CouponBrowserCard({
    required this.coupon,
    required this.subtotal,
    required this.cartNodeIds,
    required this.isSelected,
    required this.onApply,
  });

  String _discountLabel() {
    if (coupon.discountType == 'percentage') {
      final pct = coupon.discountValue == coupon.discountValue.floorToDouble()
          ? coupon.discountValue.toInt().toString()
          : coupon.discountValue.toStringAsFixed(1);
      final cap = coupon.maxDiscountAmount != null
          ? ' (up to ${_priceFmt.format(coupon.maxDiscountAmount!)})'
          : '';
      return '$pct% off$cap';
    }
    return '${_priceFmt.format(coupon.discountValue)} off';
  }

  String _expiryLabel() {
    if (coupon.validTo == null) return 'No expiry';
    final d = coupon.validTo!;
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return 'Expires ${d.day} ${m[d.month - 1]} ${d.year}';
  }

  Color _expiryColor() {
    if (coupon.validTo == null) return AppColors.textSecondary;
    final days = coupon.validTo!.difference(DateTime.now()).inDays;
    if (days <= 3) return AppColors.error;
    if (days <= 7) return AppColors.warning;
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final validationError = adminValidateCoupon(coupon, subtotal, cartNodeIds);
    final isApplicable = validationError == null;
    final isCartApplicable = adminIsCouponCartApplicable(coupon, cartNodeIds);
    final isNotForCart = !isCartApplicable;
    final hasOtherError = !isApplicable && isCartApplicable;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.primary.withValues(alpha: 0.05)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.4)
              : AppColors.border,
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.primaryLight.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    coupon.code,
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _discountLabel(),
                    style: const TextStyle(
                      color: AppColors.success,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                if (isSelected)
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: AppColors.success, size: 14),
                      SizedBox(width: 4),
                      Text('Applied',
                          style: TextStyle(
                              color: AppColors.success,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ],
                  )
                else
                  SizedBox(
                    height: 28,
                    child: FilledButton(
                      onPressed: isApplicable ? onApply : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        disabledBackgroundColor: AppColors.border,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        minimumSize: Size.zero,
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      child: const Text('Apply'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  isNotForCart
                      ? Icons.cancel_outlined
                      : Icons.check_circle_outline_rounded,
                  size: 13,
                  color: isNotForCart ? AppColors.error : AppColors.success,
                ),
                const SizedBox(width: 4),
                Text(
                  coupon.applicabilityType == 'all' ||
                          coupon.applicableNodeIds.isEmpty
                      ? 'Valid on all services'
                      : isCartApplicable
                          ? 'Applicable to selected services'
                          : 'Not applicable for selected services',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isNotForCart ? AppColors.error : AppColors.success,
                  ),
                ),
              ],
            ),
            if (coupon.description?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(coupon.description!,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if (coupon.minOrderAmount != null)
                  _CouponMeta(
                    icon: Icons.shopping_bag_outlined,
                    label: 'Min ${_priceFmt.format(coupon.minOrderAmount!)}',
                    color: AppColors.textSecondary,
                  ),
                _CouponMeta(
                  icon: Icons.calendar_today_rounded,
                  label: _expiryLabel(),
                  color: _expiryColor(),
                ),
                if (hasOtherError)
                  _CouponMeta(
                    icon: Icons.info_outline_rounded,
                    label: validationError,
                    color: AppColors.warning,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CouponMeta extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _CouponMeta({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}
