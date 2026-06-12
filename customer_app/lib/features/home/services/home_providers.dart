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
