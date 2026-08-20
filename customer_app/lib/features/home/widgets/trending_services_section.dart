import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/service_image_registry.dart';
import '../../../core/widgets/section_header.dart';
import '../../../features/catalog/models/catalog_node_model.dart';

// ── Layout constants (standard card, same spec as sub_services) ───────────────

const double _kCardW  = 240.0;
const double _kImgH   = 170.0;
const double _kLabelH = 56.0;
const double _kCardH  = _kImgH + _kLabelH;
const double _kGap    = 16.0;
const double _kRadius = 16.0;

// ── Section ───────────────────────────────────────────────────────────────────

class TrendingServicesSection extends StatelessWidget {
  final AsyncValue<List<CatalogNodeModel>> asyncServices;
  final ValueChanged<CatalogNodeModel> onServiceTap;
  final VoidCallback? onSeeAll;
  final String title;

  const TrendingServicesSection({
    super.key,
    required this.asyncServices,
    required this.onServiceTap,
    this.onSeeAll,
    this.title = 'Most Booked Services',
  });

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
          loading: () => const _Skeleton(),
          error: (_, _) => const SizedBox.shrink(),
          data: (services) => services.isEmpty
              ? const SizedBox.shrink()
              : _Carousel(services: services, onServiceTap: onServiceTap),
        ),
      ],
    );
  }
}

// ── Carousel ──────────────────────────────────────────────────────────────────

class _Carousel extends StatelessWidget {
  final List<CatalogNodeModel> services;
  final ValueChanged<CatalogNodeModel> onServiceTap;

  const _Carousel({required this.services, required this.onServiceTap});

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: _PointerScrollBehavior(),
      child: SizedBox(
        height: _kCardH + 16, // 16px shadow breathing room
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          itemCount: services.length,
          itemBuilder: (_, i) => Padding(
            padding: EdgeInsets.only(
              right: i < services.length - 1 ? _kGap : 0,
            ),
            child: _ServiceCard(
              node: services[i],
              onTap: () => onServiceTap(services[i]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Standard service card ─────────────────────────────────────────────────────

class _ServiceCard extends StatefulWidget {
  final CatalogNodeModel node;
  final VoidCallback onTap;

  const _ServiceCard({required this.node, required this.onTap});

  @override
  State<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<_ServiceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final url = ServiceImageRegistry.resolve(node.imageUrl, node.parentName);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: _kCardW,
          height: _kCardH,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_kRadius),
            border: Border.all(
              color: _hovered
                  ? AppColors.gold.withAlpha(140)
                  : const Color(0xFFECE7DE),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(_hovered ? 20 : 8),
                blurRadius: _hovered ? 18 : 6,
                offset: Offset(0, _hovered ? 6 : 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_kRadius - 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Image ────────────────────────────────────────────────
                SizedBox(
                  height: _kImgH,
                  child: Image.network(
                    url,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    loadingBuilder: (_, child, p) => p == null
                        ? child
                        : const ColoredBox(color: Color(0xFFF1ECE1)),
                    errorBuilder: (_, _, _) => Container(
                      color: const Color(0xFFF1ECE1),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.home_repair_service_rounded,
                        size: 32,
                        color: AppColors.gold,
                      ),
                    ),
                  ),
                ),
                // ── Label strip ──────────────────────────────────────────
                SizedBox(
                  height: _kLabelH,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1A1714),
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            // Price
                            if (node.basePrice != null)
                              Text(
                                '₹${node.basePrice!.toInt()}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF1A1714),
                                ),
                              ),
                            if (node.basePrice != null && node.rating > 0)
                              const SizedBox(width: 8),
                            // Rating
                            if (node.rating > 0) ...[
                              const Icon(
                                Icons.star_rounded,
                                size: 12,
                                color: AppColors.gold,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                node.rating.toStringAsFixed(1),
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF666666),
                                ),
                              ),
                            ],
                          ],
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

// ── Skeleton ──────────────────────────────────────────────────────────────────

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kCardH + 16,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        itemCount: 4,
        itemBuilder: (_, i) => Container(
          width: _kCardW,
          height: _kCardH,
          margin: EdgeInsets.only(right: i < 3 ? _kGap : 0),
          decoration: BoxDecoration(
            color: AppColors.shimmerBase,
            borderRadius: BorderRadius.circular(_kRadius),
          ),
        ),
      ),
    );
  }
}

// ── Scroll behavior ───────────────────────────────────────────────────────────

class _PointerScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  Widget buildScrollbar(context, child, details) => child;
}
