import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/service_image_registry.dart';
import '../../../core/widgets/section_header.dart';
import '../../../models/service_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Layout constants
// ─────────────────────────────────────────────────────────────────────────────

const double _kGap    = 16.0;
const double _kRadius = 20.0;
const double _kInfoH  = 130.0;

// Info-strip height budget (130px):
//   Padding: top 12 + bottom 14 = 26px
//   Available for Column children: 104px
//     name   2 lines × 13px × h1.25 ≈ 32.5px
//     gap 3
//     desc   2 lines × 11px × h1.35 ≈ 29.7px  (optional)
//     Spacer (flexible)
//     rating row 11px icon → ~13px              (optional)
//     gap 4
//     price  13px × h1.25 ≈ 16px
//
//   With desc+rating: 32.5+3+29.7+13+4+16 = 98.2 ≤ 104 ✓
//   Without desc:     32.5+13+4+16 = 65.5 ≤ 104 ✓  (Spacer fills rest)

// ─────────────────────────────────────────────────────────────────────────────
// Responsive card dimensions
// ─────────────────────────────────────────────────────────────────────────────

({double w, double h}) _cardSize(double viewportW) {
  if (viewportW < 600) {
    // ~1.2 cards visible on mobile — card = 70% viewport width
    final w = (viewportW * 0.70).clamp(180.0, 280.0);
    return (w: w, h: 300.0);
  }
  return (w: 260.0, h: 340.0); // desktop
}

// ─────────────────────────────────────────────────────────────────────────────
// Section
// ─────────────────────────────────────────────────────────────────────────────

class MostBookedServicesSection extends StatelessWidget {
  final AsyncValue<List<ServiceModel>> asyncServices;
  final ValueChanged<ServiceModel> onServiceTap;
  final VoidCallback? onSeeAll;

