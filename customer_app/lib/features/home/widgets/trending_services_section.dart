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

const double _kGap    = 20.0;
const double _kRadius = 20.0;
const double _kInfoH  = 120.0;

// Info-strip height budget breakdown (120px):
//   padding top 10 + bottom 12 = 22px consumed by Padding
//   Remaining 98px for Column children:
//     name   2 lines × 13px × h1.25 ≈ 32.5px
//     +4 gap  = 4px
//     category 1 line × 10px × h1.2 ≈ 12px
//     +3 gap  = 3px
//     rating row                     ≈ 13px  (optional)
//     Spacer fills the rest
//     price + Book Now row           ≈ 22px
//   Total with rating: 32.5+4+12+3+13+22 = 86.5px ≤ 98px ✓

// ─────────────────────────────────────────────────────────────────────────────
// Responsive card dimensions
// ─────────────────────────────────────────────────────────────────────────────

({double w, double h}) _cardSize(double viewportW) {
  if (viewportW < 600) return (w: 220.0, h: 300.0); // mobile  (~2 cards)
  return (w: 260.0, h: 340.0);                       // desktop (~4 cards)
}

// ─────────────────────────────────────────────────────────────────────────────
// Section
// ─────────────────────────────────────────────────────────────────────────────

class TrendingServicesSection extends StatelessWidget {
  final AsyncValue<List<ServiceModel>> asyncServices;
  final ValueChanged<ServiceModel> onServiceTap;
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
          child: SectionHeader(
            title: title,
            onSeeAll: onSeeAll,
          ),
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
        final listH = size.h + 24; // 24px shadow breathing room

        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is ScrollEndNotification) {
              SchedulerBinding.instance
                  .addPostFrameCallback((_) => _snap());
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
// Service card
//
// Layout:
//   SizedBox(cardW × cardH)              ← hard outer bound
//     AnimatedContainer(border, shadow)  ← hover decoration
//       ClipRRect(radius: 18.5)          ← rounds content to match border
//         Column
//           Expanded   → _CardImage      ← fills (cardH - _kInfoH)
//           SizedBox(_kInfoH) → _CardInfo ← always exactly 120px
//
// Card vs Book Now tap:
//   Both navigate to the same destination (service details).
//   A _navigating guard prevents double-push when nested GestureDetectors
//   both resolve (inner wins per Flutter's arena, but guard is a safety net).
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
                offset: Offset(0, _hovered ? 8 : 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_kRadius - 1.5),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _CardImage(service: widget.service),
                ),
                SizedBox(
                  height: _kInfoH,
                  child: _CardInfo(
                    service: widget.service,
                    onBookNow: _navigate,
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
// Card image
// ─────────────────────────────────────────────────────────────────────────────

class _CardImage extends StatelessWidget {
  final ServiceModel service;

  const _CardImage({required this.service});

  @override
  Widget build(BuildContext context) {
    final url = ServiceImageRegistry.resolve(
      service.imageUrl,
      service.categoryName,
    );

    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (_, child, p) =>
          p == null ? child : const ColoredBox(color: Color(0xFFEEEEEE)),
      errorBuilder: (_, _, _) =>
          const ColoredBox(color: Color(0xFFF0F0F0)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card info strip
// ─────────────────────────────────────────────────────────────────────────────

class _CardInfo extends StatelessWidget {
  final ServiceModel service;
  final VoidCallback onBookNow;

  const _CardInfo({required this.service, required this.onBookNow});

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
              service.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A),
                height: 1.25,
              ),
            ),
            if (service.categoryName != null) ...[
              const SizedBox(height: 4),
              Text(
                service.categoryName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textHint,
                  height: 1.2,
                ),
              ),
            ],
            if (service.rating > 0) ...[
              const SizedBox(height: 3),
              Row(
                children: [
                  const Icon(
                    Icons.star_rounded,
                    size: 11,
                    color: AppColors.gold,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    service.rating.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF444444),
                      height: 1.2,
                    ),
                  ),
                  if (service.reviewCount > 0) ...[
                    const SizedBox(width: 2),
                    Text(
                      '(${service.reviewCount})',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textHint,
                        height: 1.2,
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '₹${service.startingPrice.toInt()}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A1A),
                    height: 1.2,
                  ),
                ),
                GestureDetector(
                  onTap: onBookNow,
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
                      'Book Now',
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
// Loading skeleton
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
            itemCount: 4,
            itemBuilder: (_, i) => Container(
              width: size.w,
              height: size.h,
              margin: EdgeInsets.only(right: i < 3 ? _kGap : 0),
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
