import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/section_header.dart';
import '../../../features/catalog/models/catalog_node_model.dart';

/// Renders the bookable sub-services (featured leaf/bookable catalog nodes)
/// in a horizontal scroll carousel. The distinct [section_type] = 'sub_services'
/// in the CMS gives this section its own identity, visibility toggle, and
/// configurable title independent of any trending or popular services section.
class SubServicesSection extends StatelessWidget {
  const SubServicesSection({
    super.key,
    required this.asyncServices,
    required this.onServiceTap,
    this.onSeeAll,
    this.title = 'Sub Services',
  });

  final AsyncValue<List<CatalogNodeModel>> asyncServices;
  final ValueChanged<CatalogNodeModel> onServiceTap;
  final VoidCallback? onSeeAll;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SectionHeader(title: title, onSeeAll: onSeeAll),
        ),
        const SizedBox(height: 20),
        asyncServices.when(
          loading: () => const _SubServicesSkeleton(),
          error: (e, _) => const SizedBox.shrink(),
          data: (services) => services.isEmpty
              ? const SizedBox.shrink()
              : _SubServicesCarousel(services: services, onServiceTap: onServiceTap),
        ),
      ],
    );
  }
}

// ── Horizontal scroll carousel ────────────────────────────────────────────────

const _kCardWidth = 148.0;
const _kCardHeight = 185.0; // approx cardWidth / 0.80

class _SubServicesCarousel extends StatelessWidget {
  const _SubServicesCarousel({
    required this.services,
    required this.onServiceTap,
  });

  final List<CatalogNodeModel> services;
  final ValueChanged<CatalogNodeModel> onServiceTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kCardHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: services.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) => SizedBox(
          width: _kCardWidth,
          child: _ServiceCard(
            service: services[index],
            onTap: () => onServiceTap(services[index]),
          ),
        ),
      ),
    );
  }
}

// ── Individual service card ────────────────────────────────────────────────────

class _ServiceCard extends StatefulWidget {
  const _ServiceCard({required this.service, required this.onTap});
  final CatalogNodeModel service;
  final VoidCallback onTap;

  @override
  State<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<_ServiceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hovered
                  ? AppColors.gold.withAlpha(120)
                  : AppColors.border,
              width: _hovered ? 1.5 : 0.8,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: AppColors.gold.withAlpha(30),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    const BoxShadow(
                      color: Color(0x07000000),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Service image
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: widget.service.imageUrl != null
                      ? Image.network(
                          widget.service.imageUrl!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (context, error, stackTrace) => const _PlaceholderImage(),
                        )
                      : const _PlaceholderImage(),
                ),
              ),
              // Service info
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.service.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        height: 1.3,
                      ),
                    ),
                    if (widget.service.basePrice != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'From ₹${widget.service.basePrice!.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.gold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Placeholder image ─────────────────────────────────────────────────────────

class _PlaceholderImage extends StatelessWidget {
  const _PlaceholderImage();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceVariant,
      child: const Center(
        child: Icon(
          Icons.home_repair_service_rounded,
          size: 36,
          color: AppColors.textHint,
        ),
      ),
    );
  }
}

// ── Loading skeleton ───────────────────────────────────────────────────────────

class _SubServicesSkeleton extends StatelessWidget {
  const _SubServicesSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kCardHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: 5,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) => Container(
          width: _kCardWidth,
          decoration: BoxDecoration(
            color: AppColors.shimmerBase,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
