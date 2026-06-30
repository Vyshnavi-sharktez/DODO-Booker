import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'home_service.dart';
import '../../../models/banner_model.dart';
import '../../../models/category_model.dart';
import '../../../models/service_model.dart';

final homeServiceProvider = Provider<HomeService>((ref) => HomeService());

final homeBannersProvider = FutureProvider<List<BannerModel>>((ref) {
  return ref.read(homeServiceProvider).fetchBanners();
});

final featuredCategoriesProvider = FutureProvider<List<CategoryModel>>((ref) {
  return ref.read(homeServiceProvider).fetchFeaturedCategories();
});

final featuredServicesProvider = FutureProvider<List<ServiceModel>>((ref) {
  return ref.read(homeServiceProvider).fetchFeaturedServices();
});

final popularServicesProvider = FutureProvider<List<ServiceModel>>((ref) {
  return ref.read(homeServiceProvider).fetchPopularServices();
});

final trendingServicesProvider = FutureProvider<List<ServiceModel>>((ref) {
  return ref.read(homeServiceProvider).fetchTrendingServices();
});

final newServicesProvider = FutureProvider<List<ServiceModel>>((ref) {
  return ref.read(homeServiceProvider).fetchNewServices();
});

final homeReviewsProvider = FutureProvider<List<PublicReview>>((ref) {
  return ref.read(homeServiceProvider).fetchPublicReviews();
});
