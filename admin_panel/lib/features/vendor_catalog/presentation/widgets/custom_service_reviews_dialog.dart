import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../vendor_service_requests/data/vendor_service_requests_repository.dart';

class CustomServiceReviewsDialog extends StatefulWidget {
  const CustomServiceReviewsDialog({
    super.key,
    required this.customServiceId,
    required this.serviceName,
  });

  final String customServiceId;
  final String serviceName;

  static Future<void> show(
    BuildContext context, {
    required String customServiceId,
    required String serviceName,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => CustomServiceReviewsDialog(
        customServiceId: customServiceId,
        serviceName: serviceName,
      ),
    );
  }

  @override
  State<CustomServiceReviewsDialog> createState() =>
      _CustomServiceReviewsDialogState();
}

class _CustomServiceReviewsDialogState
    extends State<CustomServiceReviewsDialog> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = VendorServiceRequestsRepository(Supabase.instance.client)
        .fetchReviewsForCustomService(widget.customServiceId);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(maxWidth: 580, maxHeight: 620),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.star_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Customer Reviews',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700),
                        ),
                        Text(
                          widget.serviceName,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
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

            // ── Body ────────────────────────────────────────────────────
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Failed to load reviews: ${snap.error}',
                          style: const TextStyle(
                              color: AppColors.error, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  final reviews = snap.data ?? [];
                  if (reviews.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_border_rounded,
                              size: 52, color: AppColors.textSecondary),
                          SizedBox(height: 12),
                          Text('No reviews yet',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondary)),
                          SizedBox(height: 4),
                          Text('Reviews will appear here once customers rate this service.',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary),
                              textAlign: TextAlign.center),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: reviews.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (_, i) =>
                        _ReviewTile(review: reviews[i]),
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

// ── Review tile ───────────────────────────────────────────────────────────────

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});
  final Map<String, dynamic> review;

  @override
  Widget build(BuildContext context) {
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final text = review['review_text'] as String? ?? '';
    final createdAt = review['created_at'] as String?;
    final customer =
        review['customers'] as Map<String, dynamic>?;
    final customerName = customer?['full_name'] as String? ?? 'Customer';
    final date = createdAt != null
        ? _formatDate(DateTime.parse(createdAt).toLocal())
        : '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Stars
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (i) {
                  return Icon(
                    i < rating
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 16,
                    color: const Color(0xFFF4A81D),
                  );
                }),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  customerName,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                date,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              text,
              style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}
