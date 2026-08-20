import 'dart:ui' show ImageFilter;
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

// ── Default items ─────────────────────────────────────────────────────────────

const _kDefaultItems = [
  _TrustGridItem(
    icon: Icons.verified_user_outlined,
    title: 'Verified Professionals',
    description:
        'All professionals are verified, trained and experienced.',
    hasDivider: true,
  ),
  _TrustGridItem(
    icon: Icons.sell_outlined,
    title: 'Transparent Pricing',
    description: 'No hidden charges. Know the price before you book.',
    hasDivider: true,
  ),
  _TrustGridItem(
    icon: Icons.checklist_outlined,
    title: 'Services for Every Need',
    description:
        'From cleaning to repairs, we have every service you need.',
    hasDivider: false,
  ),
  _TrustGridItem(
    icon: Icons.access_time_outlined,
    title: 'On-Time & Reliable',
    description: 'We value your time and ensure on-time service every time.',
    hasDivider: false,
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

  final String? title;
  final String? subtitle;
  final List<WhyDodoItem>? items;

  @override
  Widget build(BuildContext context) {
    final effectiveTitle = title ?? 'Why People Choose DODO?';

    final List<_TrustGridItem> gridItems;
    final cmsList = items;
    if (cmsList != null && cmsList.isNotEmpty) {
      gridItems = [
        for (int i = 0; i < cmsList.length; i++)
          _TrustGridItem(
            icon: cmsList[i].icon,
            title: cmsList[i].title,
            description: cmsList[i].description,
            hasDivider: i < (cmsList.length ~/ 2),
          ),
      ];
    } else {
      gridItems = _kDefaultItems;
    }

    final w = MediaQuery.sizeOf(context).width;
    final isDesktop = w >= 768;
    final hPad = (w * 0.05).clamp(24.0, 64.0);
    final vPad = isDesktop ? 96.0 : 64.0;

    return ClipRect(
      child: Stack(
      children: [
        // ── Background image: heavy blur + dark overlay ──────────────────
        Positioned.fill(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: 35,
              sigmaY: 35,
              tileMode: TileMode.clamp,
            ),
            child: Transform.scale(
              scale: 1.2,
              child: Image.asset(
                'assets/images/hero-bg.png',
                fit: BoxFit.cover,
                color: Colors.black.withOpacity(0.25),
                colorBlendMode: BlendMode.srcATop,
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: Color(0xFF111111)),
              ),
            ),
          ),
        ),
        // ── Primary dark overlay (rgba(17,17,17,0.45)) ───────────────────
        Positioned.fill(
          child: ColoredBox(
            color: const Color(0xFF111111).withOpacity(0.50),
          ),
        ),
        // ── Content ──────────────────────────────────────────────────────
        Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: isDesktop
                  ? _DesktopLayout(
                      items: gridItems,
                      title: effectiveTitle,
                    )
                  : _MobileLayout(
                      items: gridItems,
                      title: effectiveTitle,
                    ),
            ),
          ),
        ),
      ],
      ),
    );
  }
}

// ── Desktop two-column layout ─────────────────────────────────────────────────

class _DesktopLayout extends StatelessWidget {
  final List<_TrustGridItem> items;
  final String title;

  const _DesktopLayout({required this.items, required this.title});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final gap = (w * 0.05).clamp(32.0, 64.0);

    // Split title at "DODO?" to colorize
    final goldenWord = 'DODO?';
    final beforeGold = title.contains(goldenWord)
        ? title.substring(0, title.indexOf(goldenWord))
        : title;
    final afterGold =
        title.contains(goldenWord) ? goldenWord : '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Left column ─────────────────────────────────────────────────
        Expanded(
          flex: 38,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Heading
              Text.rich(
                TextSpan(
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w800,
                    fontSize: 36,
                    color: Colors.white,
                    height: 1.2,
                  ),
                  children: [
                    TextSpan(text: beforeGold),
                    TextSpan(
                      text: afterGold,
                      style: const TextStyle(color: AppColors.gold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Gold underline bar
              Container(
                width: 56,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 28),
              // Trust badge card
              _TrustBadgeCard(),
            ],
          ),
        ),
        SizedBox(width: gap),
        // ── Right column: 2×2 grid ──────────────────────────────────────
        Expanded(
          flex: 62,
          child: _TrustGrid(items: items),
        ),
      ],
    );
  }
}

// ── Mobile single-column layout ───────────────────────────────────────────────

class _MobileLayout extends StatelessWidget {
  final List<_TrustGridItem> items;
  final String title;

  const _MobileLayout({required this.items, required this.title});

  @override
  Widget build(BuildContext context) {
    final goldenWord = 'DODO?';
    final beforeGold = title.contains(goldenWord)
        ? title.substring(0, title.indexOf(goldenWord))
        : title;
    final afterGold = title.contains(goldenWord) ? goldenWord : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w800,
              fontSize: 28,
              color: Colors.white,
              height: 1.2,
            ),
            children: [
              TextSpan(text: beforeGold),
              TextSpan(
                text: afterGold,
                style: const TextStyle(color: AppColors.gold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: 48,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.gold,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 24),
        _TrustBadgeCard(),
        const SizedBox(height: 32),
        // Items in single column
        for (int i = 0; i < items.length; i++) ...[
          _TrustItemTile(item: items[i]),
          if (i < items.length - 1)
            const Divider(color: Color(0xFF2A2622), height: 32),
        ],
      ],
    );
  }
}

// ── Trust badge card ──────────────────────────────────────────────────────────

class _TrustBadgeCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1714),
          border: Border.all(color: const Color(0xFF2A2622)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.gold, width: 1.5),
              ),
              child: const Icon(
                Icons.verified_user_outlined,
                color: AppColors.gold,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trusted by thousands',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'for quality home services',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF9A948C),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 2×2 Trust grid (desktop) ──────────────────────────────────────────────────

class _TrustGrid extends StatelessWidget {
  final List<_TrustGridItem> items;

  const _TrustGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    final half = (items.length / 2).ceil();
    final topRow = items.take(half).toList();
    final bottomRow = items.skip(half).toList();
    final colGap = 48.0;

    return Column(
      children: [
        // Top row
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < topRow.length; i++) ...[
              if (i > 0) SizedBox(width: colGap),
              Expanded(
                child: _TrustItemTile(item: topRow[i]),
              ),
            ],
          ],
        ),
        // Divider between rows
        if (topRow.any((e) => e.hasDivider))
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Divider(color: Color(0xFF2A2622), height: 1),
          )
        else
          const SizedBox(height: 28),
        // Bottom row
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < bottomRow.length; i++) ...[
              if (i > 0) SizedBox(width: colGap),
              Expanded(
                child: _TrustItemTile(item: bottomRow[i]),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// ── Single trust item ─────────────────────────────────────────────────────────

class _TrustItemTile extends StatelessWidget {
  final _TrustGridItem item;

  const _TrustItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Gold-ring circle with icon
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.gold, width: 1.5),
          ),
          child: Icon(
            item.icon,
            color: AppColors.gold,
            size: 22,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                item.title,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                item.description,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF9A948C),
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Internal data model ───────────────────────────────────────────────────────

class _TrustGridItem {
  final IconData icon;
  final String title;
  final String description;
  final bool hasDivider;

  const _TrustGridItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.hasDivider,
  });
}
