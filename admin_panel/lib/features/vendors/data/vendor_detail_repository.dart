import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/vendor.dart';
import '../domain/models/vendor_detail.dart';
import '../domain/models/vendor_penalty_record.dart';
import '../domain/models/vendor_wallet_info.dart';

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

  Future<List<VendorPenaltyRecord>> fetchPenaltyHistory(String vendorId) async {
    try {
      final rows = await _supabase
          .from('wallet_transactions')
          .select('''
            id, vendor_id, type, amount, balance_after, reference_id, reference_type, description, created_by, created_at,
            bookings:reference_id (
              booking_number,
              booking_items (
                catalog_nodes:service_id (name)
              )
            )
          ''')
          .eq('vendor_id', vendorId)
          .eq('type', 'penalty')
          .order('created_at', ascending: false);

      return (rows as List<dynamic>)
          .map((r) => VendorPenaltyRecord.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      final rows = await _supabase
          .from('wallet_transactions')
          .select()
          .eq('vendor_id', vendorId)
          .eq('type', 'penalty')
          .order('created_at', ascending: false);

      return (rows as List<dynamic>)
          .map((r) => VendorPenaltyRecord.fromMap(r as Map<String, dynamic>))
          .toList();
    }
  }

  Future<VendorWalletInfo> fetchVendorWalletInfo(String vendorId) async {
    final walletRes = await _supabase
        .from('vendor_wallets')
        .select('available_balance, pending_balance')
        .eq('vendor_id', vendorId)
        .maybeSingle();

    final avail = (walletRes?['available_balance'] as num?)?.toDouble() ?? 0.0;
    final pend = (walletRes?['pending_balance'] as num?)?.toDouble() ?? 0.0;

    final settingRes = await _supabase
        .from('settings')
        .select('setting_value')
        .eq('setting_key', 'wallet_minimum_balance')
        .maybeSingle();

    final minBal =
        double.tryParse(settingRes?['setting_value'] as String? ?? '0') ?? 0.0;

    final topUpRes = await _supabase
        .from('wallet_transactions')
        .select('amount, created_at')
        .eq('vendor_id', vendorId)
        .eq('type', 'top_up')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    final lastAmount = (topUpRes?['amount'] as num?)?.toDouble();
    final lastDate = topUpRes?['created_at'] != null
        ? DateTime.tryParse(topUpRes!['created_at'] as String)
        : null;

    return VendorWalletInfo(
      vendorId: vendorId,
      availableBalance: avail,
      pendingBalance: pend,
      minimumRequiredBalance: minBal,
      lastTopUpAmount: lastAmount,
      lastTopUpDate: lastDate,
    );
  }

  Future<List<VendorWalletTransaction>> fetchWalletTransactions(
      String vendorId) async {
    final rows = await _supabase
        .from('wallet_transactions')
        .select()
        .eq('vendor_id', vendorId)
        .order('created_at', ascending: false);

    return (rows as List<dynamic>)
        .map((r) => VendorWalletTransaction.fromMap(r as Map<String, dynamic>))
        .toList();
  }
}
