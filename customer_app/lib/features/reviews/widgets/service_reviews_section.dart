import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../models/review_model.dart';
import '../services/review_providers.dart';

class ServiceReviewsSection extends ConsumerWidget {
  final String serviceId;

  const ServiceReviewsSection({super.key, required this.serviceId});

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

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ReviewsHeader(avgRating: avg, count: reviews.length),
            ...reviews.map((r) => _ReviewTile(review: r)),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

class _ReviewsHeader extends StatelessWidget {
  final double avgRating;
  final int count;

  const _ReviewsHeader({required this.avgRating, required this.count});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Row(
        children: [
          Text(
            'Reviews',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          const Icon(Icons.star_rounded, color: AppColors.warning, size: 18),
          const SizedBox(width: 4),
          Text(
            avgRating.toStringAsFixed(1),
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            ' ($count)',
            style: tt.bodySmall?.copyWith(color: AppColors.textHint),
          ),
        ],
      ),
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
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final d = review.createdAt;
    final date = '${d.day} ${months[d.month - 1]} ${d.year}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Star row
                  Row(
                    children: List.generate(5, (i) {
                      return Icon(
                        i < review.rating
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: AppColors.warning,
                        size: 16,
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
                const SizedBox(height: 8),
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
        ),
      ),
    );
  }
}
