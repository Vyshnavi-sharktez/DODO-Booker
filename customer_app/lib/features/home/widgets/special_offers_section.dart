import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/section_header.dart';
import '../../../models/coupon_model.dart';
import 'coupon_carousel.dart';

class SpecialOffersSection extends StatelessWidget {
  final AsyncValue<List<CouponModel>> asyncCoupons;
  final VoidCallback? onViewAll;

  const SpecialOffersSection({
    super.key,
    required this.asyncCoupons,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final body = asyncCoupons.when(
      loading: () => const _LoadingSkeleton(),
      error: (_, __) => const _EmptyState(),
      data: (coupons) => coupons.isEmpty
          ? const _EmptyState()
          : CouponCarousel(coupons: coupons),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SectionHeader(title: 'Special Offers', onSeeAll: onViewAll),
        ),
        const SizedBox(height: 16),
        body,
      ],
    );
  }
}

// ── Loading shimmer ──────────────────────────────────────────────────────────────

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final vw = constraints.maxWidth;
        final h = vw < 480 ? 340.0 : (vw < 768 ? 265.0 : 295.0);
        final hPad = (vw * 0.06).clamp(20.0, 56.0);
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad),
          child: Container(
            height: h,
            decoration: BoxDecoration(
              color: AppColors.shimmerBase,
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        );
      },
    );
  }
}

// ── Empty / error state ──────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hPad = (constraints.maxWidth * 0.06).clamp(20.0, 56.0);
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 36),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: const Center(
              child: Text(
                'No active offers available.',
                style: TextStyle(
                  color: AppColors.textHint,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