  const MostBookedServicesSection({
    super.key,
    required this.asyncServices,
    required this.onServiceTap,
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
          child: SectionHeader(
            title: 'Most Booked Services',
            onSeeAll: onSeeAll,
          ),
        ),
        const SizedBox(height: 20),
        asyncServices.when(
          loading: () => const _Skeleton(),
          error: (_, _) => const SizedBox.shrink(),
          data: (services) {
            if (services.isEmpty) return const _Empty();
            return _Carousel(
              services: services,
              onServiceTap: onServiceTap,
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Horizontal snap carousel
// ─────────────────────────────────────────────────────────────────────────────

class _Carousel extends StatefulWidget {
  final List<ServiceModel> services;
  final ValueChanged<ServiceModel> onServiceTap;

  const _Carousel({required this.services, required this.onServiceTap});

  @override
  State<_Carousel> createState() => _CarouselState();
}

class _CarouselState extends State<_Carousel> {
  final _ctrl = ScrollController();
  double _currentCardW = 260;

  void _snap() {
    if (!_ctrl.hasClients) return;
    final step = _currentCardW + _kGap;
    final target = (_ctrl.offset / step).round() * step;
    final clamped = target.clamp(0.0, _ctrl.position.maxScrollExtent);
    if ((clamped - _ctrl.offset).abs() > 0.5) {
      _ctrl.animateTo(
        clamped,
        duration: const Duration(milliseconds: 320),
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
        final listH = size.h + 24;

        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is ScrollEndNotification) {
              SchedulerBinding.instance
                  .addPostFrameCallback((_) => _snap());
            }
            return false;
          },
          child: ScrollConfiguration(
            behavior: _ScrollBehavior(),
            child: SizedBox(
              height: listH,
              child: ListView.builder(
                controller: _ctrl,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                itemCount: widget.services.length,
                itemBuilder: (_, i) {
                  final svc = widget.services[i];
                  return Padding(
                    padding: EdgeInsets.only(
                      right: i < widget.services.length - 1 ? _kGap : 0,
                    ),
                    child: _ServiceCard(
                      service: svc,
                      cardWidth: size.w,
                      cardHeight: size.h,
                      onTap: () => widget.onServiceTap(svc),
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

class _ScrollBehavior extends MaterialScrollBehavior {
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
// Service card
//
// Layout:
//   SizedBox(cardW × cardH)
//     AnimatedContainer(border, shadow)   ← hover decoration
//       ClipRRect(radius: 18.5)
//         Column
//           Expanded → _CardImage         ← fills cardH - _kInfoH
//           SizedBox(_kInfoH) → _CardInfo ← always exactly 130px
// ─────────────────────────────────────────────────────────────────────────────

class _ServiceCard extends StatefulWidget {
  final ServiceModel service;
  final double cardWidth;
  final double cardHeight;
  final VoidCallback onTap;

  const _ServiceCard({
    required this.service,
    required this.cardWidth,
    required this.cardHeight,
    required this.onTap,
  });

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
    final cs = Theme.of(context).colorScheme;
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
            color: cs.surface,
            borderRadius: BorderRadius.circular(_kRadius),
            border: Border.all(
              color: _hovered ? AppColors.gold : cs.outline.withAlpha(80),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _hovered
                    ? AppColors.gold.withAlpha(50)
                    : Colors.black.withAlpha(16),
                blurRadius: _hovered ? 24 : 10,
                spreadRadius: _hovered ? 1 : 0,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_kRadius - 1.5),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Image — fills (cardHeight − _kInfoH)
                Expanded(
                  child: _CardImage(
                    service: widget.service,
                    hovered: _hovered,
                  ),
                ),
                // Info strip — fixed 130px, cannot overflow
                SizedBox(
                  height: _kInfoH,
                  child: _CardInfo(service: widget.service),
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
// Card image with zoom-on-hover
// ─────────────────────────────────────────────────────────────────────────────

class _CardImage extends StatelessWidget {
  final ServiceModel service;
  final bool hovered;

  const _CardImage({required this.service, required this.hovered});

  @override
  Widget build(BuildContext context) {
    final url = ServiceImageRegistry.resolve(
      service.imageUrl,
      service.categoryName,
    );
    return ClipRect(
      child: AnimatedScale(
        scale: hovered ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 220),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          loadingBuilder: (_, child, p) =>
              p == null ? child : const ColoredBox(color: Color(0xFFEEEEEE)),
          errorBuilder: (_, _, _) =>
              const ColoredBox(color: Color(0xFFF0F0F0)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card info strip
//
// Layout (top → bottom, inside 130px fixed height):
//   Service name   (2 lines, 13px bold)
//   Description    (2 lines, 11px grey) — optional
//   Spacer
//   ⭐ rating      (11px, gold)         — optional
//   Starting from ₹price (13px bold)
// ─────────────────────────────────────────────────────────────────────────────

class _CardInfo extends StatelessWidget {
  final ServiceModel service;

  const _CardInfo({required this.service});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasDesc = service.description != null &&
        service.description!.trim().isNotEmpty;
    final hasRating = service.rating > 0;

    return ColoredBox(
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Service name ──────────────────────────────────────────
            Text(
              service.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
                height: 1.25,
              ),
            ),

            // ── Description ───────────────────────────────────────────
            if (hasDesc) ...[
              const SizedBox(height: 3),
              Text(
                service.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],

            const Spacer(),

            // ── Rating ────────────────────────────────────────────────
            if (hasRating) ...[
              Row(
                children: [
                  const Icon(Icons.star_rounded,
                      size: 11, color: AppColors.gold),
                  const SizedBox(width: 3),
                  Text(
                    service.rating.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                      height: 1.2,
                    ),
                  ),
                  if (service.reviewCount > 0) ...[
                    const SizedBox(width: 3),
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
              const SizedBox(height: 4),
            ],

            // ── Price ─────────────────────────────────────────────────
            Text(
              'Starting from ₹${service.startingPrice.toInt()}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading skeleton
// ─────────────────────────────────────────────────────────────────────────────

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
            itemCount: 4,
            itemBuilder: (_, i) {
              return Container(
                width: size.w,
                height: size.h,
                margin: EdgeInsets.only(right: i < 3 ? _kGap : 0),
                decoration: BoxDecoration(
                  color: cs.onSurface.withAlpha(20),
                  borderRadius: BorderRadius.circular(_kRadius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Container(color: cs.onSurface.withAlpha(20)),
                    ),
                    Container(
                      height: _kInfoH,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                      decoration:
                          BoxDecoration(color: cs.surface),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SkeletonLine(width: size.w * 0.75, height: 12),
                          const SizedBox(height: 6),
                          _SkeletonLine(width: size.w * 0.55, height: 10),
                          const Spacer(),
                          _SkeletonLine(width: size.w * 0.40, height: 10),
                          const SizedBox(height: 5),
                          _SkeletonLine(width: size.w * 0.60, height: 12),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  final double width;
  final double height;

  const _SkeletonLine({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: cs.onSurface.withAlpha(10),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.home_repair_service_outlined,
                size: 40, color: cs.onSurface.withAlpha(120)),
            const SizedBox(height: 10),
            Text(
              'No services available yet',
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
