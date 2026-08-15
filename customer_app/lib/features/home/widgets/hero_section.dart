import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';

class HeroSection extends StatefulWidget {
  final VoidCallback onBookNow;
  final VoidCallback onExplore;

  const HeroSection({
    super.key,
    required this.onBookNow,
    required this.onExplore,
  });

  @override
  State<HeroSection> createState() => _HeroSectionState();
}

class _HeroSectionState extends State<HeroSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return FadeTransition(
      opacity: _fadeAnim,
      child: width >= 768
          ? _WebHero(onContinue: widget.onBookNow)
          : _MobileHero(onGetStarted: widget.onBookNow),
    );
  }
}

// ── Web Hero ─────────────────────────────────────────────────────────────────

class _WebHero extends StatelessWidget {
  final VoidCallback onContinue;
  const _WebHero({required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final hPad = w >= 1024 ? 80.0 : 40.0;

    return Container(
      width: double.infinity,
      color: const Color(0xFF111111),
      padding: const EdgeInsets.symmetric(vertical: 72),
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 55,
                  child: _WebContent(onContinue: onContinue),
                ),
                const SizedBox(width: 48),
                Expanded(
                  flex: 45,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Image.asset(
                        'assets/images/dodo-mascot.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
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

class _WebContent extends StatelessWidget {
  final VoidCallback onContinue;
  const _WebContent({required this.onContinue});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Trust badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1B17),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(
            '✓ Trusted Home Services',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.gold,
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Headline
        Text.rich(
          TextSpan(
            style: GoogleFonts.poppins(
              fontSize: 44,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.12,
              letterSpacing: -0.5,
            ),
            children: const [
              TextSpan(text: 'Are you looking for '),
              TextSpan(
                text: 'home service?',
                style: TextStyle(color: AppColors.gold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Body
        Text(
          'Let us take care of it. Book a trusted professional in just a few taps.',
          style: GoogleFonts.inter(
            fontSize: 15,
            color: const Color(0xFFB3ADA3),
            height: 1.6,
          ),
        ),
        const SizedBox(height: 8),

        // Hint
        Text(
          "We'll show services for your location",
          style: GoogleFonts.inter(
            fontSize: 13,
            color: const Color(0xFF7A756D),
          ),
        ),
        const SizedBox(height: 20),

        // Location input pill (visual only)
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: Color(0xFF9A948C),
                ),
                const SizedBox(width: 8),
                Text(
                  'Enter your location or select from map',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFF9A948C),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Continue CTA
        _ContinueButton(onTap: onContinue),
      ],
    );
  }
}

class _ContinueButton extends StatefulWidget {
  final VoidCallback onTap;
  const _ContinueButton({required this.onTap});

  @override
  State<_ContinueButton> createState() => _ContinueButtonState();
}

class _ContinueButtonState extends State<_ContinueButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          decoration: BoxDecoration(
            color: _hovered
                ? const Color(0xFF2A2622)
                : const Color(0xFF1E1B17),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: const Color(0xFF2A2622)),
          ),
          child: Text(
            'Continue',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Mobile Hero ──────────────────────────────────────────────────────────────

class _MobileHero extends StatelessWidget {
  final VoidCallback onGetStarted;
  const _MobileHero({required this.onGetStarted});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF111111),
      child: Stack(
        children: [
          // Watermark "SERV / ICE" in the background
          Positioned(
            top: 20,
            left: 20,
            child: IgnorePointer(
              child: Text(
                'SERV\nICE',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w800,
                  fontSize: 72,
                  color: const Color(0xFF1E1B17),
                  height: 0.95,
                  letterSpacing: -1.5,
                ),
              ),
            ),
          ),

          // Main content column
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo row
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'DODO BOOKER',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Mascot
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 280,
                      maxHeight: 220,
                    ),
                    child: Image.asset(
                      'assets/images/dodo-mascot.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const SizedBox(height: 180),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Headline
                Text.rich(
                  TextSpan(
                    style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.15,
                    ),
                    children: const [
                      TextSpan(text: 'Are you looking for '),
                      TextSpan(
                        text: 'home service?',
                        style: TextStyle(color: AppColors.gold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Body
                Text(
                  'Let us take care of it. Book trusted professionals in just a few taps.',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFFB3ADA3),
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 28),

                // Get Started pill
                _GetStartedButton(onTap: onGetStarted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GetStartedButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GetStartedButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(100),
        ),
        padding: const EdgeInsets.only(left: 26, right: 5, top: 5, bottom: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Get Started',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(100),
              ),
              child: const Icon(
                Icons.arrow_forward_rounded,
                color: AppColors.gold,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
