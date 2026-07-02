import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/coupon_model.dart';

// ── Layout constants ─────────────────────────────────────────────────────────────

const double _kRadius = 24.0;

double _bannerHeight(double vw) {
  if (vw < 480) return 340.0;
  if (vw < 768) return 265.0;
  return 295.0;
}

// ── Contextual image resolver ────────────────────────────────────────────────────
// Picks a professional Unsplash photo matched to the coupon's description/code.

String _resolveImage(CouponModel c) {
  final t = '${c.code} ${c.description ?? ''}'.toLowerCase();
  if (t.contains('clean')) {
    return 'https://images.unsplash.com/photo-1558618666-fcd25c85cd64'
        '?w=800&q=80&auto=format&fit=crop';
  }
  if (t.contains('electr')) {
    return 'https://images.unsplash.com/photo-1621905252507-b35492cc74b4'
        '?w=800&q=80&auto=format&fit=crop';
  }
  if (t.contains('plumb')) {
    return 'https://images.unsplash.com/photo-1607472586893-edb57bdc0e39'
        '?w=800&q=80&auto=format&fit=crop';
  }
  if (t.contains('ac') || t.contains('air con') || t.contains('hvac')) {
    return 'https://images.unsplash.com/photo-1625451448930-f5d7c7d98b28'
        '?w=800&q=80&auto=format&fit=crop';
  }
  if (t.contains('paint')) {
    return 'https://images.unsplash.com/photo-1562259929-b4e1fd3aef09'
        '?w=800&q=80&auto=format&fit=crop';
  }
  if (t.contains('carp')) {
    return 'https://images.unsplash.com/photo-1504148455328-c376907d081c'
        '?w=800&q=80&auto=format&fit=crop';
  }
  if (t.contains('pest')) {
    return 'https://images.unsplash.com/photo-1530036128081-77a1e879d6a8'
        '?w=800&q=80&auto=format&fit=crop';
  }
  if (t.contains('salon') || t.contains('beauty') || t.contains('hair')) {
    return 'https://images.unsplash.com/photo-1560066984-138dadb4c035'
        '?w=800&q=80&auto=format&fit=crop';
  }
  if (t.contains('shift') || t.contains('mov') || t.contains('relocat')) {
    return 'https://images.unsplash.com/photo-1600518464441-9154a4dea21b'
        '?w=800&q=80&auto=format&fit=crop';
  }
  return 'https://images.unsplash.com/photo-1581578731548-c64695cc6952'
      '?w=800&q=80&auto=format&fit=crop';
}

// ── Public widget ────────────────────────────────────────────────────────────────

class CouponCarousel extends StatelessWidget {
  final List<CouponModel> coupons;

  const CouponCarousel({super.key, required this.coupons});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final vw = constraints.maxWidth;
        if (vw < 600) {
          return _MobileCarousel(coupons: coupons, viewportW: vw);
        }
        return _DesktopCarousel(coupons: coupons, viewportW: vw);
      },
    );
  }
}

// ── Mobile: full-width PageView + dot indicators ─────────────────────────────────

class _MobileCarousel extends StatefulWidget {
  final List<CouponModel> coupons;
  final double viewportW;

  const _MobileCarousel({required this.coupons, required this.viewportW});

  @override
  State<_MobileCarousel> createState() => _MobileCarouselState();
}

class _MobileCarouselState extends State<_MobileCarousel> {
  late final PageController _ctrl;
  Timer? _timer;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = PageController();
    if (widget.coupons.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!mounted || !_ctrl.hasClients) return;
        final next = (_current + 1) % widget.coupons.length;
        _ctrl.animateToPage(next,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeInOut);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _bannerHeight(widget.viewportW);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: h,
          child: PageView.builder(
            controller: _ctrl,
            physics: const BouncingScrollPhysics(),
            itemCount: widget.coupons.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _CouponCard(
                coupon: widget.coupons[i],
                height: h,
                isMobile: true,
              ),
            ),
          ),
        ),
        if (widget.coupons.length > 1) ...[
          const SizedBox(height: 12),
          _DotIndicator(count: widget.coupons.length, current: _current),
        ],
      ],
    );
  }
}

// ── Desktop/tablet: PageView + left/right navigation arrows ──────────────────────

class _DesktopCarousel extends StatefulWidget {
  final List<CouponModel> coupons;
  final double viewportW;

  const _DesktopCarousel({required this.coupons, required this.viewportW});

  @override
  State<_DesktopCarousel> createState() => _DesktopCarouselState();
}

