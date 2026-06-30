import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../models/banner_model.dart';
import '../../../models/category_model.dart';
import '../../../models/service_model.dart';

// ── Public review model for home page testimonials ────────────────────────────

class PublicReview {
  final String id;
  final String customerName;
  final String? customerAvatarUrl;
  final int rating;
  final String reviewText;
  final DateTime createdAt;

  const PublicReview({
    required this.id,
    required this.customerName,
    this.customerAvatarUrl,
    required this.rating,
    required this.reviewText,
    required this.createdAt,
  });

  String get initials {
    final parts = customerName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return customerName.isNotEmpty ? customerName[0].toUpperCase() : 'C';
  }

  factory PublicReview.fromJson(Map<String, dynamic> json) {
    final cust = json['customers'] as Map<String, dynamic>?;
    final rawName =
        cust?['full_name'] as String? ?? cust?['name'] as String? ?? 'Customer';
    final firstName = rawName.trim().split(' ').first;
    return PublicReview(
      id: json['id'] as String,
      customerName: firstName,
      customerAvatarUrl: cust?['profile_image_url'] as String?,
      rating: (json['rating'] as num).toInt(),
      reviewText: json['review_text'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class HomeService {
  static bool get _ready =>
      SupabaseConfig.supabaseUrl.isNotEmpty &&
      SupabaseConfig.supabaseAnonKey.isNotEmpty;

  static SupabaseClient get _db => Supabase.instance.client;

  // ── Banners ────────────────────────────────────────────────────────────────

  Future<List<BannerModel>> fetchBanners() async {
    if (!_ready) return _devBanners;

    try {
      final data = await _db
          .from('banners')
          .select()
          .eq('is_active', true)
          .order('display_order', ascending: true);

      final now = DateTime.now();
      return (data as List)
          .map((e) => BannerModel.fromJson(e as Map<String, dynamic>))
          .where((b) {
            if (b.startDate != null && b.startDate!.isAfter(now)) return false;
            if (b.endDate != null && b.endDate!.isBefore(now)) return false;
            return true;
          })
          .toList();
    } catch (_) {
      // Fallback if display_order column does not exist in the DB yet.
      final data = await _db
          .from('banners')
          .select()
          .eq('is_active', true)
          .order('created_at', ascending: true);

      return (data as List)
          .map((e) => BannerModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  // ── Featured categories ────────────────────────────────────────────────────

  Future<List<CategoryModel>> fetchFeaturedCategories() async {
    if (!_ready) return _devCategories;

    final data = await _db
        .from('categories')
        .select()
        .eq('is_active', true)
        .order('name', ascending: true);

    return (data as List)
        .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Featured services ──────────────────────────────────────────────────────

  Future<List<ServiceModel>> fetchFeaturedServices() async {
    if (!_ready) return _devServices;

    final data = await _db
        .from('services')
        .select('*, sub_categories(name, categories(name))')
        .eq('is_active', true)
        .eq('is_featured', true)
        .order('name', ascending: true)
        .limit(10);

    return (data as List)
        .map((e) => ServiceModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Popular services (by rating) ──────────────────────────────────────────

  Future<List<ServiceModel>> fetchPopularServices() async {
    if (!_ready) return _devServices;

    final data = await _db
        .from('services')
        .select('*, sub_categories(name, categories(name))')
        .eq('is_active', true)
        .order('rating', ascending: false)
        .limit(8);

    return (data as List)
        .map((e) => ServiceModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Most booked services (by actual booking count) ─────────────────────────
  //
  // Strategy:
  //   1. Aggregate booking_items.service_id in Dart (cap 500 rows for perf).
  //   2. Fetch full service details for the top-10 IDs via .inFilter().
  //   3. Re-sort the result to restore booking-count order.
  //   Fallback: active services ordered by rating descending.

  Future<List<ServiceModel>> fetchTrendingServices() async {
    if (!_ready) return _devServices.toList();

    try {
      // Step 1 – collect raw service_ids from booking_items
      final rawItems = await _db
          .from('booking_items')
          .select('service_id')
          .limit(500);

      final items = rawItems as List;

      // If the platform has no bookings yet, fall through to rating-sort
      if (items.isEmpty) {
        debugPrint('[DODO][HomeService] fetchTrendingServices: no booking_items — rating fallback');
        return _fetchByRating();
      }

      // Step 2 – aggregate count per service_id (client-side)
      final counts = <String, int>{};
      for (final row in items) {
        final id = row['service_id'] as String?;
        if (id != null && id.isNotEmpty) {
          counts[id] = (counts[id] ?? 0) + 1;
        }
      }

      if (counts.isEmpty) return _fetchByRating();

      // Sort descending by count; take top 10
      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topIds = sorted.take(10).map((e) => e.key).toList();

      // Step 3 – fetch full service rows for those IDs (flat join)
      final data = await _db
          .from('services')
          .select('*, sub_categories(id, name), categories(id, name)')
          .inFilter('id', topIds)
          .eq('is_active', true);

      final services = (data as List)
          .map((e) => ServiceModel.fromJson(e as Map<String, dynamic>))
          .toList();

      if (services.isEmpty) return _fetchByRating();

      // Restore booking-count order (.inFilter does not preserve list order)
      services.sort((a, b) {
        final ca = counts[a.id] ?? 0;
        final cb = counts[b.id] ?? 0;
        return cb.compareTo(ca);
      });

      debugPrint('[DODO][HomeService] fetchTrendingServices → ${services.length} services (booking-count order)');
      return services;
    } catch (e) {
      debugPrint('[DODO][HomeService] fetchTrendingServices error: $e — rating fallback');
      return _fetchByRating();
    }
  }

  // ── New services (recently added) ─────────────────────────────────────────

  Future<List<ServiceModel>> fetchNewServices() async {
    if (!_ready) return [];
    try {
      final data = await _db
          .from('services')
          .select('*, sub_categories(id, name), categories(id, name)')
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(8);
      return (data as List)
          .map((e) => ServiceModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[DODO][HomeService] fetchNewServices error: $e');
      return [];
    }
  }

  // ── Public reviews for home page ───────────────────────────────────────────

  Future<List<PublicReview>> fetchPublicReviews() async {
    if (!_ready) return [];
    try {
      final data = await _db
          .from('customer_reviews')
          .select('*, customers(full_name, profile_image_url)')
          .gte('rating', 4)
          .order('created_at', ascending: false)
          .limit(12);
      return (data as List)
          .map((e) => PublicReview.fromJson(e as Map<String, dynamic>))
          .where((r) => r.reviewText.trim().isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[DODO][HomeService] fetchPublicReviews error: $e');
      return [];
    }
  }

  // Private fallback: active services ordered by rating descending
  Future<List<ServiceModel>> _fetchByRating() async {
    try {
      final data = await _db
          .from('services')
          .select('*, sub_categories(id, name), categories(id, name)')
          .eq('is_active', true)
          .order('rating', ascending: false)
          .limit(10);

      final result = (data as List)
          .map((e) => ServiceModel.fromJson(e as Map<String, dynamic>))
          .toList();

      debugPrint('[DODO][HomeService] _fetchByRating → ${result.length} services');
      return result.isNotEmpty ? result : _devServices.toList();
    } catch (_) {
      return _devServices.toList();
    }
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

// IDs must match CategoryService._devSubcategories.categoryId values
final _devCategories = [
  const CategoryModel(id: '1', name: 'Cleaning', description: 'Home & deep cleaning'),
  const CategoryModel(id: '2', name: 'Plumbing', description: 'Repairs & installations'),
  const CategoryModel(id: '3', name: 'Electrical', description: 'Certified electricians'),
  const CategoryModel(id: '4', name: 'Painting', description: 'Interior & exterior'),
  const CategoryModel(id: '5', name: 'Carpentry', description: 'Furniture & woodwork'),
  const CategoryModel(id: '6', name: 'Pest Control', description: 'Safe extermination'),
  const CategoryModel(id: '7', name: 'Appliances', description: 'AC, washing machine, more'),
  const CategoryModel(id: '8', name: 'Shifting', description: 'Packing & moving'),
];

final _devServices = [
  const ServiceModel(id: 'dev-s1', name: 'Home Deep Clean', startingPrice: 999, categoryName: 'Cleaning'),
  const ServiceModel(id: 'dev-s2', name: 'AC Service', startingPrice: 499, categoryName: 'Appliances'),
  const ServiceModel(id: 'dev-s3', name: 'Plumber Visit', startingPrice: 299, categoryName: 'Plumbing'),
  const ServiceModel(id: 'dev-s4', name: 'Electrician', startingPrice: 349, categoryName: 'Electrical'),
  const ServiceModel(id: 'dev-s5', name: 'Wall Painting', startingPrice: 799, categoryName: 'Painting'),
  const ServiceModel(id: 'dev-s6', name: 'Carpenter', startingPrice: 449, categoryName: 'Carpentry'),
];
