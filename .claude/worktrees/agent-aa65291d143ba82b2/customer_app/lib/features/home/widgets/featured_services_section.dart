import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/section_header.dart';
import '../../../models/service_model.dart';

class FeaturedServicesSection extends StatelessWidget {
  final AsyncValue<List<ServiceModel>> asyncServices;

  const FeaturedServicesSection({super.key, required this.asyncServices});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SectionHeader(
            title: 'Featured Services',
            onSeeAll: () {
              // TODO: navigate to all services
            },
          ),
        ),
        const SizedBox(height: 14),
        asyncServices.when(
          loading: () => const _ServicesSkeleton(),
          error: (_, _) => const _ServicesError(),
          data: (services) {
            if (services.isEmpty) return const _ServicesEmpty();
            return _ServicesHorizontalList(services: services);
          },
        ),
      ],
    );
  }
}

// ── Horizontal scrolling list ─────────────────────────────────────────────────

class _ServicesHorizontalList extends StatelessWidget {
  final List<ServiceModel> services;
  const _ServicesHorizontalList({required this.services});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 224,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: services.length,
        itemBuilder: (context, index) => _ServiceCard(
          service: services[index],
          colorIndex: index,
        ),
      ),
    );
  }
}

// ── Service card ──────────────────────────────────────────────────────────────

class _ServiceCard extends StatelessWidget {
  final ServiceModel service;
  final int colorIndex;

  const _ServiceCard({required this.service, required this.colorIndex});

  static const _cardBgColors = [
    Color(0xFFE3F2FD),
    Color(0xFFFFF3E0),
    Color(0xFFE8F5E9),
    Color(0xFFFCE4EC),
    Color(0xFFEDE7F6),
    Color(0xFFE0F7FA),
  ];

  static const _cardIconColors = [
    Color(0xFF1565C0),
    Color(0xFFE65100),
    Color(0xFF2E7D32),
    Color(0xFFC62828),
    Color(0xFF4527A0),
    Color(0xFF00838F),
  ];

  static const _cardIcons = [
    Icons.cleaning_services,
    Icons.kitchen,
    Icons.plumbing,
    Icons.electrical_services,
    Icons.format_paint,
    Icons.build,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final idx = colorIndex % _cardBgColors.length;

    return GestureDetector(
      onTap: () {
        // TODO: navigate to service detail
      },
      child: Container(
        width: 162,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 0.8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image / icon area
            Container(
              height: 110,
              decoration: BoxDecoration(
                color: _cardBgColors[idx],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Center(
                child: Icon(
                  _cardIcons[idx % _cardIcons.length],
                  size: 50,
                  color: _cardIconColors[idx],
                ),
              ),
            ),
            // Info area
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (service.categoryName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        service.categoryName!,
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '₹${service.startingPrice.toInt()}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (service.rating > 0)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded,
                                  size: 13, color: Color(0xFFFBBC04)),
                              const SizedBox(width: 2),
                              Text(
                                service.rating.toStringAsFixed(1),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Loading / Error / Empty states ────────────────────────────────────────────

class _ServicesSkeleton extends StatelessWidget {
  const _ServicesSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 224,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 4,
        itemBuilder: (_, _) => Container(
          width: 162,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: AppColors.shimmerBase,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _ServicesError extends StatelessWidget {
  const _ServicesError();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: AppColors.textHint, size: 32),
            SizedBox(height: 8),
            Text(
              'Could not load services',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServicesEmpty extends StatelessWidget {
  const _ServicesEmpty();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.home_repair_service_outlined,
                size: 48, color: AppColors.textHint),
            SizedBox(height: 12),
            Text(
              'No services available',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Check back soon',
              style: TextStyle(color: AppColors.textHint, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
