import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/service_model.dart';

class ServiceInfoSection extends StatelessWidget {
  final ServiceModel service;

  const ServiceInfoSection({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category badge pill
          if (service.categoryName != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                service.categoryName!,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          const SizedBox(height: 10),

          // Service name
          Text(
            service.name,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),

          // Star rating + review count
          Row(
            children: [
              const Icon(Icons.star_rounded, size: 16, color: AppColors.gold),
              const SizedBox(width: 4),
              Text(
                service.rating.toStringAsFixed(1),
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.gold,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '(${_formatCount(service.reviewCount)} reviews)',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),

          // Description
          if (service.description != null && service.description!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              service.description!,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.55,
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Price row
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'From',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF9A948C),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _formatPrice(service.startingPrice),
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return '$count';
  }

  String _formatPrice(double price) {
    if (price == price.roundToDouble()) return '₹${price.toInt()}';
    return '₹${price.toStringAsFixed(2)}';
  }
}
