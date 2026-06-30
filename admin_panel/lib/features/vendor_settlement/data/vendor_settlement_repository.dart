import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/vendor_earnings_summary.dart';
import '../domain/models/vendor_settlement.dart';

class VendorSettlementRepository {
  final SupabaseClient _supabase;
  const VendorSettlementRepository(this._supabase);

  // ── Earnings summaries ─────────────────────────────────────────────────────

  Future<List<VendorEarningsSummary>> fetchEarningsSummaries() async {
    // Start all three queries in parallel, then await each.
    final vendorsFuture = _supabase
        .from('vendors')
        .select('id, business_name, owner_name, is_active')
        .order('business_name');
    final bookingsFuture = _supabase
        .from('bookings')
        .select('vendor_id, total_amount')
        .eq('status', 'completed')
        .not('vendor_id', 'is', null);
    final settlementsFuture = _supabase
        .from('vendor_settlements')
        .select('vendor_id, amount, settled_at');

    final vendors = await vendorsFuture;
    final bookings = await bookingsFuture;
    final settlements = await settlementsFuture;

    // Group bookings by vendor
    final bookingsByVendor = <String, List<Map<String, dynamic>>>{};
    for (final b in bookings) {
      final vid = b['vendor_id'] as String?;
      if (vid != null && vid.isNotEmpty) {
        bookingsByVendor.putIfAbsent(vid, () => []).add(b as Map<String, dynamic>);
      }
    }

    // Group settlements by vendor
    final settlementsByVendor = <String, List<Map<String, dynamic>>>{};
    for (final s in settlements) {
      final vid = s['vendor_id'] as String?;
      if (vid != null) {
        settlementsByVendor.putIfAbsent(vid, () => []).add(s as Map<String, dynamic>);
      }
    }

    return vendors.map((v) {
      final vendorId = v['id'] as String;
      final vb = bookingsByVendor[vendorId] ?? [];
      final vs = settlementsByVendor[vendorId] ?? [];

      final grossEarnings = vb.fold<double>(
        0.0, (sum, b) => sum + ((b['total_amount'] as num?)?.toDouble() ?? 0.0));
      final totalSettled = vs.fold<double>(
        0.0, (sum, s) => sum + ((s['amount'] as num?)?.toDouble() ?? 0.0));

      DateTime? lastSettlementAt;
      if (vs.isNotEmpty) {
        final dates = vs
            .map((s) => DateTime.tryParse(s['settled_at'] as String? ?? ''))
            .whereType<DateTime>()
            .toList();
        if (dates.isNotEmpty) {
          lastSettlementAt = dates.reduce((a, b) => a.isAfter(b) ? a : b);
        }
      }

      return VendorEarningsSummary(
        vendorId: vendorId,
        vendorName: v['business_name'] as String? ?? '',
        ownerName: v['owner_name'] as String?,
        isActive: v['is_active'] as bool? ?? false,
        completedJobs: vb.length,
        grossEarnings: grossEarnings,
        totalSettled: totalSettled,
        lastSettlementAt: lastSettlementAt,
      );
    }).toList();
  }

  Future<VendorEarningsSummary?> fetchEarningsSummaryForVendor(
      String vendorId) async {
    if (vendorId.isEmpty) return null;

    // .single() returns Future<Map<…>> while the others return Future<List<…>>,
    // so they cannot share a Future.wait list. Start all three in parallel,
    // then await each individually to preserve concurrency without type issues.
    final vendorFuture = _supabase
        .from('vendors')
        .select('business_name, owner_name, is_active')
        .eq('id', vendorId)
        .single();
    final bookingsFuture = _supabase
        .from('bookings')
        .select('total_amount')
        .eq('vendor_id', vendorId)
        .eq('status', 'completed');
    final settlementsFuture = _supabase
        .from('vendor_settlements')
        .select('amount, settled_at')
        .eq('vendor_id', vendorId)
        .order('settled_at', ascending: false);

    final vendorData = await vendorFuture;
    final bookingsData = await bookingsFuture;
    final settlementsData = await settlementsFuture;

    final grossEarnings = bookingsData.fold<double>(
      0.0, (sum, b) => sum + ((b['total_amount'] as num?)?.toDouble() ?? 0.0));
    final totalSettled = settlementsData.fold<double>(
      0.0, (sum, s) => sum + ((s['amount'] as num?)?.toDouble() ?? 0.0));

    DateTime? lastSettlementAt;
    if (settlementsData.isNotEmpty) {
      lastSettlementAt = DateTime.tryParse(
          settlementsData.first['settled_at'] as String? ?? '');
    }

    return VendorEarningsSummary(
      vendorId: vendorId,
      vendorName: vendorData['business_name'] as String? ?? '',
      ownerName: vendorData['owner_name'] as String?,
      isActive: vendorData['is_active'] as bool? ?? false,
      completedJobs: bookingsData.length,
      grossEarnings: grossEarnings,
      totalSettled: totalSettled,
      lastSettlementAt: lastSettlementAt,
    );
  }

  // ── Settlement records ─────────────────────────────────────────────────────

  Future<List<VendorSettlement>> fetchSettlements({String? vendorId}) async {
    final hasVendor = vendorId != null && vendorId.isNotEmpty;
    final data = await (hasVendor
        ? _supabase
            .from('vendor_settlements')
            .select()
            .eq('vendor_id', vendorId!)
            .order('settled_at', ascending: false)
        : _supabase
            .from('vendor_settlements')
            .select()
            .order('settled_at', ascending: false));
    return (data as List<dynamic>)
        .map((r) => VendorSettlement.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<VendorSettlement> createSettlement({
    required String vendorId,
    required String vendorName,
    required double amount,
    required int completedJobsCount,
    required String settledBy,
    String? paymentMethod,
    String? referenceNumber,
    String? notes,
  }) async {
    final data = await _supabase
        .from('vendor_settlements')
        .insert({
          'vendor_id': vendorId,
          'vendor_name': vendorName,
          'amount': amount,
          'completed_jobs_count': completedJobsCount,
          'payment_method': paymentMethod,
          'reference_number':
              referenceNumber?.isNotEmpty == true ? referenceNumber : null,
          'notes': notes?.isNotEmpty == true ? notes : null,
          'settled_by': settledBy,
        })
        .select()
        .single();
    return VendorSettlement.fromMap(data);
  }

  // ── Monthly stats ──────────────────────────────────────────────────────────

  Future<(double amount, int count)> fetchThisMonthStats() async {
    final now = DateTime.now();
    final firstOfMonth = DateTime(now.year, now.month);
    final data = await _supabase
        .from('vendor_settlements')
        .select('amount')
        .gte('settled_at', firstOfMonth.toIso8601String());
    final list = data as List<dynamic>;
    final total = list.fold<double>(
      0.0, (sum, s) => sum + ((s['amount'] as num?)?.toDouble() ?? 0.0));
    return (total, list.length);
  }
}
