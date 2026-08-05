import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/vendor.dart';

class VendorPerformanceMetrics {
  final int completedBookings;
  final int cancelledBookings;
  final int totalBookings;
  final double avgRating;
  final double cancellationRate;
  final double completionRate;

  const VendorPerformanceMetrics({
    required this.completedBookings,
    required this.cancelledBookings,
    required this.totalBookings,
    required this.avgRating,
    required this.cancellationRate,
    required this.completionRate,
  });
}

class VendorsRepository {
  final SupabaseClient _supabase;

  const VendorsRepository(this._supabase);

  Future<List<Vendor>> fetchVendors() async {
    final data = await _supabase
        .from('vendors')
        .select('*, vendor_tiers(*)')
        .order('created_at', ascending: false);
    return (data as List<dynamic>)
        .map((r) => Vendor.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Call database RPC to evaluate and update a vendor's tier
  Future<void> evaluateVendorPerformance(String vendorId) async {
    await _supabase.rpc('evaluate_vendor_performance', params: {
      'p_vendor_id': vendorId,
    });
  }

  /// Fetch live calculated performance metrics for a specific vendor
  Future<VendorPerformanceMetrics> getVendorPerformanceMetrics(String vendorId) async {
    final bookingsResponse = await _supabase
        .from('bookings')
        .select('status')
        .eq('vendor_id', vendorId);

    final bookings = (bookingsResponse as List).cast<Map<String, dynamic>>();
    final completedCount = bookings.where((b) => b['status'] == 'completed').length;
    final cancelledCount = bookings.where((b) => b['status'] == 'cancelled').length;
    final totalAssigned = bookings.where((b) => [
          'completed',
          'cancelled',
          'assigned',
          'in_progress',
          'accepted'
        ].contains(b['status'])).length;

    double cancellationRate = 0.0;
    double completionRate = 0.0;
    if (totalAssigned > 0) {
      cancellationRate = ((cancelledCount / totalAssigned) * 10000).round() / 100.0;
      completionRate = ((completedCount / totalAssigned) * 10000).round() / 100.0;
    }

    final reviewsResponse = await _supabase
        .from('customer_reviews')
        .select('rating, bookings!inner(vendor_id)')
        .eq('bookings.vendor_id', vendorId);

    final reviews = (reviewsResponse as List).cast<Map<String, dynamic>>();
    double avgRating = 0.0;
    if (reviews.isNotEmpty) {
      final totalRating = reviews.fold<double>(
        0.0,
        (sum, r) => sum + ((r['rating'] as num?)?.toDouble() ?? 0.0),
      );
      avgRating = ((totalRating / reviews.length) * 100).round() / 100.0;
    } else {
      final vendorRow = await _supabase
          .from('vendors')
          .select('rating')
          .eq('id', vendorId)
          .maybeSingle();
      avgRating = (vendorRow?['rating'] as num?)?.toDouble() ?? 0.0;
    }

    return VendorPerformanceMetrics(
      completedBookings: completedCount,
      cancelledBookings: cancelledCount,
      totalBookings: totalAssigned,
      avgRating: avgRating,
      cancellationRate: cancellationRate,
      completionRate: completionRate,
    );
  }

  Future<Vendor> createVendor({
    required String businessName,
    String? ownerName,
    required String phone,
    required String email,
    required String city,
    String? address,
    required String status,
    required bool isActive,
    double? rating,
    double? latitude,
    double? longitude,
    double commissionRate = 0.0,
    bool isPreferredVendor = false,
    double preferredVendorFee = 0.0,
  }) async {
    final data = await _supabase
        .from('vendors')
        .insert({
          'business_name': businessName,
          if (ownerName?.isNotEmpty == true) 'owner_name': ownerName,
          'phone': phone,
          'email': email,
          'city': city,
          if (address?.isNotEmpty == true) 'address': address,
          'status': status,
          'is_active': isActive,
          'rating': rating,
          'latitude': latitude,
          'longitude': longitude,
          'commission_rate': commissionRate,
          'is_preferred_vendor': isPreferredVendor,
          'preferred_vendor_fee': preferredVendorFee,
        })
        .select('*, vendor_tiers(*)')
        .single();
    return Vendor.fromMap(data);
  }

  Future<Vendor> updateVendor(
    String id, {
    required String businessName,
    String? ownerName,
    required String phone,
    required String email,
    required String city,
    String? address,
    required String status,
    required bool isActive,
    double? rating,
    double? latitude,
    double? longitude,
    double? commissionRate,
    bool isPreferredVendor = false,
    double preferredVendorFee = 0.0,
  }) async {
    final data = await _supabase
        .from('vendors')
        .update({
          'business_name': businessName,
          'owner_name': ownerName?.isNotEmpty == true ? ownerName : null,
          'phone': phone,
          'email': email,
          'city': city,
          'address': address?.isNotEmpty == true ? address : null,
          'status': status,
          'is_active': isActive,
          'rating': rating,
          'latitude': latitude,
          'longitude': longitude,
          'commission_rate': commissionRate ?? 0.0,
          'is_preferred_vendor': isPreferredVendor,
          'preferred_vendor_fee': preferredVendorFee,
        })
        .eq('id', id)
        .select('*, vendor_tiers(*)')
        .single();
    return Vendor.fromMap(data);
  }

  Future<void> deleteVendor(String id) async {
    await _supabase.from('vendors').delete().eq('id', id);
  }

  Future<void> updateActive(String id, {required bool isActive}) async {
    await _supabase
        .from('vendors')
        .update({
          'is_active': isActive,
          'status': isActive ? 'active' : 'inactive',
        })
        .eq('id', id);
  }
}
