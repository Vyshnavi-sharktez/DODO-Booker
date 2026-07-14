import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../features/catalog/models/catalog_node_model.dart';
import '../../../features/catalog/utils/catalog_launcher.dart';
import '../../booking/services/coupon_providers.dart';
import '../services/home_providers.dart';
import '../widgets/customer_reviews_section.dart';
import '../widgets/hero_section.dart';
import '../widgets/home_categories_section.dart';
import '../widgets/home_header_section.dart';
import '../widgets/special_offers_section.dart';
import '../widgets/trending_services_section.dart';
import '../widgets/footer_section.dart';
import '../widgets/why_dodo_section.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _onRefresh(WidgetRef ref) async {
    ref.invalidate(activeCouponsProvider);
    ref.invalidate(featuredCatalogNodesProvider);
    ref.invalidate(trendingServicesProvider);
    ref.invalidate(newServicesProvider);
    ref.invalidate(homeReviewsProvider);
    try {
      await Future.wait([
        ref.read(activeCouponsProvider.future),
        ref.read(featuredCatalogNodesProvider.future),
        ref.read(trendingServicesProvider.future),
        ref.read(newServicesProvider.future),
        ref.read(homeReviewsProvider.future),
      ]);
    } catch (_) {}
  }

  void _onCatalogNodeTap(BuildContext context, CatalogNodeModel node) {
    openCatalogNode(context, node);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeCoupons     = ref.watch(activeCouponsProvider);
    final featuredNodes     = ref.watch(featuredCatalogNodesProvider);
    final trendingServices  = ref.watch(trendingServicesProvider);
    final newServices       = ref.watch(newServicesProvider);
    final reviews           = ref.watch(homeReviewsProvider);

    // Only show offers section while loading or when there are active coupons.
    final showCoupons = activeCoupons.isLoading ||
        (activeCoupons.asData?.value.isNotEmpty ?? false);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.gold,
          onRefresh: () => _onRefresh(ref),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context)
                .copyWith(scrollbars: false),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // ── All constrained page sections (max-width 1280) ─────
                SliverToBoxAdapter(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1280),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── Greeting row ───────────────────────────
                          const HomeHeaderSection(),

                          // ── Premium Hero Section ───────────────────
                          const SizedBox(height: 16),
                          HeroSection(
                            onBookNow: () => context.push('/categories'),
                            onExplore: () => context.push('/categories'),
                          ),

                          // ── Special offers (active coupons) ───────────
                          if (showCoupons) ...[
                            const SizedBox(height: 28),
                            SpecialOffersSection(asyncCoupons: activeCoupons),
                          ],

                          // ── Service categories (circular) ──────────
                          const SizedBox(height: 28),
                          HomeCategoriesSection(
                            asyncCategories: featuredNodes,
                            onCategorySelected: (node) =>
                                _onCatalogNodeTap(context, node),
                            onSeeAll: () => context.push('/categories'),
                          ),

                          // ── Featured services ──────────────────────
                          // const SizedBox(height: 32),
                          // TrendingServicesSection(
                          //   asyncServices: featuredServices,
                          //   onServiceTap: (n) => _onCatalogNodeTap(context, n),
                          //   onSeeAll: () => context.push('/categories'),
                          //   title: 'Featured Services',
                          // ),

                          // ── Popular services ───────────────────────
                          // const SizedBox(height: 32),
                          // TrendingServicesSection(
                          //   asyncServices: popularServices,
                          //   onServiceTap: (n) => _onCatalogNodeTap(context, n),
                          //   onSeeAll: () => context.push('/categories'),
                          //   title: 'Popular Services',
                          // ),

                          // ── Most booked services ───────────────────
                          const SizedBox(height: 32),
                          TrendingServicesSection(
                            asyncServices: trendingServices,
                            onServiceTap: (n) => _onCatalogNodeTap(context, n),
                            onSeeAll: () => context.push('/categories'),
                            title: 'Most Booked Services',
                          ),

                          // ── New services ───────────────────────────
                          const SizedBox(height: 32),
                          TrendingServicesSection(
                            asyncServices: newServices,
                            onServiceTap: (n) => _onCatalogNodeTap(context, n),
                            onSeeAll: () => context.push('/categories'),
                            title: 'New Services',
                          ),

                          // ── Customer reviews ───────────────────────
                          const SizedBox(height: 32),
                          CustomerReviewsSection(asyncReviews: reviews),

                          // ── Why choose DODO Booker ─────────────────
                          const SizedBox(height: 32),
                          const WhyDodoSection(),

                          const SizedBox(height: 48),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Site footer – full browser width ───────────────────
                const SliverToBoxAdapter(child: FooterSection()),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
