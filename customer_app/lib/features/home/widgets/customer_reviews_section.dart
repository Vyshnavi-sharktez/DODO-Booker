import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/section_header.dart';
import '../services/home_service.dart';

class CustomerReviewsSection extends StatelessWidget {
  final AsyncValue<List<PublicReview>> asyncReviews;

  const CustomerReviewsSection({super.key, required this.asyncReviews});

  @override
  Widget build(BuildContext context) {
    return asyncReviews.when(
      loading: () => _section(child: const _SkeletonRow()),
      error: (_, _) => const SizedBox.shrink(),
      data: (reviews) => reviews.isEmpty
          ? const SizedBox.shrink()
          : _section(child: _ReviewRow(reviews: reviews)),
    );
  }

  Widget _section({required Widget child}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: SectionHeader(title: 'What Our Customers Say'),
        ),
        const SizedBox(height: 16),
        child,
      ],
    );
  }
}

// ── Horizontal row ────────────────────────────────────────────────────────────

class _ReviewRow extends StatelessWidget {
  final List<PublicReview> reviews;
  const _ReviewRow({required this.reviews});

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: _PointerScrollBehavior(),
      child: SizedBox(
        height: 172,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          itemCount: reviews.length,
          itemBuilder: (_, i) => Padding(
            padding: EdgeInsets.only(right: i < reviews.length - 1 ? 12 : 0),
            child: _ReviewCard(review: reviews[i]),
          ),
        ),
      ),
    );
  }
}

// ── Review card ───────────────────────────────────────────────────────────────

class _ReviewCard extends StatelessWidget {
  final PublicReview review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      width: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x07000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(review: review),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.customerName,
                      style: tt.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    _Stars(rating: review.rating),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Text(
              review.reviewText,
              style: tt.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Avatar ────────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final PublicReview review;
  const _Avatar({required this.review});

  @override
  Widget build(BuildContext context) {
    if (review.customerAvatarUrl != null &&
        review.customerAvatarUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          review.customerAvatarUrl!,
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _InitialsAvatar(review: review),
        ),
      );
    }
    return _InitialsAvatar(review: review);
  }
}

class _InitialsAvatar extends StatelessWidget {
  final PublicReview review;
  const _InitialsAvatar({required this.review});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        color: AppColors.goldLight,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        review.initials,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.gold,
        ),
      ),
    );
  }
}

// ── Star row ──────────────────────────────────────────────────────────────────

class _Stars extends StatelessWidget {
  final int rating;
  const _Stars({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        return Icon(
          i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
          size: 12,
          color: AppColors.gold,
        );
      }),
    );
  }
}

// ── Loading skeleton ──────────────────────────────────────────────────────────

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 172,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        itemCount: 3,
        itemBuilder: (_, i) => Container(
          width: 260,
          height: 160,
          margin: EdgeInsets.only(right: i < 2 ? 12 : 0),
          decoration: BoxDecoration(
            color: AppColors.shimmerBase,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

// ── Scroll behavior ───────────────────────────────────────────────────────────

class _PointerScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  Widget buildScrollbar(context, child, details) => child;
}
