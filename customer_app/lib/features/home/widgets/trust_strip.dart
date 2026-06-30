import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class TrustStrip extends StatelessWidget {
  const TrustStrip({super.key});

  static const _items = <(IconData, String)>[
    (Icons.verified_rounded, 'Verified Vendors'),
    (Icons.flash_on_rounded, 'Instant Booking'),
    (Icons.receipt_long_rounded, 'Transparent Pricing'),
    (Icons.shield_rounded, 'Background Verified'),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return ColoredBox(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
          if (width >= 600) const _DesktopLayout() else const _MobileLayout(),
          const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
        ],
      ),
    );
  }
}

// ── Desktop: horizontal centered row ─────────────────────────────────────────

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < TrustStrip._items.length; i++) ...[
            _TrustItem(
              icon: TrustStrip._items[i].$1,
              label: TrustStrip._items[i].$2,
            ),
            if (i < TrustStrip._items.length - 1)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 28),
                width: 1,
                height: 18,
                color: AppColors.border,
              ),
          ],
        ],
      ),
    );
  }
}

// ── Mobile: horizontally scrollable chips ─────────────────────────────────────

class _MobileLayout extends StatelessWidget {
  const _MobileLayout();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ScrollConfiguration(
        behavior: _TrustScrollBehavior(),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          itemCount: TrustStrip._items.length,
          itemBuilder: (_, i) => Padding(
            padding: EdgeInsets.only(
              right: i < TrustStrip._items.length - 1 ? 10 : 0,
            ),
            child: _TrustChip(
              icon: TrustStrip._items[i].$1,
              label: TrustStrip._items[i].$2,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Desktop trust item ────────────────────────────────────────────────────────

class _TrustItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TrustItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: AppColors.goldLight,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 13, color: AppColors.gold),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

// ── Mobile pill chip ──────────────────────────────────────────────────────────

class _TrustChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TrustChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.goldLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.gold.withAlpha(60),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.gold),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Scroll behavior ───────────────────────────────────────────────────────────

class _TrustScrollBehavior extends MaterialScrollBehavior {
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
