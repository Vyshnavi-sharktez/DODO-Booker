import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/section_header.dart';
import '../../../models/category_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const double _kGap    = 16.0;
const double _kRadius = 24.0;

({double w, double h}) _cardSize(double viewportW) {
  if (viewportW < 480) return (w: 170.0, h: 230.0);  // mobile
  if (viewportW < 768) return (w: 200.0, h: 255.0);  // tablet
  return (w: 230.0, h: 285.0);                        // desktop
}

// Generic Unsplash fallback
const String _kDefaultImageUrl =
    'https://images.unsplash.com/photo-1581578731548-c64695cc6952'
    '?w=480&q=75&auto=format&fit=crop';

// ─────────────────────────────────────────────────────────────────────────────
// Section
// ─────────────────────────────────────────────────────────────────────────────

class PopularCategoriesSection extends StatelessWidget {
  final AsyncValue<List<CategoryModel>> asyncCategories;
  final ValueChanged<CategoryModel> onCategorySelected;
  final VoidCallback? onSeeAll;

  const PopularCategoriesSection({
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
          child: SectionHeader(title: 'Service Categories', onSeeAll: onSeeAll),
        ),
        const SizedBox(height: 24),
        asyncCategories.when(
          loading: () => const _SkeletonRow(),
          error: (_, _) => const SizedBox.shrink(),
          data: (cats) {
            final visible = cats.where((c) => c.name.trim().isNotEmpty).toList();
            if (visible.isEmpty) return const SizedBox.shrink();
            return _Carousel(categories: visible, onSelect: onCategorySelected);
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Carousel
// ─────────────────────────────────────────────────────────────────────────────

class _Carousel extends StatefulWidget {
  final List<CategoryModel> categories;
  final ValueChanged<CategoryModel> onSelect;

  const _Carousel({required this.categories, required this.onSelect});

  @override
  State<_Carousel> createState() => _CarouselState();
}

class _CarouselState extends State<_Carousel> {
  final _ctrl = ScrollController();
  double _currentCardW = 230;

  void _snap() {
    if (!_ctrl.hasClients) return;
    final step = _currentCardW + _kGap;
    final target = (_ctrl.offset / step).round() * step;
    final clamped = target.clamp(0.0, _ctrl.position.maxScrollExtent);
    if ((clamped - _ctrl.offset).abs() > 0.5) {
      _ctrl.animateTo(
        clamped,
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = _cardSize(constraints.maxWidth);
        _currentCardW = size.w;
        final listH = size.h + 28; // shadow breathing room

        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is ScrollEndNotification) {
              SchedulerBinding.instance.addPostFrameCallback((_) => _snap());
            }
            return false;
          },
          child: ScrollConfiguration(
            behavior: _CarouselScrollBehavior(),
            child: SizedBox(
              height: listH,
              child: ListView.builder(
                controller: _ctrl,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                itemCount: widget.categories.length,
                itemBuilder: (_, i) {
                  final cat = widget.categories[i];
                  return Padding(
                    padding: EdgeInsets.only(
                      right: i < widget.categories.length - 1 ? _kGap : 0,
                    ),
                    child: ServiceCategoryCard(
                      category: cat,
                      cardWidth: size.w,
                      cardHeight: size.h,
                      onTap: () => widget.onSelect(cat),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CarouselScrollBehavior extends MaterialScrollBehavior {
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

// ─────────────────────────────────────────────────────────────────────────────
// ServiceCategoryCard — Urban Company style full-bleed image + gradient overlay
// ─────────────────────────────────────────────────────────────────────────────

class ServiceCategoryCard extends StatefulWidget {
  final CategoryModel category;
  final double cardWidth;
  final double cardHeight;
  final VoidCallback onTap;

  const ServiceCategoryCard({
    super.key,
    required this.category,
    required this.cardWidth,
    required this.cardHeight,
    required this.onTap,
  });

  @override
  State<ServiceCategoryCard> createState() => _ServiceCategoryCardState();
}

class _ServiceCategoryCardState extends State<ServiceCategoryCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          width: widget.cardWidth,
          height: widget.cardHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_kRadius),
            boxShadow: [
              BoxShadow(
                color: _hovered
                    ? AppColors.gold.withAlpha(70)
                    : Colors.black.withAlpha(28),
                blurRadius: _hovered ? 28 : 12,
                spreadRadius: _hovered ? 2 : 0,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_kRadius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ── Full-bleed image with zoom on hover ────────────────
                AnimatedScale(
                  scale: _hovered ? 1.06 : 1.0,
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  child: _CategoryImage(category: widget.category),
                ),

                // ── Dark gradient scrim (bottom 60%) ───────────────────
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: widget.cardHeight * 0.62,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withAlpha(220),
                          Colors.black.withAlpha(90),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.55, 1.0],
                      ),
                    ),
                  ),
                ),

                // ── Subtle gold shimmer on hover ───────────────────────
                AnimatedOpacity(
                  opacity: _hovered ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.gold.withAlpha(18),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Category name + count + arrow at bottom ────────────
                Positioned(
                  bottom: 16,
                  left: 14,
                  right: 14,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.category.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                                letterSpacing: -0.2,
                              ),
                            ),
                            if (widget.category.serviceCount > 0) ...[
                              const SizedBox(height: 3),
                              Text(
                                '${widget.category.serviceCount} services',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withAlpha(178),
                                  fontSize: 11.5,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _hovered
                              ? AppColors.gold
                              : Colors.white.withAlpha(230),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                          color: _hovered
                              ? Colors.black
                              : cs.onSurface,
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
// _CategoryImage
//
// Resolution chain:
//   1. category.imageUrl  (admin-uploaded via Supabase)
//   2. _nameUrl()         (Unsplash matched by category name)
//   3. _kDefaultImageUrl  (always-valid cleaning photo fallback)
//   4. _GradientFallback  (fully offline — styled dark gradient)
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryImage extends StatelessWidget {
  final CategoryModel category;
  const _CategoryImage({required this.category});

  static String? _nameUrl(String name) {
    final n = name.toLowerCase();
    if (n.contains('clean')) {
      return 'https://images.unsplash.com/photo-1581578731548-c64695cc6952?w=480&q=80&auto=format&fit=crop';
    }
    if (n.contains('plumb')) {
      return 'https://images.unsplash.com/photo-1607472586893-edb57bdc0e39?w=480&q=80&auto=format&fit=crop';
    }
    if (n.contains('electr')) {
      return 'https://images.unsplash.com/photo-1621905252507-b35492cc74b4?w=480&q=80&auto=format&fit=crop';
    }
    if (n.contains('paint')) {
      return 'https://images.unsplash.com/photo-1562259929-b4e1fd3aef09?w=480&q=80&auto=format&fit=crop';
    }
    if (n.contains('carp')) {
      return 'https://images.unsplash.com/photo-1504148455328-c376907d081c?w=480&q=80&auto=format&fit=crop';
    }
    if (n.contains('pest')) {
      return 'https://images.unsplash.com/photo-1530036128081-77a1e879d6a8?w=480&q=80&auto=format&fit=crop';
    }
    if (n.contains('appli') || n.contains('repair')) {
      return 'https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=480&q=80&auto=format&fit=crop';
    }
    if (n.contains('shift') || n.contains('mov') || n.contains('relocat')) {
      return 'https://images.unsplash.com/photo-1600518464441-9154a4dea21b?w=480&q=80&auto=format&fit=crop';
    }
    if (n.startsWith('ac') || n.contains('ac repair') || n.contains('hvac')) {
      return 'https://images.unsplash.com/photo-1625451648930-f5d7c7d98b28?w=480&q=80&auto=format&fit=crop';
    }
    if (n.contains('salon') || n.contains('beauty') || n.contains('hair')) {
      return 'https://images.unsplash.com/photo-1560066984-138dadb4c035?w=480&q=80&auto=format&fit=crop';
    }
    if (n.contains('ev ') || n == 'ev' || n.contains('electric vehicle')) {
      return 'https://images.unsplash.com/photo-1593941707882-a5bba14938c7?w=480&q=80&auto=format&fit=crop';
    }
    if (n.contains('garden') || n.contains('landscap')) {
      return 'https://images.unsplash.com/photo-1416879595882-3373a0480b5b?w=480&q=80&auto=format&fit=crop';
    }
    if (n.contains('security') || n.contains('cctv')) {
      return 'https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=480&q=80&auto=format&fit=crop';
    }
    return null;
  }

  static const _shimmer = ColoredBox(color: Color(0xFFDDDDDD));

  @override
  Widget build(BuildContext context) {
    final adminUrl =
        category.imageUrl?.isNotEmpty == true ? category.imageUrl! : null;
    final nameUrl = _nameUrl(category.name);
    final primaryUrl = adminUrl ?? nameUrl ?? _kDefaultImageUrl;

    return Image.network(
      primaryUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (_, child, p) => p == null ? child : _shimmer,
      errorBuilder: (_, _, _) {
        if (adminUrl != null && nameUrl != null) {
          return Image.network(
            nameUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            loadingBuilder: (_, child, p) => p == null ? child : _shimmer,
            errorBuilder: (_, _, _) => _networkFallback(),
          );
        }
        return _networkFallback();
      },
    );
  }

  Widget _networkFallback() => Image.network(
        _kDefaultImageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (_, child, p) =>
            p == null ? child : const ColoredBox(color: Color(0xFFDDDDDD)),
        errorBuilder: (_, _, _) => _GradientFallback(name: category.name),
      );
}

// Premium dark gradient used when all network images fail (offline mode)
class _GradientFallback extends StatelessWidget {
  final String name;
  const _GradientFallback({required this.name});

  static const _gradients = <List<Color>>[
    [Color(0xFF1A1A2E), Color(0xFF16213E)],
    [Color(0xFF111111), Color(0xFF2C2C2C)],
    [Color(0xFF0D1117), Color(0xFF1C2833)],
    [Color(0xFF1B0000), Color(0xFF2D1515)],
    [Color(0xFF0A0F1C), Color(0xFF111827)],
  ];

  @override
  Widget build(BuildContext context) {
    final idx = name.hashCode.abs() % _gradients.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _gradients[idx],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.home_repair_service_rounded,
          size: 44,
          color: Colors.white.withAlpha(50),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading skeleton
// ─────────────────────────────────────────────────────────────────────────────

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = _cardSize(constraints.maxWidth);
        final listH = size.h + 28;

        return SizedBox(
          height: listH,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            itemCount: 5,
            itemBuilder: (_, i) => Container(
              width: size.w,
              height: size.h,
              margin: EdgeInsets.only(right: i < 4 ? _kGap : 0),
              decoration: BoxDecoration(
                color: cs.onSurface.withAlpha(20),
                borderRadius: BorderRadius.circular(_kRadius),
              ),
            ),
          ),
        );
      },
    );
  }
}
