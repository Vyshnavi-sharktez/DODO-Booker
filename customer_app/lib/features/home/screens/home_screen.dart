import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../services/home_providers.dart';
import '../widgets/banner_carousel.dart';
import '../widgets/featured_categories_section.dart';
import '../widgets/featured_services_section.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _onRefresh(WidgetRef ref) async {
    ref.invalidate(homeBannersProvider);
    ref.invalidate(featuredCategoriesProvider);
    ref.invalidate(featuredServicesProvider);
    try {
      await Future.wait([
        ref.read(homeBannersProvider.future),
        ref.read(featuredCategoriesProvider.future),
        ref.read(featuredServicesProvider.future),
      ]);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banners = ref.watch(homeBannersProvider);
    final categories = ref.watch(featuredCategoriesProvider);
    final services = ref.watch(featuredServicesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => _onRefresh(ref),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Top spacing ────────────────────────────────────────────
              const SliverToBoxAdapter(child: SizedBox(height: 12)),

              // ── Banner carousel ────────────────────────────────────────
              SliverToBoxAdapter(
                child: BannerCarousel(asyncBanners: banners),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 28)),

              // ── Featured categories ────────────────────────────────────
              SliverToBoxAdapter(
                child: FeaturedCategoriesSection(asyncCategories: categories),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 28)),

              // ── Featured services ──────────────────────────────────────
              SliverToBoxAdapter(
                child: FeaturedServicesSection(asyncServices: services),
              ),

              // Bottom padding (accounts for nav bar)
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ),
      ),
    );
  }
}

