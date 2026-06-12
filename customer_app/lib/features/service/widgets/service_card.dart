import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/service_model.dart';
import '../../wishlist/widgets/heart_button.dart';

class ServiceCard extends StatelessWidget {
  final ServiceModel service;
  final VoidCallback onTap;

  const ServiceCard({super.key, required this.service, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final color = _colorForService(service.id);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Stack(
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 100,
              child: Row(
                children: [
                  // Colored icon block
                  Container(
                    width: 96,
                    decoration: BoxDecoration(
                      color: color.withAlpha(30),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                      ),
                    ),
                    child: Icon(_iconForService(service), color: color, size: 36),
                  ),
                  // Content
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            service.name,
                            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          if (service.subcategoryName != null)
                            Text(
                              service.subcategoryName!,
                              style: tt.labelSmall?.copyWith(color: AppColors.textSecondary),
                            ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              if (service.durationMinutes != null) ...[
                                const Icon(Icons.schedule_rounded, size: 12, color: AppColors.textHint),
                                const SizedBox(width: 3),
                                Text(
                                  '${service.durationMinutes} min',
                                  style: tt.labelSmall?.copyWith(color: AppColors.textHint),
                                ),
                                const SizedBox(width: 10),
                              ],
                              const Icon(Icons.star_rounded, size: 12, color: AppColors.warning),
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
                  ),
                  // Price + arrow (right-padded to leave room for heart overlay)
                  Padding(
                    padding: const EdgeInsets.only(right: 44),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₹${service.startingPrice.toInt()}',
                          style: tt.titleSmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'onwards',
                          style: tt.labelSmall?.copyWith(color: AppColors.textHint, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Heart button overlay — top-right corner
          Positioned(
            top: 2,
            right: 2,
            child: HeartButton(serviceId: service.id),
          ),
        ],
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
