import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/coupon_model.dart';
import '../services/coupon_providers.dart';

/// Bottom sheet for coupon discovery.
/// Pops with the selected [CouponModel] via Navigator.pop(coupon).
class AvailableCouponsSheet extends ConsumerStatefulWidget {
  final double subtotal;
  final CouponModel? selectedCoupon;

  const AvailableCouponsSheet({
    super.key,
    required this.subtotal,
    this.selectedCoupon,
  });

  @override
  ConsumerState<AvailableCouponsSheet> createState() =>
      _AvailableCouponsSheetState();
}

class _AvailableCouponsSheetState
    extends ConsumerState<AvailableCouponsSheet> {
  bool _loggedLoaded = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[DODO][Coupon] Loading coupons');
  }

  List<CouponModel> _sorted(List<CouponModel> coupons) {
    final list = List<CouponModel>.from(coupons);
    list.sort((a, b) {
      // Primary: highest calculated discount first
      final da = a.calculateDiscount(widget.subtotal);
      final db = b.calculateDiscount(widget.subtotal);
      if (db != da) return db.compareTo(da);
      // Secondary: nearest expiry first; null (no expiry) goes last
      if (a.validTo == null && b.validTo == null) return 0;
      if (a.validTo == null) return 1;
      if (b.validTo == null) return -1;
      return a.validTo!.compareTo(b.validTo!);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final couponsAsync = ref.watch(activeCouponsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.60,
      minChildSize: 0.40,
      maxChildSize: 0.88,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Drag handle ────────────────────────────────────────────────
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 2),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── Header ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.local_offer_rounded,
                    size: 20,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Available Coupons',
                    style: tt.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: IconButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // ── Body ───────────────────────────────────────────────────────
            Expanded(
              child: couponsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 44,
                          color: AppColors.error,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Could not load coupons',
                          style: tt.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () =>
                              ref.invalidate(activeCouponsProvider),
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (all) {
                  if (!_loggedLoaded) {
                    _loggedLoaded = true;
                    debugPrint(
                        '[DODO][Coupon] Coupons loaded: ${all.length}');
                  }
                  final sorted = _sorted(all);
                  if (sorted.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.local_offer_outlined,
                              size: 52,
                              color: AppColors.textHint,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'No coupons available',
                              style: tt.bodyLarge?.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Check back later for offers.',
                              style: tt.bodySmall
                                  ?.copyWith(color: AppColors.textHint),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    itemCount: sorted.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final c = sorted[i];
                      return _CouponCard(
                        coupon: c,
                        subtotal: widget.subtotal,
                        isSelected: widget.selectedCoupon?.id == c.id,
                        onApply: () {
                          debugPrint(
                              '[DODO][Coupon] Coupon selected: ${c.code}');
                          Navigator.of(ctx).pop(c);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Coupon card ────────────────────────────────────────────────────────────────

class _CouponCard extends StatelessWidget {
  final CouponModel coupon;
  final double subtotal;
  final bool isSelected;
  final VoidCallback onApply;

  const _CouponCard({
    required this.coupon,
    required this.subtotal,
    required this.isSelected,
    required this.onApply,
  });

  Color _expiryColor() {
    if (coupon.validTo == null) return AppColors.textSecondary;
    final days = coupon.validTo!.difference(DateTime.now()).inDays;
    if (days <= 3) return AppColors.error;
    if (days <= 7) return AppColors.warning;
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final validationError = coupon.validate(subtotal);
    final isApplicable = validationError == null;
    final discount = coupon.calculateDiscount(subtotal);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.primary.withAlpha(13)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? AppColors.primary.withAlpha(120)
              : AppColors.border,
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: code + discount label + apply/applied ─────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Code badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    coupon.code,
                    style: tt.labelMedium?.copyWith(
                      color: isSelected ? Colors.white : AppColors.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Discount label
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success.withAlpha(25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    coupon.discountLabel,
                    style: tt.labelSmall?.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                // Apply / Applied indicator
                if (isSelected)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          color: AppColors.success, size: 15),
                      const SizedBox(width: 4),
                      Text(
                        'Applied',
                        style: tt.labelSmall?.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  )
                else
                  SizedBox(
                    height: 30,
                    child: FilledButton(
                      onPressed: isApplicable ? onApply : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        disabledBackgroundColor:
                            AppColors.border,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 14),
                        minimumSize: Size.zero,
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      child: const Text('Apply'),
                    ),
                  ),
              ],
            ),

            // ── Description ───────────────────────────────────────────────
            if (coupon.description != null &&
                coupon.description!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                coupon.description!,
                style: tt.bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],

            const SizedBox(height: 8),

            // ── Meta row ──────────────────────────────────────────────────
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if (isApplicable && discount > 0)
                  _MetaItem(
                    icon: Icons.savings_rounded,
                    label: 'Save ₹${discount.toStringAsFixed(0)}',
                    color: AppColors.success,
                  ),
                if (coupon.minOrderAmount != null)
                  _MetaItem(
                    icon: Icons.shopping_bag_outlined,
                    label:
                        'Min ₹${coupon.minOrderAmount!.toStringAsFixed(0)}',
                    color: AppColors.textSecondary,
                  ),
                _MetaItem(
                  icon: Icons.calendar_today_rounded,
                  label: coupon.expiryLabel,
                  color: _expiryColor(),
                ),
                if (!isApplicable)
                  _MetaItem(
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

// ── Meta item ──────────────────────────────────────────────────────────────────

class _MetaItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MetaItem({
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
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: color),
        ),
      ],
    );
  }
}
