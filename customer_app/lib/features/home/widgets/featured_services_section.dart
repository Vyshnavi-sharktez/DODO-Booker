import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/service_image_registry.dart';
import '../../../core/widgets/section_header.dart';
import '../../../models/service_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Layout constants  (identical to TrendingServicesSection for visual parity)
// ─────────────────────────────────────────────────────────────────────────────

const double _kGap    = 20.0;
const double _kRadius = 20.0;
const double _kInfoH  = 120.0;

({double w, double h}) _cardSize(double viewportW) {
  if (viewportW < 600) return (w: 220.0, h: 300.0);
  return (w: 260.0, h: 340.0);
}

// ─────────────────────────────────────────────────────────────────────────────
// Section
// ─────────────────────────────────────────────────────────────────────────────

class FeaturedServicesSection extends StatelessWidget {
  final String title;
  final AsyncValue<List<ServiceModel>> asyncServices;
  final ValueChanged<ServiceModel> onServiceSelected;
  final VoidCallback? onSeeAll;

  const FeaturedServicesSection({
    super.key,
    this.title = 'Featured Services',
    required this.asyncServices,
    required this.onServiceSelected,
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
          child: SectionHeader(title: title, onSeeAll: onSeeAll),
        ),
        const SizedBox(height: 20),
        asyncServices.when(
          loading: () => const _Skeleton(),
          error: (_, _) => const SizedBox.shrink(),
          data: (services) => services.isEmpty
              ? const SizedBox.shrink()
              : _Carousel(
                  services: services,
                  onServiceSelected: onServiceSelected,
                ),
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
  final ValueChanged<ServiceModel> onServiceSelected;

  const _Carousel({
    required this.services,
    required this.onServiceSelected,
  });

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
                      onTap: () => widget.onServiceSelected(svc),
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
                    ? AppColors.gold.withAlpha(55)
                    : Colors.black.withAlpha(18),
                blurRadius: _hovered ? 28 : 12,
                spreadRadius: _hovered ? 1 : 0,
                offset: const Offset(0, 6),
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
                  child: _CardImage(
                    service: widget.service,
                    hovered: _hovered,
                  ),
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
  final bool hovered;

  const _CardImage({required this.service, required this.hovered});

  @override
  Widget build(BuildContext context) {
    final url = ServiceImageRegistry.resolve(
      service.imageUrl,
      service.categoryName,
    );
    return AnimatedScale(
      scale: hovered ? 1.04 : 1.0,
      duration: const Duration(milliseconds: 200),
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
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surface,
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
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
                height: 1.25,
              ),
            ),
            if (service.categoryName != null) ...[
              const SizedBox(height: 4),
              Text(
                service.categoryName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurface.withAlpha(120),
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
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
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
            ],
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '₹${service.startingPrice.toInt()}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
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
                      color: cs.primary,
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
            itemBuilder: (_, i) => Container(
              width: size.w,
              height: size.h,
              margin: EdgeInsets.only(right: i < 3 ? _kGap : 0),
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
