import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/subcategory_model.dart';

class SubcategoryCard extends StatelessWidget {
  final SubcategoryModel subcategory;
  final int colorIndex;
  final VoidCallback onTap;

  const SubcategoryCard({
    super.key,
    required this.subcategory,
    required this.colorIndex,
    required this.onTap,
  });

  static const _bgColors = [
    Color(0xFFF0F4FF),
    Color(0xFFFFF8F0),
    Color(0xFFF0FAF1),
    Color(0xFFFFF0F3),
    Color(0xFFF5F0FF),
    Color(0xFFF0FBFC),
    Color(0xFFFFFBF0),
    Color(0xFFFBF0FF),
  ];

  static const _accentColors = [
    Color(0xFF1A73E8),
    Color(0xFFFF6D00),
    Color(0xFF34A853),
    Color(0xFFEA4335),
    Color(0xFF9C27B0),
    Color(0xFF00BCD4),
    Color(0xFFFFC107),
    Color(0xFF673AB7),
  ];

  IconData _resolveIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('deep clean') || n.contains('home clean')) return Icons.cleaning_services;
    if (n.contains('kitchen')) return Icons.kitchen;
    if (n.contains('bathroom') || n.contains('bath')) return Icons.bathtub;
    if (n.contains('sofa') || n.contains('carpet')) return Icons.chair;
    if (n.contains('window')) return Icons.window;
    if (n.contains('tap') || n.contains('faucet')) return Icons.water;
    if (n.contains('pipe')) return Icons.plumbing;
    if (n.contains('drain')) return Icons.water_drop;
    if (n.contains('heater') || n.contains('geyser')) return Icons.hot_tub;
    if (n.contains('fan')) return Icons.wind_power;
    if (n.contains('wiring') || n.contains('wire')) return Icons.cable;
    if (n.contains('switch')) return Icons.electric_bolt;
    if (n.contains('cctv') || n.contains('security')) return Icons.security;
    if (n.contains('inverter') || n.contains('ups')) return Icons.battery_charging_full;
    if (n.contains('wall paint')) return Icons.format_paint;
    if (n.contains('door') || n.contains('window paint')) return Icons.door_back_door;
    if (n.contains('exterior')) return Icons.house;
    if (n.contains('waterproof')) return Icons.water_damage;
    if (n.contains('furniture')) return Icons.chair_alt;
    if (n.contains('cabinet')) return Icons.shelves;
    if (n.contains('ceiling')) return Icons.roofing;
    if (n.contains('cockroach')) return Icons.bug_report;
    if (n.contains('termite')) return Icons.pest_control;
    if (n.contains('bed bug')) return Icons.bedtime;
    if (n.contains('ac') || n.contains('air')) return Icons.ac_unit;
    if (n.contains('washing')) return Icons.local_laundry_service;
    if (n.contains('refriger') || n.contains('fridge')) return Icons.kitchen;
    if (n.contains('tv') || n.contains('display')) return Icons.tv;
    if (n.contains('microwave') || n.contains('oven')) return Icons.microwave;
    if (n.contains('home shift') || n.contains('house shift')) return Icons.home;
    if (n.contains('office shift')) return Icons.business;
    if (n.contains('vehicle') || n.contains('car') || n.contains('bike')) return Icons.directions_car;
    if (n.contains('packing')) return Icons.inventory_2;
    return Icons.home_repair_service;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final idx = colorIndex % _bgColors.length;
    final accent = _accentColors[idx];
    final bg = _bgColors[idx];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 0.8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x06000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon area
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_resolveIcon(subcategory.name), color: accent, size: 24),
            ),

            const SizedBox(height: 10),

            // Name
            Text(
              subcategory.name,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            // Description
            if (subcategory.description != null) ...[
              const SizedBox(height: 3),
              Text(
                subcategory.description!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textHint,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            const Spacer(),

            // Service count row
            Row(
              children: [
                Icon(Icons.bolt_rounded, size: 13, color: accent),
                const SizedBox(width: 3),
                Text(
                  '${subcategory.serviceCount} services',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
