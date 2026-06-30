import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/service_image_registry.dart';
import '../services/home_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public entry point
// ─────────────────────────────────────────────────────────────────────────────

class HeroSection extends ConsumerStatefulWidget {
  final VoidCallback onBookNow;
  final VoidCallback onExplore;

  const HeroSection({
    super.key,
    required this.onBookNow,
    required this.onExplore,
  });

  @override
  ConsumerState<HeroSection> createState() => _HeroSectionState();
}

class _HeroSectionState extends ConsumerState<HeroSection>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final AnimationController _floatCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _floatAnim;

  @override
  void initState() {
    super.initState();

    // One-shot fade-in
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    // Looping float — collage gently bobs ±7 px
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: -7.0, end: 7.0).animate(
      CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _floatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return FadeTransition(
      opacity: _fadeAnim,
      child: width >= 960
          ? _DesktopHero(
              floatAnim: _floatAnim,
              onBookNow: widget.onBookNow,
              onExplore: widget.onExplore,
            )
          : _MobileHero(
              floatAnim: _floatAnim,
              onBookNow: widget.onBookNow,
              onExplore: widget.onExplore,
            ),
    );
  }
}

// ── Desktop two-column layout ─────────────────────────────────────────────────

class _DesktopHero extends StatelessWidget {
  final Animation<double> floatAnim;
  final VoidCallback onBookNow;
  final VoidCallback onExplore;

