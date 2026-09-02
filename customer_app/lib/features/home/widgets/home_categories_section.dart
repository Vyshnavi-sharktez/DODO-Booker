import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/service_image_registry.dart';
import '../../../core/widgets/horizontal_carousel.dart';
import '../../../core/widgets/section_header.dart';
import '../../../features/catalog/models/catalog_node_model.dart';

// ── Layout constants (full-image portrait card) ───────────────────────────────

const double _kCardW  = 340.0;
const double _kCardH  = 180.0;
const double _kGap    = 20.0;
const double _kRadius = 16.0;

// ── Section widget ────────────────────────────────────────────────────────────

class HomeCategoriesSection extends StatelessWidget {
  final AsyncValue<List<CatalogNodeModel>> asyncCategories;
  final ValueChanged<CatalogNodeModel> onCategorySelected;
  final VoidCallback? onSeeAll;

  const HomeCategoriesSection({
    super.key,
    required this.asyncCategories,
    required this.onCategorySelected,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SectionHeader(title: 'Our Services', onSeeAll: onSeeAll),
        ),
        const SizedBox(height: 20),
        asyncCategories.when(
          loading: () => const _Skeleton(),
          error: (_, _) => const SizedBox.shrink(),
          data: (nodes) {
            final visible =
                nodes.where((n) => n.name.trim().isNotEmpty).toList();
            return visible.isEmpty
                ? const SizedBox.shrink()
                : _Carousel(nodes: visible, onSelect: onCategorySelected);
          },
        ),
      ],
    );
  }
}

// ── Horizontal carousel ───────────────────────────────────────────────────────

class _Carousel extends StatelessWidget {
  final List<CatalogNodeModel> nodes;
  final ValueChanged<CatalogNodeModel> onSelect;

  const _Carousel({required this.nodes, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return HorizontalCarousel(
      height: _kCardH + 20,
      itemCount: nodes.length,
      scrollStep: 3 * (_kCardW + _kGap),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      itemBuilder: (_, i) => Padding(
        padding: EdgeInsets.only(right: i < nodes.length - 1 ? _kGap : 0),
        child: _ServiceCard(
          node: nodes[i],
          onTap: () => onSelect(nodes[i]),
        ),
      ),
    );
  }
}

// ── Full-image portrait card (200 × 260) ──────────────────────────────────────

class _ServiceCard extends StatefulWidget {
  final CatalogNodeModel node;
  final VoidCallback onTap;

  const _ServiceCard({required this.node, required this.onTap});

  @override
  State<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<_ServiceCard> {
  bool _hovered = false;
  bool _navigating = false;

  void _navigate() {
    if (_navigating) return;
    _navigating = true;
    widget.onTap();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _navigating = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final url = ServiceImageRegistry.resolve(node.imageUrl, node.name);
    final String? subLabel = node.basePrice != null
        ? '₹${(node.finalPrice ?? node.basePrice)!.toInt()}'
        : node.childrenCount > 0
            ? '${node.childrenCount} options'
            : null;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _navigate,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: _kCardW,
          height: _kCardH,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_kRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(_hovered ? 40 : 18),
                blurRadius: _hovered ? 22 : 8,
                offset: Offset(0, _hovered ? 8 : 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_kRadius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ── Full background image ──────────────────────────────────
                Image.network(
                  url,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, p) => p == null
                      ? child
                      : const ColoredBox(color: Color(0xFFECE7DE)),
                  errorBuilder: (_, _, _) => Container(
                    color: const Color(0xFFECE7DE),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.home_repair_service_rounded,
                      size: 40,
                      color: AppColors.gold,
                    ),
                  ),
                ),
                // ── Bottom gradient overlay ────────────────────────────────
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.30, 0.62, 1.0],
                      colors: [
                        Color(0x00000000),
                        Color(0x88000000),
                        Color(0xCE000000),
                      ],
                    ),
                  ),
                ),
                // ── Hover brightening ──────────────────────────────────────
                if (_hovered)
                  const ColoredBox(color: Color(0x12FFFFFF)),
                // ── Bottom content ─────────────────────────────────────────
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        node.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.2,
                        ),
                      ),
                      if (subLabel != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subLabel,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: Color(0xC8FFFFFF),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      // View → button
                      GestureDetector(
                        onTap: _navigate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'View',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 5),
                              const Text(
                                '→',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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

// ─────────────────────────────────────────────────────────────────────────────
// Card image — static, no hover animation
// ─────────────────────────────────────────────────────────────────────────────

class _CardImage extends StatelessWidget {
  final CatalogNodeModel node;
  const _CardImage({required this.node});

  @override
  Widget build(BuildContext context) {
    final url = ServiceImageRegistry.resolve(node.imageUrl, node.name);
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (_, child, p) =>
          p == null ? child : const ColoredBox(color: Color(0xFFEEEEEE)),
      errorBuilder: (_, _, _) => Container(
        color: AppColors.goldLight,
        alignment: Alignment.center,
        child: const Icon(
          Icons.home_repair_service_rounded,
          size: 32,
          color: AppColors.gold,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Info strip — mirrors _CardInfo layout from TrendingServicesSection
// ─────────────────────────────────────────────────────────────────────────────

class _CardInfo extends StatelessWidget {
  final CatalogNodeModel node;
  final VoidCallback onTap;

  const _CardInfo({required this.node, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              node.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A),
                height: 1.25,
              ),
            ),

            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (node.isLeafBookable && node.basePrice != null)
                  Text(
                    '₹${(node.finalPrice ?? node.basePrice)!.toInt()}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A1A),
                      height: 1.2,
                    ),
                  )
                else if (node.childrenCount > 0)
                  Text(
                    '${node.childrenCount} ${node.childrenCount == 1 ? 'option' : 'options'}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A1A),
                      height: 1.2,
                    ),
                  )
                else
                  const SizedBox.shrink(),
                GestureDetector(
                  onTap: onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.textPrimary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'View',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                        height: 1.2,
                      ),
                    ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Loading skeleton — same responsive height as real carousel
// ─────────────────────────────────────────────────────────────────────────────

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kCardH + 20,
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
