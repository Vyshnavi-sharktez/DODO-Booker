import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../features/catalog/utils/catalog_launcher.dart';
import '../../booking/services/coupon_providers.dart';
import '../models/landing_page_section.dart';
import '../services/home_providers.dart';
import 'content_grid_section.dart';
import 'cta_section.dart';
import 'customer_reviews_section.dart';
import 'faq_section.dart';
import 'footer_section.dart';
import 'hero_section.dart';
import 'home_categories_section.dart';
import 'how_it_works_section.dart';
import 'promo_banner_section.dart';
import 'special_offers_section.dart';
import 'sub_services_section.dart';
import 'trending_services_section.dart';
import 'why_dodo_section.dart';

// ── Public entry point ────────────────────────────────────────────────────────

/// Maps a [LandingPageSection] to its approved UI widget.
///
/// The [footer] type is flagged via [isFullWidth] — callers must render it
/// outside any max-width constraint box.
class SectionRenderer extends StatelessWidget {
  const SectionRenderer({super.key, required this.section});
  final LandingPageSection section;

  static bool isFullWidth(String sectionType) =>
      sectionType == 'footer' || sectionType == 'why_dodo';

  @override
  Widget build(BuildContext context) {
    return switch (section.sectionType) {
      'hero'           => _HeroRenderer(section: section),
      'service_grid'   => _ServiceGridRenderer(section: section),
      'sub_services'   => _SubServicesRenderer(section: section),
      'why_dodo'       => _WhyDodoRenderer(section: section),
      'how_it_works'   => _HowItWorksRenderer(section: section),
      'special_offers' => _SpecialOffersRenderer(section: section),
      'popular_near_you' => _PopularNearYouRenderer(section: section),
      'testimonials'   => _TestimonialsRenderer(section: section),
      'footer'         => const FooterSection(),
      'content_grid'   => ContentGridSection(config: section.config),
      'promo_banner'   => PromoBannerSection(config: section.config),
      'faq'            => FaqSection(config: section.config),
      'cta'            => CtaSection(config: section.config),
      _                => const SizedBox.shrink(),
    };
  }
}

// ── hero ──────────────────────────────────────────────────────────────────────

class _HeroRenderer extends StatelessWidget {
  const _HeroRenderer({required this.section});
  final LandingPageSection section;

  @override
  Widget build(BuildContext context) {
    return HeroSection(
      onBookNow: () => context.push('/categories'),
      onExplore: () => context.push('/categories'),
    );
  }
}

// ── service_grid ──────────────────────────────────────────────────────────────

class _ServiceGridRenderer extends ConsumerWidget {
  const _ServiceGridRenderer({required this.section});
  final LandingPageSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodes = ref.watch(featuredCatalogNodesProvider);
    return HomeCategoriesSection(
      asyncCategories: nodes,
      onCategorySelected: (n) => openCatalogNode(context, n),
      onSeeAll: () => context.push('/categories'),
    );
  }
}

// ── sub_services ──────────────────────────────────────────────────────────────

class _SubServicesRenderer extends ConsumerWidget {
  const _SubServicesRenderer({required this.section});
  final LandingPageSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(newServicesProvider);
    return SubServicesSection(
      asyncServices: services,
      title: section.config['title'] as String? ?? 'Sub Services',
      onServiceTap: (n) => openCatalogNode(context, n),
      onSeeAll: () => context.push('/categories'),
    );
  }
}

// ── why_dodo ──────────────────────────────────────────────────────────────────

class _WhyDodoRenderer extends StatelessWidget {
  const _WhyDodoRenderer({required this.section});
  final LandingPageSection section;

  @override
  Widget build(BuildContext context) {
    final rawItems = section.config['items'] as List?;
    final items = rawItems
        ?.map((e) => WhyDodoItem.fromMap(e as Map<String, dynamic>))
        .toList();

    return WhyDodoSection(
      title: section.config['title'] as String?,
      subtitle: section.config['subtitle'] as String?,
      items: items?.isNotEmpty == true ? items : null,
    );
  }
}

// ── how_it_works ──────────────────────────────────────────────────────────────

class _HowItWorksRenderer extends StatelessWidget {
  const _HowItWorksRenderer({required this.section});
  final LandingPageSection section;

  @override
  Widget build(BuildContext context) {
    final rawSteps = section.config['steps'] as List?;
    final steps = rawSteps
        ?.map((e) => HowItWorksStep.fromMap(e as Map<String, dynamic>))
        .toList();

    return HowItWorksSection(
      title: section.config['title'] as String?,
      steps: steps?.isNotEmpty == true ? steps : null,
    );
  }
}

// ── special_offers ────────────────────────────────────────────────────────────

class _SpecialOffersRenderer extends ConsumerWidget {
  const _SpecialOffersRenderer({required this.section});
  final LandingPageSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coupons = ref.watch(activeCouponsProvider);
    final hasOffers = coupons.isLoading ||
        (coupons.asData?.value.isNotEmpty ?? false);
    if (!hasOffers) return const SizedBox.shrink();
    return SpecialOffersSection(asyncCoupons: coupons);
  }
}

// ── popular_near_you ──────────────────────────────────────────────────────────

class _PopularNearYouRenderer extends ConsumerWidget {
  const _PopularNearYouRenderer({required this.section});
  final LandingPageSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(popularServicesProvider);
    return TrendingServicesSection(
      asyncServices: services,
      title: section.config['title'] as String? ?? 'Popular Near You',
      onServiceTap: (n) => openCatalogNode(context, n),
      onSeeAll: () => context.push('/categories'),
    );
  }
}

// ── testimonials ──────────────────────────────────────────────────────────────

class _TestimonialsRenderer extends ConsumerWidget {
  const _TestimonialsRenderer({required this.section});
  final LandingPageSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(homeReviewsProvider);
    return CustomerReviewsSection(asyncReviews: reviews);
  }
}
