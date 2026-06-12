import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/profile_model.dart';

class ProfileStatsCard extends StatelessWidget {
  final ProfileModel profile;

  const ProfileStatsCard({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _StatItem(
            icon: Icons.receipt_long_rounded,
            iconColor: AppColors.primary,
            value: profile.totalBookings.toString(),
            label: 'Total\nBookings',
            showDivider: true,
          ),
          _StatItem(
            icon: Icons.check_circle_rounded,
            iconColor: AppColors.success,
            value: profile.completedBookings.toString(),
            label: 'Completed\nServices',
            showDivider: true,
          ),
          _StatItem(
            icon: Icons.savings_rounded,
            iconColor: const Color(0xFFFF6D00),
            value: '₹${_formatAmount(profile.savedAmount)}',
            label: 'Amount\nSaved',
            showDivider: true,
          ),
          _StatItem(
            icon: Icons.favorite_rounded,
            iconColor: const Color(0xFFE91E63),
            value: profile.favouriteCount.toString(),
            label: 'Favourite\nServices',
            showDivider: false,
          ),
        ],
      ),
    );
  }

  String _formatAmount(double amount) {
    if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(1)}k';
    }
    return amount.toStringAsFixed(0);
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final bool showDivider;

  const _StatItem({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Expanded(
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: iconColor.withAlpha(18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 20, color: iconColor),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    value,
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: tt.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          if (showDivider)
            Container(width: 1, height: 52, color: AppColors.divider),
        ],
      ),
    );
  }
}
