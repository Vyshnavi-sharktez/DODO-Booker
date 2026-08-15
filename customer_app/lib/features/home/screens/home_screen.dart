import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../booking/services/coupon_providers.dart';
import '../models/landing_page_section.dart';
import '../services/home_providers.dart';
import '../services/landing_page_sections_provider.dart';
import '../widgets/home_header_section.dart';
import '../widgets/section_renderer.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

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
              loading: () => _buildBody(context, null),
              error: (error, _) => _buildBody(context, []),
              data: (sections) => _buildBody(context, sections),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<LandingPageSection>? sections,
  ) {
    final effectiveSections = sections ?? const <LandingPageSection>[];

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // ── Persistent nav header (always top — not a CMS section) ───────────
        SliverToBoxAdapter(
          child: ColoredBox(
            color: const Color(0xFF111111),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final isDesktop = w >= 768;
                final hPad = isDesktop ? (w >= 1024 ? 80.0 : 40.0) : 24.0;
                final vPad = isDesktop ? 28.0 : 20.0;
                return Padding(
                  padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: HomeHeaderSection(
                      padding: EdgeInsets.only(top: vPad),
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        // ── Loading placeholder ───────────────────────────────────────────────
        if (sections == null)
          const SliverToBoxAdapter(child: SizedBox(height: 200)),

        // ── CMS sections rendered in exact display_order ──────────────────────
        for (final section in effectiveSections)
          ..._sectionSlivers(section),

        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  /// Returns the sliver(s) that represent one CMS section.
  ///
  /// Layout per type:
  ///   hero   → dark ColoredBox, full-width (seamless with nav header band)
  ///   footer → full browser width, 48 px top gap
  ///   others → 1280 px max-width column, 28 px top gap
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
