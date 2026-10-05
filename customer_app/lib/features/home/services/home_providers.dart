import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'home_service.dart';
import '../../../features/catalog/models/catalog_node_model.dart';
import '../../../models/banner_model.dart';

final homeServiceProvider = Provider<HomeService>((ref) => HomeService());

final homeBannersProvider = FutureProvider<List<BannerModel>>((ref) {
  return ref.read(homeServiceProvider).fetchBanners();
});

/// Root catalog nodes shown in the home categories carousel.
/// StreamProvider: updates in real time when catalog_nodes changes.
final featuredCatalogNodesProvider =
    StreamProvider.autoDispose<List<CatalogNodeModel>>((ref) {
  return ref.read(homeServiceProvider).watchFeaturedCatalogNodes();
});

/// StreamProvider: updates in real time when catalog_nodes changes.
final featuredServicesProvider = StreamProvider<List<CatalogNodeModel>>((ref) {
  return ref.read(homeServiceProvider).watchFeaturedServices();
});

final popularServicesProvider = FutureProvider<List<CatalogNodeModel>>((ref) {
  return ref.read(homeServiceProvider).fetchPopularServices();
});

final trendingServicesProvider = FutureProvider<List<CatalogNodeModel>>((ref) {
  return ref.read(homeServiceProvider).fetchTrendingServices();
});

/// StreamProvider: updates in real time when catalog_nodes changes.
final newServicesProvider = StreamProvider<List<CatalogNodeModel>>((ref) {
  return ref.read(homeServiceProvider).watchNewServices();
});

final homeReviewsProvider = FutureProvider<List<PublicReview>>((ref) {
  return ref.read(homeServiceProvider).fetchPublicReviews();
});

/// Set to true once the user completes the mobile location flow and taps
/// "Continue to Home". Gates whether the service content is visible.
final mobileServicesUnlockedProvider = StateProvider<bool>((ref) => false);
