import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/service_image_registry.dart';
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
    return ScrollConfiguration(
      behavior: _PointerScrollBehavior(),
      child: SizedBox(
        height: _kCardH + 20,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          itemCount: nodes.length,
          itemBuilder: (_, i) => Padding(
            padding:
                EdgeInsets.only(right: i < nodes.length - 1 ? _kGap : 0),
            child: _ServiceCard(
              node: nodes[i],
              onTap: () => onSelect(nodes[i]),
            ),
          ),
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
    final String? subLabel = node.childrenCount > 0
        ? '${node.childrenCount} options'
        : node.basePrice != null
            ? 'From ₹${node.basePrice!.toInt()}'
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

// ── Loading skeleton ──────────────────────────────────────────────────────────

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
