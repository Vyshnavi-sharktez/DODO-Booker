import 'package:flutter/material.dart';
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

  static const _gradients = [
    [Color(0xFF1A73E8), Color(0xFF0D47A1)],
    [Color(0xFF00ACC1), Color(0xFF006064)],
    [Color(0xFF43A047), Color(0xFF1B5E20)],
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: _gradients.length,
          onPageChanged: (i) => setState(() => _currentPage = i),
          itemBuilder: (_, i) => _buildSlide(i),
        ),
        // Bottom gradient overlay
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 80,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withAlpha(140)],
              ),
            ),
          ),
        ),
        // Page indicators
        Positioned(
          bottom: 12,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _gradients.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _currentPage == i ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _currentPage == i ? Colors.white : Colors.white54,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSlide(int i) {
    final colors = _gradients[i % _gradients.length];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Center(
        child: Icon(
          _slideIcon(i),
          size: 80,
          color: Colors.white.withAlpha(77),
        ),
      ),
    );
  }

  IconData _slideIcon(int i) {
    final name = widget.service.name.toLowerCase();
    if (i == 0) {
      if (name.contains('clean')) return Icons.cleaning_services_rounded;
      if (name.contains('ac')) return Icons.ac_unit_rounded;
      if (name.contains('plumb') || name.contains('tap')) return Icons.plumbing_rounded;
      if (name.contains('electric') || name.contains('fan')) return Icons.electrical_services_rounded;
      if (name.contains('paint')) return Icons.format_paint_rounded;
      if (name.contains('pest')) return Icons.bug_report_rounded;
      if (name.contains('shift')) return Icons.local_shipping_rounded;
      return Icons.home_repair_service_rounded;
    }
    const icons = [
      Icons.verified_rounded,
      Icons.thumb_up_rounded,
      Icons.star_rounded,
    ];
    return icons[i % icons.length];
  }
}
