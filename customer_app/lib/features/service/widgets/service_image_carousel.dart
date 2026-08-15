import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/service_model.dart';

class ServiceImageCarousel extends StatefulWidget {
  final ServiceModel service;

  const ServiceImageCarousel({super.key, required this.service});

  @override
  State<ServiceImageCarousel> createState() => _ServiceImageCarouselState();
}

class _ServiceImageCarouselState extends State<ServiceImageCarousel> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  static const _fallbackGradients = [
    [Color(0xFF1A1714), Color(0xFF2C2420)],
    [Color(0xFF0D1B2A), Color(0xFF1B263B)],
    [Color(0xFF1A1A2E), Color(0xFF16213E)],
  ];

  List<Widget> get _slides {
    final slides = <Widget>[];
    // Primary: actual service image if available
    if (widget.service.imageUrl != null && widget.service.imageUrl!.isNotEmpty) {
      slides.add(_ImageSlide(imageUrl: widget.service.imageUrl!));
    }
    // Fill to at least 1 slide with gradient fallbacks
    final needed = slides.isEmpty ? 1 : 0;
    for (int i = 0; i < needed; i++) {
      slides.add(_GradientSlide(
        colors: _fallbackGradients[i % _fallbackGradients.length],
        service: widget.service,
        index: i,
      ));
    }
    return slides;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = _slides;
    final total = pages.length;

    return Stack(
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: total,
          onPageChanged: (i) => setState(() => _currentPage = i),
          itemBuilder: (_, i) => pages[i],
        ),

        // Bottom gradient scrim for readability
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 100,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withAlpha(160)],
              ),
            ),
          ),
        ),

        // Gold dot page indicators (bottom center)
        if (total > 1)
          Positioned(
            bottom: 14,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(total, (i) {
                final isActive = _currentPage == i;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: isActive ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.gold : Colors.white.withAlpha(120),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),

        // Dark pill page counter (bottom right)
        if (total > 1)
          Positioned(
            bottom: 10,
            right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(160),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                '${_currentPage + 1}/$total',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Image slide ───────────────────────────────────────────────────────────────

class _ImageSlide extends StatelessWidget {
  final String imageUrl;
  const _ImageSlide({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (_, child, progress) =>
          progress == null
              ? child
              : Container(color: AppColors.shimmerBase),
      errorBuilder: (_, _, _) => Container(
        color: AppColors.primary,
        alignment: Alignment.center,
        child: const Icon(
          Icons.home_repair_service_rounded,
          size: 64,
          color: Colors.white24,
        ),
      ),
    );
  }
}

// ── Gradient fallback slide ───────────────────────────────────────────────────

class _GradientSlide extends StatelessWidget {
  final List<Color> colors;
  final ServiceModel service;
  final int index;

  const _GradientSlide({
    required this.colors,
    required this.service,
    required this.index,
  });

  IconData get _icon {
    final name = service.name.toLowerCase();
    if (name.contains('clean')) return Icons.cleaning_services_rounded;
    if (name.contains('ac') || name.contains('air')) return Icons.ac_unit_rounded;
    if (name.contains('plumb') || name.contains('tap')) return Icons.plumbing_rounded;
    if (name.contains('electric') || name.contains('fan')) return Icons.electrical_services_rounded;
    if (name.contains('paint')) return Icons.format_paint_rounded;
    if (name.contains('pest')) return Icons.bug_report_rounded;
    if (name.contains('shift') || name.contains('mov')) return Icons.local_shipping_rounded;
    if (name.contains('carp')) return Icons.handyman_rounded;
    return Icons.home_repair_service_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Center(
        child: Icon(_icon, size: 80, color: Colors.white.withAlpha(60)),
      ),
    );
  }
}
