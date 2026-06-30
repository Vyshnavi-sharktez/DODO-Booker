import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/banner_model.dart';
import '../../../models/category_model.dart';
import '../../../models/service_model.dart';
import '../../service/utils/service_detail_launcher.dart';
import '../services/home_providers.dart';
import '../widgets/customer_reviews_section.dart';
import '../widgets/hero_section.dart';
import '../widgets/home_categories_section.dart';
import '../widgets/home_header_section.dart';
import '../widgets/service_selection_modal.dart';
import '../widgets/special_offers_section.dart';
import '../widgets/trending_services_section.dart';
import '../widgets/why_dodo_section.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _onRefresh(WidgetRef ref) async {
    ref.invalidate(homeBannersProvider);
    ref.invalidate(featuredCategoriesProvider);
    ref.invalidate(featuredServicesProvider);
    ref.invalidate(popularServicesProvider);
    ref.invalidate(trendingServicesProvider);
    ref.invalidate(newServicesProvider);
    ref.invalidate(homeReviewsProvider);
    try {
      await Future.wait([
        ref.read(homeBannersProvider.future),
        ref.read(featuredCategoriesProvider.future),
        ref.read(featuredServicesProvider.future),
        ref.read(popularServicesProvider.future),
        ref.read(trendingServicesProvider.future),
        ref.read(newServicesProvider.future),
        ref.read(homeReviewsProvider.future),
      ]);
    } catch (_) {}
  }

  void _onServiceTap(BuildContext context, ServiceModel service) {
    openServiceDetail(context, service);
  }

  void _onCategoryTap(BuildContext context, CategoryModel category) {
    ServiceSelectionModal.show(context, category);
  }

  void _onBannerTap(BuildContext context, BannerModel banner) {
    final type = banner.redirectType;
    final id = banner.redirectId;
    if (type == 'service' && id != null && id.isNotEmpty) {
      context.push('/service-detail/$id');
    } else {
      context.push('/categories');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeBanners      = ref.watch(homeBannersProvider);
    final featuredCategories = ref.watch(featuredCategoriesProvider);
    final featuredServices = ref.watch(featuredServicesProvider);
    final popularServices  = ref.watch(popularServicesProvider);
    final trendingServices = ref.watch(trendingServicesProvider);
    final newServices      = ref.watch(newServicesProvider);
    final reviews          = ref.watch(homeReviewsProvider);

    // Only show banners section while loading or when there is real data.
    final showBanners = homeBanners.isLoading ||
        (homeBanners.asData?.value.isNotEmpty ?? false);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: RefreshIndicator(
              color: AppColors.gold,
              onRefresh: () => _onRefresh(ref),
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context)
                    .copyWith(scrollbars: false),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // ── Greeting row ───────────────────────────────────
                    const SliverToBoxAdapter(child: HomeHeaderSection()),

                    // ── Premium Hero Section ────────────────────────────
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                    SliverToBoxAdapter(
                      child: HeroSection(
                        onBookNow: () => context.push('/categories'),
                        onExplore: () => context.push('/categories'),
                      ),
                    ),

                    // ── Promotional banners (hidden when empty / error) ─
                    if (showBanners) ...[
                      const SliverToBoxAdapter(child: SizedBox(height: 28)),
                      SliverToBoxAdapter(
                        child: SpecialOffersSection(
                          asyncBanners: homeBanners,
                          onBannerTap: (b) => _onBannerTap(context, b),
                        ),
                      ),
                    ],

                    // ── Service categories (circular) ──────────────────
                    const SliverToBoxAdapter(child: SizedBox(height: 28)),
                    SliverToBoxAdapter(
                      child: HomeCategoriesSection(
                        asyncCategories: featuredCategories,
                        onCategorySelected: (c) =>
                            _onCategoryTap(context, c),
                        onSeeAll: () => context.push('/categories'),
                      ),
                    ),

                    // ── Featured services ──────────────────────────────
                    // const SliverToBoxAdapter(child: SizedBox(height: 32)),
                    // SliverToBoxAdapter(
                    //   child: TrendingServicesSection(
                    //     asyncServices: featuredServices,
                    //     onServiceTap: (s) => _onServiceTap(context, s),
                    //     onSeeAll: () => context.push('/categories'),
                    //     title: 'Featured Services',
                    //   ),
                    // ),

                    // ── Popular services ───────────────────────────────
                    // const SliverToBoxAdapter(child: SizedBox(height: 32)),
                    // SliverToBoxAdapter(
                    //   child: TrendingServicesSection(
                    //     asyncServices: popularServices,
                    //     onServiceTap: (s) => _onServiceTap(context, s),
                    //     onSeeAll: () => context.push('/categories'),
                    //     title: 'Popular Services',
                    //   ),
                    // ),

                    // ── Most booked services ───────────────────────────
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                    SliverToBoxAdapter(
                      child: TrendingServicesSection(
                        asyncServices: trendingServices,
                        onServiceTap: (s) => _onServiceTap(context, s),
                        onSeeAll: () => context.push('/categories'),
                        title: 'Most Booked Services',
                      ),
                    ),

                    // ── New services ───────────────────────────────────
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                    SliverToBoxAdapter(
                      child: TrendingServicesSection(
                        asyncServices: newServices,
                        onServiceTap: (s) => _onServiceTap(context, s),
                        onSeeAll: () => context.push('/categories'),
                        title: 'New Services',
                      ),
                    ),

                    // ── Customer reviews ───────────────────────────────
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                    SliverToBoxAdapter(
                      child: CustomerReviewsSection(asyncReviews: reviews),
                    ),

                    // ── Why choose DODO Booker ─────────────────────────
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                    const SliverToBoxAdapter(child: WhyDodoSection()),

                    const SliverToBoxAdapter(child: SizedBox(height: 64)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
