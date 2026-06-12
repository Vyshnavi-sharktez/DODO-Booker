import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/category_model.dart';

class CategoryCard extends StatelessWidget {
  final CategoryModel category;
  final int colorIndex;
  final VoidCallback onTap;

  const CategoryCard({
    super.key,
    required this.category,
    required this.colorIndex,
    required this.onTap,
  });

  // ── Color palettes ──────────────────────────────────────────────────────────

  static const _bgColors = [
    Color(0xFFE8F0FE),
    Color(0xFFFFF3E0),
    Color(0xFFE8F5E9),
    Color(0xFFFCE4EC),
    Color(0xFFEDE7F6),
    Color(0xFFE0F7FA),
    Color(0xFFFFF8E1),
    Color(0xFFF3E5F5),
  ];

  static const _iconBgColors = [
    Color(0xFFD2E3FC),
    Color(0xFFFFE0B2),
    Color(0xFFC8E6C9),
    Color(0xFFF8BBD0),
    Color(0xFFD1C4E9),
    Color(0xFFB2EBF2),
    Color(0xFFFFECB3),
    Color(0xFFE1BEE7),
  ];

  static const _iconColors = [
    Color(0xFF1565C0),
    Color(0xFFE65100),
    Color(0xFF2E7D32),
    Color(0xFFC62828),
    Color(0xFF4527A0),
    Color(0xFF00838F),
    Color(0xFFF57F17),
    Color(0xFF6A1B9A),
  ];

  // ── Icon resolver ───────────────────────────────────────────────────────────

  IconData _resolveIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('clean')) return Icons.cleaning_services;
    if (n.contains('plumb')) return Icons.plumbing;
    if (n.contains('electr')) return Icons.electrical_services;
    if (n.contains('paint')) return Icons.format_paint;
    if (n.contains('carpen')) return Icons.build;
    if (n.contains('pest')) return Icons.bug_report;
    if (n.contains('appli')) return Icons.kitchen;
    if (n.contains('shift') || n.contains('moving')) return Icons.local_shipping;
    if (n.contains('salon') || n.contains('beauty')) return Icons.content_cut;
    if (n.contains('garden')) return Icons.yard;
    if (n.contains('laundry')) return Icons.local_laundry_service;
    return Icons.home_repair_service;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final idx = colorIndex % _bgColors.length;
    final icon = _resolveIcon(category.name);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: _bgColors[idx],
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _iconBgColors[idx],
            width: 1.2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon container
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _iconBgColors[idx],
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: _iconColors[idx], size: 32),
            ),

            const SizedBox(height: 12),

            // Category name
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                category.name,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            const SizedBox(height: 4),

            // Service count badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: _iconColors[idx].withAlpha(20),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${category.serviceCount} services',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: _iconColors[idx],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
