import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/service_model.dart';

class ServiceInfoSection extends StatelessWidget {
  final ServiceModel service;

  const ServiceInfoSection({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Breadcrumb
          if (service.categoryName != null)
            Text(
              service.categoryName!.toUpperCase(),
              style: tt.labelSmall?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          const SizedBox(height: 6),
          // Service name
          Text(
            service.name,
            style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          // Stat chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (service.durationMinutes != null)
                _Chip(
                  icon: Icons.schedule_rounded,
                  label: _formatDuration(service.durationMinutes!),
                  color: AppColors.primary,
                ),
              _Chip(
                icon: Icons.star_rounded,
                label: service.rating.toStringAsFixed(1),
                color: AppColors.warning,
              ),
              _Chip(
                icon: Icons.rate_review_rounded,
                label: '${_formatCount(service.reviewCount)} reviews',
                color: AppColors.success,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}min';
  }

  String _formatCount(int count) {
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return '$count';
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Chip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
