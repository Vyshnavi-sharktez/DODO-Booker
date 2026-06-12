import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../models/banner_model.dart';
import '../../../models/category_model.dart';
import '../../../models/service_model.dart';

class HomeService {
  static bool get _ready =>
      SupabaseConfig.supabaseUrl.isNotEmpty &&
      SupabaseConfig.supabaseAnonKey.isNotEmpty;

  static SupabaseClient get _db => Supabase.instance.client;

  // ── Banners ────────────────────────────────────────────────────────────────

  Future<List<BannerModel>> fetchBanners() async {
    if (!_ready) return _devBanners;

    final data = await _db
        .from('banners')
        .select()
        .eq('is_active', true)
        .order('created_at', ascending: true);

    return (data as List)
        .map((e) => BannerModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Featured categories ────────────────────────────────────────────────────

  Future<List<CategoryModel>> fetchFeaturedCategories() async {
    if (!_ready) return _devCategories;

    final data = await _db
        .from('categories')
        .select()
        .eq('is_active', true)
        .order('name', ascending: true)
        .limit(8);

    return (data as List)
        .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Featured services ──────────────────────────────────────────────────────
  //
  // Joins subcategories and their parent categories so the model can populate
  // subcategoryName and categoryName without extra round-trips.

  Future<List<ServiceModel>> fetchFeaturedServices() async {
    if (!_ready) return _devServices;

    final data = await _db
        .from('services')
        .select('*, sub_categories(name, categories(name))')
        .eq('is_active', true)
        .order('name', ascending: true)
        .limit(10);

    return (data as List)
        .map((e) => ServiceModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

// ── Dev fallback dataset (shown only when Supabase is not configured) ─────────

final _devBanners = [
  const BannerModel(
    id: 'dev-b1',
    title: 'Professional Home Cleaning',
    subtitle: 'Certified pros, eco-friendly products',
    actionLabel: 'Book Now',
  ),
  const BannerModel(
    id: 'dev-b2',
    title: 'AC Service & Repair',
    subtitle: 'Expert technicians at your door',
    actionLabel: 'Book Now',
  ),
  const BannerModel(
    id: 'dev-b3',
    title: '24/7 Plumbing Solutions',
    subtitle: 'Emergency service available',
    actionLabel: 'Call Now',
  ),
];

final _devCategories = [
  const CategoryModel(id: 'dev-c1', name: 'Cleaning', description: 'Home & deep cleaning'),
  const CategoryModel(id: 'dev-c2', name: 'Plumbing', description: 'Repairs & installations'),
  const CategoryModel(id: 'dev-c3', name: 'Electrical', description: 'Certified electricians'),
  const CategoryModel(id: 'dev-c4', name: 'Painting', description: 'Interior & exterior'),
  const CategoryModel(id: 'dev-c5', name: 'Carpentry', description: 'Furniture & woodwork'),
  const CategoryModel(id: 'dev-c6', name: 'Pest Control', description: 'Safe extermination'),
  const CategoryModel(id: 'dev-c7', name: 'Appliances', description: 'AC, washing machine, more'),
  const CategoryModel(id: 'dev-c8', name: 'Shifting', description: 'Packing & moving'),
];

final _devServices = [
  const ServiceModel(id: 'dev-s1', name: 'Home Deep Clean', startingPrice: 999, categoryName: 'Cleaning'),
  const ServiceModel(id: 'dev-s2', name: 'AC Service', startingPrice: 499, categoryName: 'Appliances'),
  const ServiceModel(id: 'dev-s3', name: 'Plumber Visit', startingPrice: 299, categoryName: 'Plumbing'),
  const ServiceModel(id: 'dev-s4', name: 'Electrician', startingPrice: 349, categoryName: 'Electrical'),
  const ServiceModel(id: 'dev-s5', name: 'Wall Painting', startingPrice: 799, categoryName: 'Painting'),
  const ServiceModel(id: 'dev-s6', name: 'Carpenter', startingPrice: 449, categoryName: 'Carpentry'),
];