  const _DesktopHero({
    required this.floatAnim,
    required this.onBookNow,
    required this.onExplore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFFDF8ED)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEEE8D5), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(52, 52, 20, 52),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 52,
            child: _HeroContent(
              onBookNow: onBookNow,
              onExplore: onExplore,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 48,
            child: Center(
              child: AnimatedBuilder(
                animation: floatAnim,
                builder: (_, child) => Transform.translate(
                  offset: Offset(0, floatAnim.value),
                  child: child,
                ),
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: 530, maxHeight: 570),
                  child: const _ServiceEcosystem(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mobile single-column layout ───────────────────────────────────────────────

class _MobileHero extends StatelessWidget {
  final Animation<double> floatAnim;
  final VoidCallback onBookNow;
  final VoidCallback onExplore;

  const _MobileHero({
    required this.floatAnim,
    required this.onBookNow,
    required this.onExplore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFFDF8ED)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEEE8D5), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(22, 32, 22, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeroContent(onBookNow: onBookNow, onExplore: onExplore),
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: floatAnim,
            builder: (_, child) => Transform.translate(
              offset: Offset(0, floatAnim.value),
              child: child,
            ),
            child: const SizedBox(
              height: 300,
              child: _ServiceEcosystem(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared left-panel content ─────────────────────────────────────────────────

class _HeroContent extends StatelessWidget {
  final VoidCallback onBookNow;
  final VoidCallback onExplore;

  const _HeroContent({required this.onBookNow, required this.onExplore});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 960;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Gold accent bar
        Container(
          width: isDesktop ? 48 : 36,
          height: 3,
          decoration: BoxDecoration(
            color: AppColors.gold,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 18),

        // Headline
        Text(
          'Book Trusted Services\nat Your Doorstep',
          style: TextStyle(
            fontSize: isDesktop ? 48 : 30,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            height: 1.1,
            letterSpacing: isDesktop ? -1.2 : -0.5,
          ),
        ),
        SizedBox(height: isDesktop ? 16 : 12),

        // Description
        Text(
          'Professional experts for your everyday needs.\nFast booking, transparent pricing, and verified professionals.',
          style: TextStyle(
            fontSize: isDesktop ? 15.5 : 14,
            color: AppColors.textSecondary,
            height: 1.65,
          ),
        ),
        SizedBox(height: isDesktop ? 40 : 28),

        // CTA buttons
        Wrap(
          spacing: 14,
          runSpacing: 12,
          children: [
            _BookNowButton(onTap: onBookNow, large: isDesktop),
            _ExploreButton(onTap: onExplore, large: isDesktop),
          ],
        ),
      ],
    );
  }
}

// ── Book Now — gold primary with InkWell ripple ───────────────────────────────

class _BookNowButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool large;

  const _BookNowButton({required this.onTap, required this.large});

  @override
  Widget build(BuildContext context) {
    final hPad = large ? 28.0 : 22.0;
    final vPad = large ? 15.0 : 13.0;
    final fontSize = large ? 15.0 : 14.0;

    return Material(
      color: AppColors.gold,
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      shadowColor: AppColors.gold.withAlpha(100),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: Colors.white.withAlpha(70),
        highlightColor: Colors.transparent,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_today_rounded,
                size: large ? 16 : 14,
                color: Colors.black,
              ),
              const SizedBox(width: 8),
              Text(
                'Book Now',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Explore Services — outlined secondary ─────────────────────────────────────

class _ExploreButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool large;

  const _ExploreButton({required this.onTap, required this.large});

  @override
  State<_ExploreButton> createState() => _ExploreButtonState();
}

class _ExploreButtonState extends State<_ExploreButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hPad = widget.large ? 26.0 : 20.0;
    final vPad = widget.large ? 14.0 : 12.0;
    final fontSize = widget.large ? 15.0 : 14.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(14),
          splashColor: AppColors.gold.withAlpha(40),
          highlightColor: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _hovered
                    ? AppColors.textPrimary
                    : AppColors.textPrimary.withAlpha(140),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Explore Services',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSlide(
                  offset: _hovered
                      ? const Offset(0.15, 0)
                      : Offset.zero,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: widget.large ? 16 : 14,
                    color: AppColors.textPrimary,
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

// ══════════════════════════════════════════════════════════════════════════════
// Service Ecosystem — orbital collage (unchanged visual logic)
// ══════════════════════════════════════════════════════════════════════════════

class _NodeDef {
  final String label;
  final double angle;
  final String fallbackPhotoId;

  const _NodeDef({
    required this.label,
    required this.angle,
    required this.fallbackPhotoId,
  });
}

class _ServiceEcosystem extends ConsumerWidget {
  const _ServiceEcosystem();

  // True hexagonal layout — 60° between every neighbor
  static const _nodes = [
    _NodeDef(
      label: 'Cleaning',
      angle: 0,
      fallbackPhotoId: 'photo-1581578731548-c64695cc6952',
    ),
    _NodeDef(
      label: 'Plumbing',
      angle: 60,
      fallbackPhotoId: 'photo-1676210133055-eab6ef033ce3',
    ),
    _NodeDef(
      label: 'EV Services',
      angle: 120,
      fallbackPhotoId: 'photo-1593941707882-a5bba14938c7',
    ),
    _NodeDef(
      label: 'Carpentry',
      angle: 180,
      fallbackPhotoId: 'photo-1504148455328-c376907d081c',
    ),
    _NodeDef(
      label: 'AC Repair',
      angle: 240,
      fallbackPhotoId: 'photo-1762341123870-d706f257a12e',
    ),
    _NodeDef(
      label: 'Electrical',
      angle: 300,
      fallbackPhotoId: 'photo-1621905251189-08b45d6a269e',
    ),
  ];

  static String _unsplash(String id) =>
      'https://images.unsplash.com/$id'
      '?auto=format&fit=crop&crop=entropy&w=320&h=320&q=80';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(featuredCategoriesProvider).asData?.value ?? [];

    final catImages = <String, String>{};
    for (final cat in cats) {
      catImages[cat.name.toLowerCase().trim()] =
          ServiceImageRegistry.resolve(cat.imageUrl, cat.name);
    }

    final resolved = <String, String>{};
    for (final node in _nodes) {
      final key = node.label.toLowerCase();
      String? url = catImages[key];
      if (url == null) {
        for (final e in catImages.entries) {
          if (e.key.contains(key) || key.contains(e.key)) {
            url = e.value;
            break;
          }
        }
      }
      resolved[node.label] = url ?? _unsplash(node.fallbackPhotoId);
    }

    return LayoutBuilder(
      builder: (_, constraints) {
        final w = constraints.maxWidth;
        final h = math.min(w * 1.065, constraints.maxHeight);
        return _EcosystemCanvas(
          width: w,
          height: h,
          nodes: _nodes,
          resolvedImages: resolved,
        );
      },
    );
  }
}

// ── Canvas ────────────────────────────────────────────────────────────────────

class _EcosystemCanvas extends StatelessWidget {
  final double width;
  final double height;
  final List<_NodeDef> nodes;
  final Map<String, String> resolvedImages;

  const _EcosystemCanvas({
    required this.width,
    required this.height,
    required this.nodes,
    required this.resolvedImages,
  });

  @override
  Widget build(BuildContext context) {
    final w = width;
    final h = height;
    final orbit      = w * 0.400;
    final nodeDiam   = w * 0.178;
    final centerDiam = w * 0.230;
    final colWidth   = nodeDiam * 1.32;
    final cxC = w / 2;
    final cyC = h / 2;

    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Rings + dashed connectors
          Positioned.fill(
            child: CustomPaint(
              painter: _EcosystemPainter(
                nodeAngles: nodes.map((n) => n.angle).toList(),
                orbitRadius: orbit,
              ),
            ),
          ),

          // Outer glow halo
          Positioned(
            left: cxC - centerDiam * 0.76,
            top:  cyC - centerDiam * 0.76,
            child: Container(
              width:  centerDiam * 1.52,
              height: centerDiam * 1.52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold.withAlpha(10),
              ),
            ),
          ),
          Positioned(
            left: cxC - centerDiam * 0.615,
            top:  cyC - centerDiam * 0.615,
            child: Container(
              width:  centerDiam * 1.23,
              height: centerDiam * 1.23,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold.withAlpha(20),
              ),
            ),
          ),

          // Service nodes
          for (final node in nodes) ...[
            () {
              final rad = node.angle * math.pi / 180;
              final cx = cxC + orbit * math.sin(rad);
              final cy = cyC - orbit * math.cos(rad);
              return Positioned(
                left: cx - colWidth / 2,
                top:  cy - nodeDiam / 2,
                child: _ServiceNode(
                  label: node.label,
                  imageUrl: resolvedImages[node.label] ?? '',
                  diameter: nodeDiam,
                  colWidth: colWidth,
                ),
              );
            }(),
          ],

          // Center home icon
          Positioned(
            left: cxC - centerDiam / 2,
            top:  cyC - centerDiam / 2,
            child: Container(
              width:  centerDiam,
              height: centerDiam,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.textPrimary,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(72),
                    blurRadius: 36,
                    spreadRadius: 3,
                    offset: const Offset(0, 14),
                  ),
                  BoxShadow(
                    color: AppColors.gold.withAlpha(45),
                    blurRadius: 32,
                  ),
                ],
              ),
              child: Icon(
                Icons.home_rounded,
                color: Colors.white,
                size: centerDiam * 0.48,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Rings + dashed connector painter ─────────────────────────────────────────

class _EcosystemPainter extends CustomPainter {
  final List<double> nodeAngles;
  final double orbitRadius;

  const _EcosystemPainter({
    required this.nodeAngles,
    required this.orbitRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    void ring(double r, double stroke, int alpha) {
      canvas.drawCircle(
        center, r,
        Paint()
          ..color = const Color(0xFFD4AF37).withAlpha(alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
    }

    ring(orbitRadius * 0.27, 1.2, 65);
    ring(orbitRadius * 0.57, 1.2, 45);
    ring(orbitRadius * 1.00, 2.0, 35);

    final linePaint = Paint()
      ..color = const Color(0xFFD4AF37).withAlpha(42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    final innerSkip = orbitRadius * 0.145;
    final outerStop = orbitRadius * 0.840;

    for (final deg in nodeAngles) {
      final rad = deg * math.pi / 180;
      final dx = math.sin(rad);
      final dy = -math.cos(rad);
      _dashed(
        canvas,
        center + Offset(dx * innerSkip, dy * innerSkip),
        center + Offset(dx * outerStop, dy * outerStop),
        linePaint,
      );
    }
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    final total = (b - a).distance;
    final dir   = (b - a) / total;
    const dash  = 4.0;
    const gap   = 4.0;
    var pos = 0.0;
    while (pos < total) {
      final end = math.min(pos + dash, total);
      canvas.drawLine(a + dir * pos, a + dir * end, paint);
      pos += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_EcosystemPainter old) =>
      old.orbitRadius != orbitRadius;
}

// ── Individual service node ───────────────────────────────────────────────────

class _ServiceNode extends StatefulWidget {
  final String label;
  final String imageUrl;
  final double diameter;
  final double colWidth;

  const _ServiceNode({
    required this.label,
    required this.imageUrl,
    required this.diameter,
    required this.colWidth,
  });

  @override
  State<_ServiceNode> createState() => _ServiceNodeState();
}

class _ServiceNodeState extends State<_ServiceNode> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.diameter;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SizedBox(
        width: widget.colWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width:  d,
                height: d,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(
                    color: AppColors.gold.withAlpha(110),
                    width: 2.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(_hovered ? 24 : 14),
                      blurRadius: _hovered ? 14 : 8,
                      spreadRadius: 0,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.network(
                    widget.imageUrl,
                    fit: BoxFit.cover,
                    width:  d,
                    height: d,
                    loadingBuilder: (_, child, progress) =>
                        progress == null
                            ? child
                            : Container(color: AppColors.surfaceVariant),
                    errorBuilder: (_, _, _) => Container(
                      color: AppColors.surfaceVariant,
                      child: Icon(
                        Icons.home_repair_service_rounded,
                        size: d * 0.38,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: d * 0.148,
                fontWeight: _hovered ? FontWeight.w700 : FontWeight.w600,
                color: _hovered
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                letterSpacing: 0.1,
              ),
              child: Text(
                widget.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
