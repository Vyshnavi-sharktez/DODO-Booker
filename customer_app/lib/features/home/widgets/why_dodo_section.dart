import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/icon_resolver.dart';

// ── Public data model (used by CMS renderer) ──────────────────────────────────

class WhyDodoItem {
  final IconData icon;
  final String title;
  final String description;

  const WhyDodoItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  factory WhyDodoItem.fromMap(Map<String, dynamic> map) {
    return WhyDodoItem(
      icon: resolveIconData(map['icon'] as String?),
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
    );
  }
}

// ── Default items (approved Phase 1 numbered design) ─────────────────────────

const _kDefaultItems = [
  _TrustItem(
    number: '01',
    icon: Icons.verified_user_rounded,
    title: 'Verified Professionals',
    description:
        'Every service provider is background-checked and certified before joining our platform.',
    circleColor: AppColors.primary,
    circleTextColor: Colors.white,
  ),
  _TrustItem(
    number: '02',
    icon: Icons.receipt_long_rounded,
    title: 'Transparent Pricing',
    description:
        'No hidden charges — what you see is what you pay. Get instant quotes upfront.',
    circleColor: Color(0xFFD0CBC5),
    circleTextColor: AppColors.primary,
  ),
  _TrustItem(
    number: '03',
    icon: Icons.timer_rounded,
    title: 'Reliable & On-Time',
    description: 'We value your time. On-time, every time.',
    circleColor: AppColors.gold,
    circleTextColor: AppColors.primary,
  ),
];

// ── Widget ────────────────────────────────────────────────────────────────────

class WhyDodoSection extends StatelessWidget {
  const WhyDodoSection({
    super.key,
    this.title,
    this.subtitle,
    this.items,
  });

  /// Section heading. Defaults to 'Why Choose DODO Booker?'.
  final String? title;

  /// Sub-heading. Defaults to the approved copy.
  final String? subtitle;

  /// Trust items from CMS config. Falls back to hardcoded defaults when null.
  final List<WhyDodoItem>? items;

  @override
  Widget build(BuildContext context) {
    final effectiveTitle = title ?? 'Why Choose DODO Booker?';
    final effectiveSubtitle =
        subtitle ?? 'Everything you need for a seamless home services experience.';

    // Build the _TrustItem list from CMS items or fall back to approved defaults.
    // CMS items get auto-assigned numbered circles cycling through the approved palette.
    final List<_TrustItem> trustItems;
    final cmsList = items;
    if (cmsList != null && cmsList.isNotEmpty) {
      const bgs = [AppColors.primary, Color(0xFFD0CBC5), AppColors.gold];
      const fgs = [Colors.white, AppColors.primary, AppColors.primary];
      trustItems = [
        for (int i = 0; i < cmsList.length; i++)
          _TrustItem(
            number: (i + 1).toString().padLeft(2, '0'),
            icon: cmsList[i].icon,
            title: cmsList[i].title,
            description: cmsList[i].description,
            circleColor: bgs[i % bgs.length],
            circleTextColor: fgs[i % fgs.length],
          ),
      ];
    } else {
      trustItems = _kDefaultItems;
    }

    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 768;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 24 : 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: isDesktop
            ? _DesktopLayout(
                items: trustItems,
                title: effectiveTitle,
                subtitle: effectiveSubtitle,
              )
            : _MobileLayout(items: trustItems, title: effectiveTitle),
      ),
    );
  }
}

// ── Desktop two-column split ───────────────────────────────────────────────────

class _DesktopLayout extends StatelessWidget {
  final List<_TrustItem> items;
  final String title;
  final String subtitle;

  const _DesktopLayout({
    required this.items,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left dark panel
          Expanded(
            flex: 40,
            child: Container(
              color: const Color(0xFF111111),
              padding: const EdgeInsets.all(36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 3,
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.2,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.white.withAlpha(160),
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Right white panel
          Expanded(
            flex: 60,
            child: Container(
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(36, 36, 36, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < items.length; i++) ...[
                    _NumberedItem(item: items[i], isLast: i == items.length - 1),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mobile single-column ──────────────────────────────────────────────────────

class _MobileLayout extends StatelessWidget {
  final List<_TrustItem> items;
  final String title;

  const _MobileLayout({required this.items, required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dark header strip
          Container(
            width: double.infinity,
            color: const Color(0xFF111111),
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 2.5,
                  decoration: BoxDecoration(
                    color: AppColors.gold,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.25,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          // Numbered items
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  _NumberedItem(item: items[i], isLast: i == items.length - 1),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Numbered list item ────────────────────────────────────────────────────────

class _NumberedItem extends StatelessWidget {
  final _TrustItem item;
  final bool isLast;

  const _NumberedItem({required this.item, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Number circle + vertical connector
          Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: item.circleColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  item.number,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: item.circleTextColor,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1.5,
                    color: AppColors.border,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          // Text content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    item.title,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.description,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Internal data model ───────────────────────────────────────────────────────

class _TrustItem {
  final String number;
  final IconData icon;
  final String title;
  final String description;
  final Color circleColor;
  final Color circleTextColor;

  const _TrustItem({
    required this.number,
    required this.icon,
    required this.title,
    required this.description,
    required this.circleColor,
    required this.circleTextColor,
  });
}
