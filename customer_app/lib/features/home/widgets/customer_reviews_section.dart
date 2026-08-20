import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/section_header.dart';
import '../services/home_service.dart';

// ── Section ───────────────────────────────────────────────────────────────────

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
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: SectionHeader(title: 'What Our Customers Say'),
        ),
        const SizedBox(height: 20),
        child,
      ],
    );
  }
}

// ── Horizontal row ────────────────────────────────────────────────────────────

const double _kCardW  = 300.0;
const double _kCardH  = 210.0;
const double _kGap    = 16.0;

class _ReviewRow extends StatelessWidget {
  final List<PublicReview> reviews;
  const _ReviewRow({required this.reviews});

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: _PointerScrollBehavior(),
      child: SizedBox(
        height: _kCardH + 16, // 16px shadow breathing room
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          itemCount: reviews.length,
          itemBuilder: (_, i) => Padding(
            padding:
                EdgeInsets.only(right: i < reviews.length - 1 ? _kGap : 0),
            child: _ReviewCard(review: reviews[i]),
          ),
        ),
      ),
    );
  }
}

// ── Review card: stars → quote → avatar+name ─────────────────────────────────

class _ReviewCard extends StatelessWidget {
  final PublicReview review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kCardW,
      height: _kCardH,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECE7DE), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stars
          _Stars(rating: review.rating),
          const SizedBox(height: 10),
          // Quote text
          Expanded(
            child: Text(
              review.reviewText,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: const Color(0xFF5A5550),
                height: 1.55,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Avatar + name row
          Row(
            children: [
              _Avatar(review: review),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  review.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A1714),
                  ),
                ),
              ),
            ],
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

// ── Stars ─────────────────────────────────────────────────────────────────────

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
          size: 14,
          color: AppColors.gold,
        );
      }),
    );
  }
}

// ── Skeleton ──────────────────────────────────────────────────────────────────

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kCardH + 16,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        itemCount: 3,
        itemBuilder: (_, i) => Container(
          width: _kCardW,
          height: _kCardH,
          margin: EdgeInsets.only(right: i < 2 ? _kGap : 0),
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
