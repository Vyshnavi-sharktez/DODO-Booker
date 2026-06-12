import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/service_model.dart';
import '../models/wishlist_item_model.dart';

class WishlistItemCard extends StatelessWidget {
  final WishlistItemModel item;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const WishlistItemCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final service = item.service;
    final tt = Theme.of(context).textTheme;
    final color = _colorForService(service.id);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Service icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_iconForService(service), color: color, size: 28),
              ),
              const SizedBox(width: 12),
              // Service info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.name,
                      style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (service.categoryName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        service.categoryName!,
                        style: tt.labelSmall?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          '₹${service.startingPrice.toInt()}',
                          style: tt.bodySmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          ' onwards',
                          style: tt.labelSmall?.copyWith(
                            color: AppColors.textHint,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(
                          Icons.star_rounded,
                          size: 12,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          service.rating.toStringAsFixed(1),
                          style: tt.labelSmall?.copyWith(color: AppColors.textHint),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Remove (filled heart)
              IconButton(
                icon: const Icon(
                  Icons.favorite_rounded,
                  color: Color(0xFFE91E63),
                ),
                onPressed: onRemove,
                tooltip: 'Remove from wishlist',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _palette = [
  AppColors.primary,
  AppColors.secondary,
  Color(0xFF34A853),
  Color(0xFF9C27B0),
  Color(0xFFFF5722),
  Color(0xFF00ACC1),
  Color(0xFFF4511E),
  Color(0xFF0F9D58),
];

Color _colorForService(String id) {
  final hash = id.codeUnits.fold(0, (a, b) => a + b);
  return _palette[hash % _palette.length];
}

IconData _iconForService(ServiceModel s) {
  final name = s.name.toLowerCase();
  final sub = (s.subcategoryName ?? '').toLowerCase();
  final cat = (s.categoryName ?? '').toLowerCase();
  if (name.contains('clean') || cat.contains('clean')) return Icons.cleaning_services_rounded;
  if (name.contains('ac') || sub.contains('ac')) return Icons.ac_unit_rounded;
  if (name.contains('plumb') || sub.contains('tap') || sub.contains('pipe')) return Icons.plumbing_rounded;
  if (name.contains('electric') || sub.contains('fan') || sub.contains('wiring')) return Icons.electrical_services_rounded;
  if (name.contains('paint')) return Icons.format_paint_rounded;
  if (name.contains('pest') || sub.contains('cockroach') || sub.contains('termite')) return Icons.bug_report_rounded;
  if (name.contains('shift') || sub.contains('shifting') || cat.contains('shift')) return Icons.local_shipping_rounded;
  if (name.contains('carpen') || sub.contains('furniture')) return Icons.chair_rounded;
  return Icons.home_repair_service_rounded;
}
