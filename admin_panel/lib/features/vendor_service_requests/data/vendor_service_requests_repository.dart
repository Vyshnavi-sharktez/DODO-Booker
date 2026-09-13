import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/vendor_service_request.dart';

class VendorServiceRequestsRepository {
  const VendorServiceRequestsRepository(this._supabase);
  final SupabaseClient _supabase;

  static const _columns =
      'id, vendor_id, service_name, description, price, active_price, new_price, '
      'image_url, status, rejection_reason, request_type, parent_request_id, '
      'is_active, warranty_enabled, warranty_days, warranty_covers, warranty_exclusions, '
      'included_items, excluded_items, before_after_pairs, '
      'created_at, updated_at, vendors(id, business_name, vendor_tiers(id, name))';

  Future<List<VendorServiceRequest>> fetchAll() async {
    final data = await _supabase
        .from('vendor_service_requests')
        .select(_columns)
        .order('created_at', ascending: false);
    return (data as List)
        .map((r) => VendorServiceRequest.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<VendorServiceRequest?> fetchById(String id) async {
    final data = await _supabase
        .from('vendor_service_requests')
        .select(_columns)
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;
    return VendorServiceRequest.fromMap(data);
  }

  Future<List<VendorServiceRequest>> fetchByVendor(String vendorId) async {
    final data = await _supabase
        .from('vendor_service_requests')
        .select(_columns)
        .eq('vendor_id', vendorId)
        .order('created_at', ascending: false);
    return (data as List)
        .map((r) => VendorServiceRequest.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> accept(String id) async {
    await _supabase.rpc('admin_accept_service_request', params: {
      'p_request_id': id,
    });
  }

  Future<void> complete(String id) async {
    await _supabase
        .from('vendor_service_requests')
        .update({'status': 'completed'}).eq('id', id);
  }

  Future<void> reject(String id, {required String reason}) async {
    await _supabase.rpc('admin_reject_service_request', params: {
      'p_request_id': id,
      'p_reason': reason.trim(),
    });
  }

  Future<void> updateCustomService(
    String id, {
    required String serviceName,
    String? description,
    required double activePrice,
    String? imageUrl,
  }) async {
    await _supabase.from('vendor_service_requests').update({
      'service_name': serviceName,
      'description': description,
      'active_price': activePrice,
      'image_url': imageUrl,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> toggleActive(String id, {required bool isActive}) async {
    await _supabase.rpc('toggle_custom_service_active', params: {
      'p_request_id': id,
      'p_is_active': isActive,
    });
  }

  Future<List<Map<String, dynamic>>> fetchReviewsForCustomService(
      String customServiceId) async {
    // Step 1: find all booking IDs that include this custom service.
    final items = await _supabase
        .from('booking_items')
        .select('booking_id')
        .eq('custom_service_id', customServiceId);
    final bookingIds =
        (items as List).map((r) => r['booking_id'] as String).toList();
    if (bookingIds.isEmpty) return [];

    // Step 2: fetch reviews for those bookings, joining customer name.
    final reviews = await _supabase
        .from('customer_reviews')
        .select('id, rating, review_text, created_at, customer_id, booking_id, customers(full_name, phone)')
        .inFilter('booking_id', bookingIds)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(reviews as List);
  }
}
