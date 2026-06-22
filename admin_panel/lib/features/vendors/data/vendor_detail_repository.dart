import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/vendor.dart';
import '../domain/models/vendor_detail.dart';

class VendorDetailRepository {
  const VendorDetailRepository(this._supabase);
  final SupabaseClient _supabase;

  Future<Vendor> fetchVendorById(String vendorId) async {
    final data = await _supabase
        .from('vendors')
        .select()
        .eq('id', vendorId)
        .single();
    return Vendor.fromMap(data);
  }

  Future<List<VendorDocument>> fetchDocuments(String vendorId) async {
    final rows = await _supabase
        .from('vendor_documents')
        .select()
        .eq('vendor_id', vendorId)
        .order('created_at', ascending: false);
    return (rows as List<dynamic>)
        .map((r) => VendorDocument.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateDocumentStatus(
      String documentId, String status) async {
    await _supabase
        .from('vendor_documents')
        .update({'verification_status': status}).eq('id', documentId);
  }

  Future<List<VendorServiceArea>> fetchServiceAreas(
      String vendorId) async {
    try {
      final rows = await _supabase
          .from('vendor_service_areas')
          .select()
          .eq('vendor_id', vendorId)
          .order('city');
      return (rows as List<dynamic>)
          .map(
              (r) => VendorServiceArea.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetches all service areas across all vendors in a single query.
  /// Returns a map keyed by vendor_id for O(1) lookups during assignment.
  Future<Map<String, List<VendorServiceArea>>> fetchAllServiceAreas() async {
    try {
      final rows = await _supabase
          .from('vendor_service_areas')
          .select('id, vendor_id, city, area, pincode, radius_km');
      final result = <String, List<VendorServiceArea>>{};
      for (final r in rows as List<dynamic>) {
        final map = r as Map<String, dynamic>;
        final vendorId = map['vendor_id'] as String;
        result
            .putIfAbsent(vendorId, () => [])
            .add(VendorServiceArea.fromMap(map));
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<VendorBookingStats> fetchBookingStats(String vendorId) async {
    final rows = await _supabase
        .from('bookings')
        .select('status, total_amount')
        .eq('vendor_id', vendorId);

    final list = rows as List<dynamic>;
    if (list.isEmpty) return VendorBookingStats.empty;

    int pending = 0,
        assigned = 0,
        inProgress = 0,
        completed = 0,
        rejected = 0,
        cancelled = 0;
    double earnings = 0;

    for (final r in list) {
      final m = r as Map<String, dynamic>;
      final status = m['status'] as String? ?? '';
      final amount = (m['total_amount'] as num?)?.toDouble() ?? 0.0;
      switch (status) {
        case 'pending':
          pending++;
        case 'assigned':
          assigned++;
        case 'in_progress':
          inProgress++;
        case 'completed':
          completed++;
          earnings += amount;
        case 'rejected':
          rejected++;
        case 'cancelled':
          cancelled++;
      }
    }

    return VendorBookingStats(
      total: list.length,
      pending: pending,
      assigned: assigned,
      inProgress: inProgress,
      completed: completed,
      rejected: rejected,
      cancelled: cancelled,
      totalEarnings: earnings,
    );
  }
}