class _DesktopCarouselState extends State<_DesktopCarousel> {
  late final PageController _ctrl;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = PageController();
  }

  void _goTo(int page) {
    if (!_ctrl.hasClients) return;
    _ctrl.animateToPage(
      page.clamp(0, widget.coupons.length - 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _bannerHeight(widget.viewportW);
    final hPad = (widget.viewportW * 0.06).clamp(20.0, 56.0);

    return SizedBox(
      height: h + 28,
      child: Stack(
        children: [
          ScrollConfiguration(
            behavior: _AllPointerScrollBehavior(),
            child: PageView.builder(
              controller: _ctrl,
              physics: const BouncingScrollPhysics(),
              itemCount: widget.coupons.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (_, i) => Padding(
                padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 28),
                child: _CouponCard(
                  coupon: widget.coupons[i],
                  height: h,
                  isMobile: false,
                ),
              ),
            ),
          ),

          if (widget.coupons.length > 1)
            Positioned(
              left: 4,
              top: 0,
              bottom: 28,
              child: Center(
                child: _NavArrow(
                  icon: Icons.chevron_left_rounded,
                  enabled: _current > 0,
                  onTap: () => _goTo(_current - 1),
                ),
              ),
            ),

          if (widget.coupons.length > 1)
            Positioned(
              right: 4,
              top: 0,
              bottom: 28,
              child: Center(
                child: _NavArrow(
                  icon: Icons.chevron_right_rounded,
                  enabled: _current < widget.coupons.length - 1,
                  onTap: () => _goTo(_current + 1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AllPointerScrollBehavior extends MaterialScrollBehavior {
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

// ── Navigation arrow button ──────────────────────────────────────────────────────

class _NavArrow extends StatefulWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _NavArrow({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_NavArrow> createState() => _NavArrowState();
}

class _NavArrowState extends State<_NavArrow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: (_hovered && widget.enabled)
                ? AppColors.gold
                : Colors.black.withAlpha(145),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(55),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Opacity(
            opacity: widget.enabled ? 1.0 : 0.25,
            child: Icon(
              widget.icon,
              size: 24,
              color: (_hovered && widget.enabled) ? Colors.black : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Coupon card ──────────────────────────────────────────────────────────────────

class _CouponCard extends StatefulWidget {
  final CouponModel coupon;
  final double height;
  final bool isMobile;

  const _CouponCard({
    required this.coupon,
    required this.height,
    required this.isMobile,
  });

  @override
  State<_CouponCard> createState() => _CouponCardState();
}

class _CouponCardState extends State<_CouponCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final showChips = !widget.isMobile && widget.height >= 285;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_kRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(_hovered ? 32 : 22),
              blurRadius: _hovered ? 26 : 18,
              spreadRadius: 0,
              offset: Offset(0, _hovered ? 10 : 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_kRadius),
          child: widget.isMobile
              ? _MobileLayout(
                  coupon: widget.coupon,
                  height: widget.height,
                  hovered: _hovered,
                  showChips: showChips,
                )
              : _DesktopLayout(
                  coupon: widget.coupon,
                  height: widget.height,
                  hovered: _hovered,
                  showChips: showChips,
                ),
        ),
      ),
    );
  }
}

// ── Mobile layout: image on top, text below ──────────────────────────────────────

class _MobileLayout extends StatelessWidget {
  final CouponModel coupon;
  final double height;
  final bool hovered;
  final bool showChips;

  const _MobileLayout({
    required this.coupon,
    required this.height,
    required this.hovered,
    required this.showChips,
  });

  @override
  Widget build(BuildContext context) {
    final imgH = height * 0.42;
    return Column(
      children: [
        SizedBox(
          height: imgH,
          child: _ImagePanel(coupon: coupon),
        ),
        Expanded(
          child: _TextPanel(
            coupon: coupon,
            hovered: hovered,
            isMobile: true,
            showChips: false,
          ),
        ),
      ],
    );
  }
}

// ── Desktop/tablet layout: text left (60%) | image right (40%) ───────────────────

class _DesktopLayout extends StatelessWidget {
  final CouponModel coupon;
  final double height;
  final bool hovered;
  final bool showChips;

  const _DesktopLayout({
    required this.coupon,
    required this.height,
    required this.hovered,
    required this.showChips,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Row(
          children: [
            Expanded(
              flex: 60,
              child: _TextPanel(
                coupon: coupon,
                hovered: hovered,
                isMobile: false,
                showChips: showChips,
              ),
            ),
            Expanded(
              flex: 40,
              child: _ImagePanel(coupon: coupon),
            ),
          ],
        ),
        // Gold accent line on the left edge
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: Container(
            width: 4,
            decoration: const BoxDecoration(
              color: AppColors.gold,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(_kRadius),
                bottomLeft: Radius.circular(_kRadius),
              ),
            ),
          ),
        ),
        // Decorative circle — top-right corner
        Positioned(
          right: -50,
          top: -50,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.gold.withAlpha(14),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Text panel ───────────────────────────────────────────────────────────────────

class _TextPanel extends StatelessWidget {
  final CouponModel coupon;
  final bool hovered;
  final bool isMobile;
  final bool showChips;

  const _TextPanel({
    required this.coupon,
    required this.hovered,
    required this.isMobile,
    required this.showChips,
  });

  List<String> get _chips {
    final chips = <String>[];
    final expiry = coupon.expiryLabel;
    if (expiry != 'No expiry') chips.add('✓  $expiry');
    if (coupon.minOrderAmount != null) {
      chips.add('✓  Min ₹${coupon.minOrderAmount!.toStringAsFixed(0)}');
    }
    if (chips.isEmpty) chips.add('✓  Verified Offer');
    return chips;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFDF7), Color(0xFFFFF6DA)],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, bc) {
          final w = bc.maxWidth;
          final pad =
              isMobile ? 18.0 : (w < 300 ? 20.0 : (w < 420 ? 26.0 : 30.0));
          final titleSize =
              isMobile ? 22.0 : (w < 300 ? 20.0 : (w < 420 ? 26.0 : 30.0));
          final descSize = isMobile ? 12.0 : 13.5;

          return Padding(
            padding: EdgeInsets.all(pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Gold "SPECIAL OFFER" badge ─────────────────────────
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.gold,
                    borderRadius: BorderRadius.circular(5),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.gold.withAlpha(90),
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Text(
                    'SPECIAL OFFER',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      height: 1.2,
                    ),
                  ),
                ),
                SizedBox(height: isMobile ? 12 : 16),

                // ── Discount as large title ────────────────────────────
                Text(
                  coupon.discountLabel,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: titleSize,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    letterSpacing: -0.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                // ── Description ────────────────────────────────────────
                if (coupon.description?.isNotEmpty == true) ...[
                  SizedBox(height: isMobile ? 6 : 8),
                  Text(
                    coupon.description!,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: descSize,
                      height: 1.5,
                    ),
                    maxLines: isMobile ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                // ── Validity + conditions chips (desktop only) ─────────
                if (showChips) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children:
                        _chips.map((c) => _BenefitChip(c)).toList(),
                  ),
                ],

                // ── Coupon code CTA ────────────────────────────────────
                SizedBox(height: isMobile ? 12 : 16),
                _CodeButton(code: coupon.code, hovered: hovered),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Image panel ──────────────────────────────────────────────────────────────────

class _ImagePanel extends StatelessWidget {
  final CouponModel coupon;

  const _ImagePanel({required this.coupon});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            _resolveImage(coupon),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, _, _) => const _FallbackImage(),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withAlpha(110),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.38],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FallbackImage extends StatelessWidget {
  const _FallbackImage();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.gold.withAlpha(38),
            AppColors.gold.withAlpha(12),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.home_repair_service_rounded,
          size: 64,
          color: AppColors.gold.withAlpha(100),
        ),
      ),
    );
  }
}

// ── Benefit chip ─────────────────────────────────────────────────────────────────

class _BenefitChip extends StatelessWidget {
  final String label;
  const _BenefitChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.gold.withAlpha(28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.gold.withAlpha(80), width: 1),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
    );
  }
}

// ── Code CTA button — copies coupon code to clipboard on tap ─────────────────────

class _CodeButton extends StatelessWidget {
  final String code;
  final bool hovered;

  const _CodeButton({required this.code, this.hovered = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: code));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Code "$code" copied!'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, hovered ? -3 : 0, 0),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
        decoration: BoxDecoration(
          color: hovered ? const Color(0xFFEDD053) : AppColors.gold,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: AppColors.gold.withAlpha(hovered ? 130 : 80),
              blurRadius: hovered ? 22 : 14,
              offset: Offset(0, hovered ? 8 : 4),
            ),
          ],
        ),
        child: Text(
          'Use Code: $code →',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

// ── Gold dot indicators (mobile only) ───────────────────────────────────────────

class _DotIndicator extends StatelessWidget {
  final int count;
  final int current;

  const _DotIndicator({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 20 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active ? AppColors.gold : AppColors.border,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
