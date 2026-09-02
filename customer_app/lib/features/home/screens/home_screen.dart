import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/nav_search.dart';
import '../../auth/providers/auth_provider.dart';
import '../../booking/services/coupon_providers.dart';
import '../../loyalty/providers/loyalty_providers.dart';
import '../../profile/services/profile_providers.dart';
import '../models/landing_page_section.dart';
import '../services/home_providers.dart';
import '../services/landing_page_sections_provider.dart';
import '../widgets/mobile_home_sections.dart';
import '../widgets/section_renderer.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.showMobileHeader = false});
  final bool showMobileHeader;

  Future<void> _onRefresh(WidgetRef ref) async {
    ref.invalidate(landingPageSectionsProvider);
    ref.invalidate(activeCouponsProvider);
    ref.invalidate(featuredCatalogNodesProvider);
    ref.invalidate(featuredServicesProvider);
    ref.invalidate(trendingServicesProvider);
    ref.invalidate(popularServicesProvider);
    ref.invalidate(newServicesProvider);
    ref.invalidate(homeReviewsProvider);
    try {
      await ref.read(landingPageSectionsProvider.future);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sectionsAsync = ref.watch(landingPageSectionsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.gold,
          onRefresh: () => _onRefresh(ref),
          child: ScrollConfiguration(
            behavior:
                ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: sectionsAsync.when(
              loading: () => _buildBody(context, ref, null),
              error: (error, _) => _buildBody(context, ref, []),
              data: (sections) => _buildBody(context, ref, sections),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    List<LandingPageSection>? sections,
  ) {
    final effectiveSections = sections ?? const <LandingPageSection>[];
    final isMobile = MediaQuery.sizeOf(context).width < 768;

    // ── Mobile: custom mobile layout, no footer ───────────────────────────────
    if (showMobileHeader && isMobile) {
      final mobileSections = effectiveSections
          .where((s) => s.sectionType != 'hero' && s.sectionType != 'footer')
          .toList();

      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: _MobileHomeGreeting()),
          const SliverToBoxAdapter(child: _MobileSearchPill()),
          if (sections == null)
            const SliverToBoxAdapter(child: SizedBox(height: 200)),
          for (final section in mobileSections)
            SliverToBoxAdapter(
              child: MobileHomeSectionRenderer(section: section),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      );
    }

    // ── Web / tablet: original CMS layout with footer ─────────────────────────
    LandingPageSection? footerSection;
    final bodySections = <LandingPageSection>[];
    for (final s in effectiveSections) {
      if (s.sectionType == 'footer') {
        footerSection ??= s;
      } else {
        bodySections.add(s);
      }
    }

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (sections == null)
          const SliverToBoxAdapter(child: SizedBox(height: 200)),

        for (final section in bodySections)
          ..._sectionSlivers(section),

        SliverFillRemaining(
          hasScrollBody: false,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (footerSection != null)
                SectionRenderer(section: footerSection),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _sectionSlivers(LandingPageSection section) {
    if (section.sectionType == 'hero') {
      return [
        SliverToBoxAdapter(
          child: ColoredBox(
            color: const Color(0xFF111111),
            child: SectionRenderer(section: section),
          ),
        ),
      ];
    }

    if (SectionRenderer.isFullWidth(section.sectionType)) {
      return [
        const SliverToBoxAdapter(child: SizedBox(height: 48)),
        SliverToBoxAdapter(child: SectionRenderer(section: section)),
      ];
    }

    return [
      const SliverToBoxAdapter(child: SizedBox(height: 28)),
      SliverToBoxAdapter(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: SectionRenderer(section: section),
          ),
        ),
      ),
    ];
  }
}

// ── Mobile home greeting ──────────────────────────────────────────────────────

class _MobileHomeGreeting extends ConsumerWidget {
  const _MobileHomeGreeting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAuth = ref.watch(isAuthenticatedProvider);
    final profileAsync = ref.watch(profileProvider);
    final points = ref.watch(customerLoyaltyProvider).whenOrNull(
          data: (l) => l.availablePoints,
        );

    String firstName = '';
    profileAsync.whenData((p) {
      if (p.fullName.isNotEmpty) {
        firstName = p.fullName.trim().split(' ').first;
      }
    });

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              isAuth && firstName.isNotEmpty ? 'Hello, $firstName!' : 'Hello!',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1714),
              ),
            ),
          ),
          if (isAuth && points != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: const Color(0xFFFFD700).withAlpha(100), width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.stars_rounded,
                      size: 14, color: Color(0xFFFFD700)),
                  const SizedBox(width: 4),
                  Text(
                    '$points',
                    style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Mobile search pill ────────────────────────────────────────────────────────

class _MobileSearchPill extends StatelessWidget {
  const _MobileSearchPill();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: GestureDetector(
        onTap: () => showMobileSearch(context),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: const Color(0xFFECE7DE)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              const Icon(Icons.search_rounded,
                  size: 20, color: Color(0xFF9A948C)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Search for a service...',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFF9A948C),
                  ),
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F2EE),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: const Icon(Icons.tune_rounded,
                    size: 16, color: Color(0xFF6E6A64)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
