import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/icon_registry.dart';
import '../../../core/utils/service_image_registry.dart';
import '../../../core/widgets/section_header.dart';
import '../../../models/service_model.dart';

class UrbanServicesSection extends StatelessWidget {
  final String title;
  final AsyncValue<List<ServiceModel>> asyncServices;
  final ValueChanged<ServiceModel> onServiceSelected;
  final VoidCallback? onSeeAll;

  const UrbanServicesSection({
    super.key,
    this.title = 'Most Booked Services',
    required this.asyncServices,
    required this.onServiceSelected,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SectionHeader(title: title, onSeeAll: onSeeAll),
        ),
        const SizedBox(height: 16),
        asyncServices.when(
          loading: () => const _ServiceGridSkeleton(),
          error: (error, stack) => const _ServiceGridError(),
          data: (services) {
            if (services.isEmpty) return const _ServiceGridEmpty();
            return _ServiceGrid(
              services: services,
              onServiceSelected: onServiceSelected,
            );
          },
        ),
      ],
    );
  }
}

// ── Responsive image grid ─────────────────────────────────────────────────────

class _ServiceGrid extends StatelessWidget {
  final List<ServiceModel> services;
  final ValueChanged<ServiceModel> onServiceSelected;

  const _ServiceGrid({
    required this.services,
    required this.onServiceSelected,
  });

  static int _cols(double width) {
    if (width < 480) return 2;
    if (width < 768) return 3;
    return 4;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = _cols(constraints.maxWidth);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisExtent: 300,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
          ),
          itemCount: services.length,
          itemBuilder: (context, index) => _ServiceCard(
            service: services[index],
            onTap: () => onServiceSelected(services[index]),
          ),
        );
      },
    );
  }
}

// ── Service card ──────────────────────────────────────────────────────────────

class _ServiceCard extends StatefulWidget {
  final ServiceModel service;
  final VoidCallback onTap;

  const _ServiceCard({required this.service, required this.onTap});

  @override
  State<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<_ServiceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final service = widget.service;
    final imageUrl =
        ServiceImageRegistry.resolve(service.imageUrl, service.categoryName);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _hovered
                  ? AppColors.gold.withAlpha(160)
                  : cs.outline.withAlpha(80),
              width: _hovered ? 1.5 : 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: _hovered
                    ? AppColors.gold.withAlpha(28)
                    : const Color(0x09000000),
                blurRadius: _hovered ? 24 : 8,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Image (54% of card height) ──────────────────────────
                Expanded(
                  flex: 54,
                  child: _CardImage(
                    imageUrl: imageUrl,
                    categoryName: service.categoryName,
                    hovered: _hovered,
                  ),
                ),
                // ── Info (46% of card height) ───────────────────────────
                Expanded(
                  flex: 46,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Service name
                        Text(
                          service.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Category label
                        if (service.categoryName != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            service.categoryName!,
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurface.withAlpha(120),
                              height: 1.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const Spacer(),
                        // Rating
                        if (service.rating > 0) ...[
                          Row(
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 11,
                                color: AppColors.gold,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                service.rating.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurfaceVariant,
                                  height: 1.2,
                                ),
                              ),
                              if (service.reviewCount > 0) ...[
                                const SizedBox(width: 2),
                                Text(
                                  '(${service.reviewCount})',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: cs.onSurface.withAlpha(120),
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                        ],
                        // Price
                        Text(
                          '₹${service.startingPrice.toInt()}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Book Now CTA
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Book Now',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Card image with fallback ──────────────────────────────────────────────────

class _CardImage extends StatelessWidget {
  final String imageUrl;
  final String? categoryName;
  final bool hovered;

  const _CardImage({
    required this.imageUrl,
    required this.categoryName,
    required this.hovered,
  });

  static const _bgColors = [
    Color(0xFFE3F2FD), Color(0xFFFFF3E0), Color(0xFFE8F5E9),
    Color(0xFFFCE4EC), Color(0xFFEDE7F6), Color(0xFFE0F7FA),
  ];
  static const _iconColors = [
    Color(0xFF1565C0), Color(0xFFE65100), Color(0xFF2E7D32),
    Color(0xFFC62828), Color(0xFF4527A0), Color(0xFF00838F),
  ];

  @override
  Widget build(BuildContext context) {
    final idx = (categoryName?.hashCode ?? 0).abs() % _bgColors.length;

    return AnimatedScale(
      scale: hovered ? 1.04 : 1.0,
      duration: const Duration(milliseconds: 160),
      child: Image.network(
        imageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return Container(color: _bgColors[idx]);
        },
        errorBuilder: (_, e, s) => Container(
          color: _bgColors[idx],
          child: Center(
            child: Icon(
              IconRegistry.resolve(null, categoryName),
              size: 44,
              color: _iconColors[idx],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Skeleton / Error / Empty states ──────────────────────────────────────────

class _ServiceGridSkeleton extends StatelessWidget {
  const _ServiceGridSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisExtent: 300,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
        ),
        itemCount: 8,
        itemBuilder: (_, index) => Container(
          decoration: BoxDecoration(
            color: cs.onSurface.withAlpha(20),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _ServiceGridError extends StatelessWidget {
  const _ServiceGridError();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, color: cs.onSurface.withAlpha(120), size: 36),
            const SizedBox(height: 10),
            Text(
              'Could not load services',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceGridEmpty extends StatelessWidget {
  const _ServiceGridEmpty();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Text(
          'No services available',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
        ),
      ),
    );
  }
}
