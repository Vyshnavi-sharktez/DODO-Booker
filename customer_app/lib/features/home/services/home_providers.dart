import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'home_service.dart';
import '../../../features/catalog/models/catalog_node_model.dart';
import '../../../models/banner_model.dart';

final homeServiceProvider = Provider<HomeService>((ref) => HomeService());

final homeBannersProvider = FutureProvider<List<BannerModel>>((ref) {
  return ref.read(homeServiceProvider).fetchBanners();
});

/// Root catalog nodes shown in the home categories carousel.
final featuredCatalogNodesProvider =
    FutureProvider<List<CatalogNodeModel>>((ref) {
  return ref.read(homeServiceProvider).fetchFeaturedCatalogNodes();
});

final featuredServicesProvider = FutureProvider<List<CatalogNodeModel>>((ref) {
  return ref.read(homeServiceProvider).fetchFeaturedServices();
});

final popularServicesProvider = FutureProvider<List<CatalogNodeModel>>((ref) {
  return ref.read(homeServiceProvider).fetchPopularServices();
});

final trendingServicesProvider = FutureProvider<List<CatalogNodeModel>>((ref) {
  return ref.read(homeServiceProvider).fetchTrendingServices();
});

final newServicesProvider = FutureProvider<List<CatalogNodeModel>>((ref) {
  return ref.read(homeServiceProvider).fetchNewServices();
});

final homeReviewsProvider = FutureProvider<List<PublicReview>>((ref) {
  return ref.read(homeServiceProvider).fetchPublicReviews();
});
