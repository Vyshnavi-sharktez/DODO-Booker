import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_modal_dialog.dart';
import '../models/review_model.dart';
import '../services/review_providers.dart';

class ReviewModal extends ConsumerStatefulWidget {
  final String bookingId;
  final String serviceName;

  const ReviewModal({
    super.key,
    required this.bookingId,
    required this.serviceName,
  });

  @override
  ConsumerState<ReviewModal> createState() => _ReviewModalState();
}

class _ReviewModalState extends ConsumerState<ReviewModal> {
  int _selectedRating = 0;
  final _textController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reviewAsync = ref.watch(bookingReviewProvider(widget.bookingId));

    return AppModalDialog(
      title: 'Rate Your Service',
      subtitle: Text(widget.serviceName),
      child: reviewAsync.when(
        loading: () => const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => _ErrorBody(message: '$e'),
        data: (existing) => existing != null
            ? _ExistingReviewBody(review: existing)
            : _ReviewForm(
                selectedRating: _selectedRating,
                controller: _textController,
                isSubmitting: _isSubmitting,
                onRatingChanged: (r) => setState(() => _selectedRating = r),
                onSubmit: () => _submit(),
              ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_selectedRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a star rating')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref.read(reviewServiceProvider).submitReview(
            bookingId: widget.bookingId,
            rating: _selectedRating,
            reviewText: _textController.text,
          );
      ref.invalidate(bookingReviewProvider(widget.bookingId));
      ref.invalidate(reviewsForServiceProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Review submitted successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

// ── Form for new review ────────────────────────────────────────────────────────

class _ReviewForm extends StatelessWidget {
  final int selectedRating;
  final TextEditingController controller;
  final bool isSubmitting;
  final ValueChanged<int> onRatingChanged;
  final VoidCallback onSubmit;

  const _ReviewForm({
    required this.selectedRating,
    required this.controller,
    required this.isSubmitting,
    required this.onRatingChanged,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Star selector
        Text(
          'Your Rating',
          style: tt.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: List.generate(5, (i) {
            final filled = i < selectedRating;
            return GestureDetector(
              onTap: () => onRatingChanged(i + 1),
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  filled ? Icons.star_rounded : Icons.star_border_rounded,
                  color: AppColors.warning,
                  size: 38,
                ),
              ),
            );
          }),
        ),
        if (selectedRating > 0) ...[
          const SizedBox(height: 4),
          Text(
            _label(selectedRating),
            style: tt.bodySmall?.copyWith(color: AppColors.warning),
          ),
        ],
        const SizedBox(height: 16),
        // Review text
        Text(
          'Your Review',
          style: tt.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(
            hintText: 'Share your experience…',
            counterText: '',
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: isSubmitting ? null : onSubmit,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          child: isSubmitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Submit Review'),
        ),
      ],
    );
  }

  String _label(int r) => const [
        '', 'Poor', 'Fair', 'Good', 'Very Good', 'Excellent'
      ][r];
}

// ── Read-only view for existing review ────────────────────────────────────────

class _ExistingReviewBody extends StatelessWidget {
  final ReviewModel review;

  const _ExistingReviewBody({required this.review});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final d = review.createdAt;
    final date = '${d.day} ${months[d.month - 1]} ${d.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Star display
        Row(
          children: List.generate(5, (i) {
            return Icon(
              i < review.rating ? Icons.star_rounded : Icons.star_border_rounded,
              color: AppColors.warning,
              size: 30,
            );
          }),
        ),
        const SizedBox(height: 4),
        Text(date, style: tt.labelSmall?.copyWith(color: AppColors.textHint)),
        const SizedBox(height: 12),
        if (review.reviewText.isNotEmpty)
          Text(
            review.reviewText,
            style: tt.bodyMedium?.copyWith(color: AppColors.textPrimary, height: 1.5),
          ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.success.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline_rounded,
                  size: 16, color: AppColors.success),
              const SizedBox(width: 6),
              Text(
                'You have already reviewed this service',
                style: tt.labelSmall?.copyWith(color: AppColors.success),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String message;

  const _ErrorBody({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          'Error: $message',
          style: const TextStyle(color: AppColors.error),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
