import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Horizontally scrollable carousel with adaptive arrow-button navigation.
///
/// Arrow visibility rules:
///   • At the start  → right arrow only.
///   • In the middle → both arrows.
///   • At the end    → left arrow only.
///   • Content fits without scrolling → no arrows.
///
/// Arrows animate in/out with opacity so transitions are smooth.
/// Normal touch / mouse / trackpad swiping is always supported.
class HorizontalCarousel extends StatefulWidget {
  const HorizontalCarousel({
    super.key,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    required this.scrollStep,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// Pixels advanced per arrow tap.  Pass roughly 3 × (cardWidth + cardGap).
  final double scrollStep;

  /// Padding applied to the inner list (left/right leading/trailing space).
  final EdgeInsets padding;

  @override
  State<HorizontalCarousel> createState() => _HorizontalCarouselState();
}

class _HorizontalCarouselState extends State<HorizontalCarousel> {
  final _ctrl = ScrollController();
  bool _canLeft = false;
  bool _canRight = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_sync);
    // Evaluate arrow state after the first frame so the list has laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  void _sync() {
    if (!_ctrl.hasClients) return;
    final max = _ctrl.position.maxScrollExtent;
    // No scrolling possible at all.
    if (max <= 1.0) {
      if (_canLeft || _canRight) setState(() { _canLeft = false; _canRight = false; });
      return;
    }
    final left  = _ctrl.offset > 1.0;
    final right = _ctrl.offset < max - 1.0;
    if (left != _canLeft || right != _canRight) {
      setState(() { _canLeft = left; _canRight = right; });
    }
  }

  void _go(double delta) {
    if (!_ctrl.hasClients) return;
    final target = (_ctrl.offset + delta)
        .clamp(0.0, _ctrl.position.maxScrollExtent);
    _ctrl.animateTo(
      target,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _ctrl.removeListener(_sync);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          // ── Scrollable list ────────────────────────────────────────
          ScrollConfiguration(
            behavior: const _CarouselScrollBehavior(),
            child: ListView.builder(
              controller: _ctrl,
              scrollDirection: Axis.horizontal,
              padding: widget.padding,
              itemCount: widget.itemCount,
              itemBuilder: widget.itemBuilder,
            ),
          ),

          // ── Left arrow ─────────────────────────────────────────────
          _CarouselArrow(
            visible: _canLeft,
            isLeft: true,
            onTap: () => _go(-widget.scrollStep),
          ),

          // ── Right arrow ────────────────────────────────────────────
          _CarouselArrow(
            visible: _canRight,
            isLeft: false,
            onTap: () => _go(widget.scrollStep),
          ),
        ],
      ),
    );
  }
}

// ── Arrow button ──────────────────────────────────────────────────────────────

class _CarouselArrow extends StatefulWidget {
  const _CarouselArrow({
    required this.visible,
    required this.isLeft,
    required this.onTap,
  });

  final bool visible;
  final bool isLeft;
  final VoidCallback onTap;

  @override
  State<_CarouselArrow> createState() => _CarouselArrowState();
}

class _CarouselArrowState extends State<_CarouselArrow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Align(
        alignment: widget.isLeft ? Alignment.centerLeft : Alignment.centerRight,
        child: Padding(
          padding: EdgeInsets.only(
            left: widget.isLeft ? 8 : 0,
            right: widget.isLeft ? 0 : 8,
          ),
          child: AnimatedOpacity(
            opacity: widget.visible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !widget.visible,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hovered = true),
                onExit:  (_) => setState(() => _hovered = false),
                child: GestureDetector(
                  onTap: widget.onTap,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _hovered ? const Color(0xFF1A1714) : Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(_hovered ? 70 : 38),
                          blurRadius: _hovered ? 16 : 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      widget.isLeft
                          ? Icons.arrow_back_ios_new_rounded
                          : Icons.arrow_forward_ios_rounded,
                      size: 15,
                      color: _hovered ? Colors.white : const Color(0xFF1A1714),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Shared scroll behavior ────────────────────────────────────────────────────

/// Enables pointer-device (mouse, trackpad, stylus) drag scrolling and hides
/// the scrollbar.  Used internally by [HorizontalCarousel].
class _CarouselScrollBehavior extends MaterialScrollBehavior {
  const _CarouselScrollBehavior();

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
