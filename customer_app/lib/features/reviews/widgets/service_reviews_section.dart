import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../models/review_model.dart';
import '../services/review_providers.dart';

class ServiceReviewsSection extends ConsumerWidget {
  final String serviceId;
  /// Whether to render the built-in "Reviews" sub-heading with avg rating.
  /// Pass false when the parent already provides its own section heading.
  final bool showHeader;
  /// Flat mode: no card borders, horizontal dividers between reviews.
  /// Use in contexts that want a minimal in-page list (e.g. CatalogNodeModal).
  final bool flat;

  const ServiceReviewsSection({
    super.key,
    required this.serviceId,
    this.showHeader = true,
    this.flat = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(reviewsForServiceProvider(serviceId));

    return reviewsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (reviews) {
        if (reviews.isEmpty) return const SizedBox.shrink();

        final avg = reviews.map((r) => r.rating).reduce((a, b) => a + b) /
            reviews.length;

        final items = <Widget>[];

        if (showHeader) {
          items.add(_ReviewsHeader(avgRating: avg, count: reviews.length));
        }

        if (flat) {
          for (int i = 0; i < reviews.length; i++) {
            items.add(_FlatReviewTile(review: reviews[i]));
            if (i < reviews.length - 1) {
              items.add(const Divider(height: 1, thickness: 0.8));
            }
          }
        } else {
          items.addAll(reviews.map((r) => _ReviewTile(review: r)));
        }

        items.add(const SizedBox(height: 8));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: items,
        );
      },
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final ReviewModel review;

  const _ReviewTile({required this.review});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final d = review.createdAt;
    final date = '${d.day} ${months[d.month - 1]} ${d.year}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant.withOpacity(0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    review.customerName?.isNotEmpty == true
                        ? review.customerName!
                        : 'Customer',
                    style: tt.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  children: List.generate(5, (i) {
                    return Icon(
                      i < review.rating
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: AppColors.warning,
                      size: 15,
                    );
                  }),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              date,
              style: tt.labelSmall?.copyWith(color: AppColors.textHint),
            ),
            if (review.reviewText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                review.reviewText,
                textAlign: TextAlign.left,
                style: tt.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Flat variant — used inside CatalogNodeModal (no card border, divider between items)
class _FlatReviewTile extends StatelessWidget {
  final ReviewModel review;

  const _FlatReviewTile({required this.review});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final d = review.createdAt;
    final date = '${d.day} ${months[d.month - 1]} ${d.year}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Row(
                children: List.generate(5, (i) {
                  return Icon(
                    i < review.rating
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: AppColors.warning,
                    size: 15,
                  );
                }),
              ),
              const Spacer(),
              Text(
                date,
                style: tt.labelSmall?.copyWith(color: AppColors.textHint),
              ),
            ],
          ),
          if (review.reviewText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              review.reviewText,
              style: tt.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
