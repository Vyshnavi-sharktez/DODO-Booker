import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/service_image_registry.dart';
import '../../../core/widgets/section_header.dart';
import '../../../models/category_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Layout constants — identical to TrendingServicesSection
// ─────────────────────────────────────────────────────────────────────────────

const double _kGap    = 20.0;
const double _kRadius = 20.0;
const double _kInfoH  = 120.0;

/// Mirrors TrendingServicesSection._cardSize exactly.
({double w, double h}) _cardSize(double viewportW) {
  if (viewportW < 600) return (w: 220.0, h: 300.0);
  return (w: 260.0, h: 340.0);
}

// ─────────────────────────────────────────────────────────────────────────────
// Public section widget
// ─────────────────────────────────────────────────────────────────────────────

class HomeCategoriesSection extends StatelessWidget {
  final AsyncValue<List<CategoryModel>> asyncCategories;
  final ValueChanged<CategoryModel> onCategorySelected;
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
          child: SectionHeader(title: 'Services', onSeeAll: onSeeAll),
        ),
        const SizedBox(height: 20),
        asyncCategories.when(
          loading: () => const _Skeleton(),
          error: (_, _) => const SizedBox.shrink(),
          data: (cats) {
            final visible =
                cats.where((c) => c.name.trim().isNotEmpty).toList();
            return visible.isEmpty
                ? const SizedBox.shrink()
                : _Carousel(
                    categories: visible,
                    onSelect: onCategorySelected,
                  );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Horizontal carousel — same structure as TrendingServicesSection._Carousel
// ─────────────────────────────────────────────────────────────────────────────

class _Carousel extends StatelessWidget {
  final List<CategoryModel> categories;
  final ValueChanged<CategoryModel> onSelect;

  const _Carousel({required this.categories, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = _cardSize(constraints.maxWidth);
        final listH = size.h + 24; // 24px shadow breathing room

        return ScrollConfiguration(
          behavior: _PointerScrollBehavior(),
          child: SizedBox(
            height: listH,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              itemCount: categories.length,
              itemBuilder: (_, i) => Padding(
                padding: EdgeInsets.only(
                  right: i < categories.length - 1 ? _kGap : 0,
                ),
                child: _CategoryCard(
                  category: categories[i],
                  cardWidth: size.w,
                  cardHeight: size.h,
                  onTap: () => onSelect(categories[i]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Category card — same dimensions + structure as _ServiceCard
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryCard extends StatefulWidget {
  final CategoryModel category;
  final double cardWidth;
  final double cardHeight;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.category,
    required this.cardWidth,
    required this.cardHeight,
    required this.onTap,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
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
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _navigate,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: widget.cardWidth,
          height: widget.cardHeight,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_kRadius),
            border: Border.all(
              color: const Color(0xFFEBEBEB),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(_hovered ? 26 : 14),
                blurRadius: _hovered ? 22 : 10,
                spreadRadius: 0,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_kRadius - 1),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Image — fills remaining height above info strip
                Expanded(
                  child: _CardImage(category: widget.category),
                ),
                // Info strip — fixed 120px, same as service cards
                SizedBox(
                  height: _kInfoH,
                  child: _CardInfo(
                    category: widget.category,
                    onTap: _navigate,
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
  final CategoryModel category;
  const _CardImage({required this.category});

  @override
  Widget build(BuildContext context) {
    final url = ServiceImageRegistry.resolve(
      category.imageUrl,
      category.name,
    );
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
  final CategoryModel category;
  final VoidCallback onTap;

  const _CardInfo({required this.category, required this.onTap});

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
            // Category name — 2 lines max, same style as service name
            Text(
              category.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A),
                height: 1.25,
              ),
            ),
            // Optional description sub-line
            if (category.description?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(
                category.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textHint,
                  height: 1.2,
                ),
              ),
            ],
            const Spacer(),
            // Bottom row: service count (left) + "View" button (right)
            // Mirrors price + "Book Now" layout from service cards
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (category.serviceCount > 0)
                  Text(
                    '${category.serviceCount} Services',
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = _cardSize(constraints.maxWidth);
        final listH = size.h + 24;

        return SizedBox(
          height: listH,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            itemCount: 5,
            itemBuilder: (_, i) => Container(
              width: size.w,
              height: size.h,
              margin: EdgeInsets.only(right: i < 4 ? _kGap : 0),
              decoration: BoxDecoration(
                color: AppColors.shimmerBase,
                borderRadius: BorderRadius.circular(_kRadius),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scroll behavior — mouse, trackpad, touch, stylus; no scrollbar
// ─────────────────────────────────────────────────────────────────────────────

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
