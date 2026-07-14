import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../features/catalog/models/catalog_node_model.dart';
import '../../../models/banner_model.dart';

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

  // ── Featured catalog nodes (home carousel) ────────────────────────────────

  Future<List<CatalogNodeModel>> fetchFeaturedCatalogNodes() async {
    if (!_ready) return [];
    try {
      final data = await _db
          .from('catalog_nodes_view')
          .select()
          .eq('is_root_node', true)
          .eq('is_active', true)
          .order('sort_order', ascending: true)
          .order('name', ascending: true);
      return (data as List)
          .map((e) => CatalogNodeModel.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[HomeService] fetchFeaturedCatalogNodes error: $e');
      return [];
    }
  }

  // ── Featured services (active bookable nodes in display order) ───────────

  Future<List<CatalogNodeModel>> fetchFeaturedServices() async {
    if (!_ready) return [];
    try {
      final data = await _db
          .from('catalog_nodes_view')
          .select()
          .eq('is_active', true)
          .eq('is_bookable', true)
          .order('sort_order', ascending: true)
          .limit(10);
      return (data as List)
          .map((e) => CatalogNodeModel.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[HomeService] fetchFeaturedServices error: $e');
      return [];
    }
  }

  // ── Popular services (top 8 by booking count, last 90 days) ─────────────
  //
  // Distinction from Most Booked (all-time top 10):
  //   Popular = recency-windowed — "what's hot right now."
  //   Most Booked = all-time volume — "what people always choose."
  //
  // Strategy mirrors fetchTrendingServices but caps to the last 90 days
  // so newer services that are gaining momentum surface here first.
  // Falls back to display-order if booking_items has no created_at or
  // no recent bookings exist yet.

  Future<List<CatalogNodeModel>> fetchPopularServices() async {
    if (!_ready) return [];
    try {
      final cutoff = DateTime.now()
          .subtract(const Duration(days: 90))
          .toUtc()
          .toIso8601String();

      final rawItems = await _db
          .from('booking_items')
          .select('service_id')
          .gte('created_at', cutoff)
          .limit(500);

      final items = rawItems as List;

      if (items.isEmpty) {
        debugPrint('[HomeService] fetchPopularServices: no recent bookings — default fallback');
        return _fetchByDefault();
      }

      final counts = <String, int>{};
      for (final row in items) {
        final id = row['service_id'] as String?;
        if (id != null && id.isNotEmpty) {
          counts[id] = (counts[id] ?? 0) + 1;
        }
      }

      if (counts.isEmpty) return _fetchByDefault();

      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topIds = sorted.take(8).map((e) => e.key).toList();

      final data = await _db
          .from('catalog_nodes_view')
          .select()
          .inFilter('id', topIds)
          .eq('is_active', true)
          .eq('is_bookable', true);

      final nodes = (data as List)
          .map((e) => CatalogNodeModel.fromMap(e as Map<String, dynamic>))
          .toList();

      if (nodes.isEmpty) return _fetchByDefault();

      nodes.sort((a, b) {
        final ca = counts[a.id] ?? 0;
        final cb = counts[b.id] ?? 0;
        return cb.compareTo(ca);
      });

      debugPrint('[HomeService] fetchPopularServices → ${nodes.length} nodes (90-day booking count)');
      return nodes;
    } catch (e) {
      debugPrint('[HomeService] fetchPopularServices error: $e — default fallback');
      return _fetchByDefault();
    }
  }

  // ── Most booked services (all-time booking count via server-side RPC) ───────
  //
  // Strategy:
  //   1. Call get_most_booked_service_ids RPC — GROUP BY runs in the DB
  //      over every booking_items row, no row-count cap.
  //   2. Fetch catalog_nodes_view rows for the returned IDs.
  //   3. Re-sort to restore RPC order (.inFilter does not preserve it).
  //   Fallback: active bookable nodes in display order.

  Future<List<CatalogNodeModel>> fetchTrendingServices() async {
    if (!_ready) return [];

    try {
      // Step 1 – server-side GROUP BY aggregation (all rows, no limit)
      final rpcRows = await _db.rpc(
        'get_most_booked_service_ids',
        params: {'p_limit': 10},
      ) as List;

      if (rpcRows.isEmpty) {
        debugPrint('[DODO][HomeService] fetchTrendingServices: no bookings — default fallback');
        return _fetchByDefault();
      }

      // Step 2 – collect ordered IDs and counts returned by the RPC
      final counts = <String, int>{};
      final topIds = <String>[];
      for (final row in rpcRows) {
        final id = row['service_id'] as String?;
        final count = (row['booking_count'] as num?)?.toInt() ?? 0;
        if (id != null && id.isNotEmpty) {
          counts[id] = count;
          topIds.add(id);
        }
      }

      if (topIds.isEmpty) return _fetchByDefault();

      // Step 3 – fetch catalog nodes for those IDs
      final data = await _db
          .from('catalog_nodes_view')
          .select()
          .inFilter('id', topIds)
          .eq('is_active', true)
          .eq('is_bookable', true);

      final nodes = (data as List)
          .map((e) => CatalogNodeModel.fromMap(e as Map<String, dynamic>))
          .toList();

      if (nodes.isEmpty) return _fetchByDefault();

      // Restore booking-count order (.inFilter does not preserve list order)
      nodes.sort((a, b) {
        final ca = counts[a.id] ?? 0;
        final cb = counts[b.id] ?? 0;
        return cb.compareTo(ca);
      });

      debugPrint('[DODO][HomeService] fetchTrendingServices → ${nodes.length} nodes (all-time booking count)');
      return nodes;
    } catch (e) {
      debugPrint('[DODO][HomeService] fetchTrendingServices error: $e — default fallback');
      return _fetchByDefault();
    }
  }

  // ── New services (recently added catalog nodes) ────────────────────────────

  Future<List<CatalogNodeModel>> fetchNewServices() async {
    if (!_ready) return [];
    try {
      final data = await _db
          .from('catalog_nodes_view')
          .select()
          .eq('is_active', true)
          .eq('is_bookable', true)
          .order('created_at', ascending: false)
          .limit(8);
      return (data as List)
          .map((e) => CatalogNodeModel.fromMap(e as Map<String, dynamic>))
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

  // Private fallback: active bookable nodes in display order
  Future<List<CatalogNodeModel>> _fetchByDefault() async {
    try {
      final data = await _db
          .from('catalog_nodes_view')
          .select()
          .eq('is_active', true)
          .eq('is_bookable', true)
          .order('sort_order', ascending: true)
          .order('name', ascending: true)
          .limit(10);

      final result = (data as List)
          .map((e) => CatalogNodeModel.fromMap(e as Map<String, dynamic>))
          .toList();

      debugPrint('[DODO][HomeService] _fetchByDefault → ${result.length} nodes');
      return result;
    } catch (_) {
      return [];
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
