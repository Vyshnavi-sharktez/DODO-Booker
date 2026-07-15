import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/vendor_booking_row.dart';
import '../domain/models/vendor_earnings_summary.dart';
import '../domain/models/vendor_settlement.dart';

class VendorSettlementRepository {
  final SupabaseClient _supabase;
  const VendorSettlementRepository(this._supabase);

  // ── Commission helpers ─────────────────────────────────────────────────────

  static double _applyRate(Map<String, dynamic> rule, double amount) {
    final type = rule['commission_type'] as String? ?? 'percentage';
    final value = (rule['commission_value'] as num?)?.toDouble() ?? 0.0;
    if (type == 'percentage') return amount * value / 100;
    return value;
  }

  static Map<String, dynamic>? _resolveRule(
    String vendorId,
    String? categoryId,
    Map<String, Map<String, dynamic>> vendorRules,
    Map<String, Map<String, dynamic>> categoryRules,
    Map<String, dynamic>? globalRule,
  ) {
    final vRule = vendorRules[vendorId];
    if (vRule != null) return vRule;
    if (categoryId != null) {
      final cRule = categoryRules[categoryId];
      if (cRule != null) return cRule;
    }
    return globalRule;
  }

  /// Per item: apply scoped config if found, otherwise accumulate into unscopedTotal.
  /// Fallback rule (from commission_rules) is applied once to the total unscoped amount.
  static double _computeVendorCommission({
    required List<Map<String, dynamic>> items,
    required Map<String, Map<String, dynamic>?> scopedConfigs,
    required Map<String, dynamic>? fallbackRule,
  }) {
    var scoped = 0.0;
    var unscopedTotal = 0.0;

    for (final item in items) {
      final serviceId = item['service_id'] as String? ?? '';
      final parentNodeId = item['catalog_parent_node_id'] as String?;
      final totalPrice = (item['total_price'] as num?)?.toDouble() ?? 0.0;
      final config = scopedConfigs['$serviceId:$parentNodeId'];

      if (config != null) {
        scoped += _applyRate(config, totalPrice);
      } else {
        unscopedTotal += totalPrice;
      }
    }

    var fallback = 0.0;
    if (unscopedTotal > 0 && fallbackRule != null) {
      fallback = _applyRate(fallbackRule, unscopedTotal);
    }

    return scoped + fallback;
  }

  // ── Scoped config resolution ───────────────────────────────────────────────

  Future<void> _batchResolveScopedCommission(
    Map<String, (String, String?)> pairs,
    Map<String, Map<String, dynamic>?> out,
  ) async {
    if (pairs.isEmpty) return;
    await Future.wait(pairs.entries.map((entry) async {
      final (serviceId, parentNodeId) = entry.value;
      try {
        final result = await _supabase.rpc(
          'resolve_catalog_module_config',
          params: {
            'p_module': 'commission',
            'p_service_id': serviceId,
            'p_parent_id': parentNodeId,
          },
        );
        out[entry.key] = result as Map<String, dynamic>?;
        debugPrint(
          '[DODO][Settlement] scoped commission: $serviceId:$parentNodeId → '
          '${result == null ? "null (fallback)" : result.toString()}',
        );
      } catch (e) {
        debugPrint('[DODO][Settlement] scoped commission RPC failed '
            'for $serviceId:$parentNodeId — $e');
        out[entry.key] = null;
      }
    }));
  }

  // ── Rule index helpers ─────────────────────────────────────────────────────

  static ({
    Map<String, Map<String, dynamic>> vendorRules,
    Map<String, Map<String, dynamic>> categoryRules,
    Map<String, dynamic>? globalRule,
  }) _indexRules(List<Map<String, dynamic>> rows) {
    final vendorRules = <String, Map<String, dynamic>>{};
    final categoryRules = <String, Map<String, dynamic>>{};
    Map<String, dynamic>? globalRule;
    for (final row in rows) {
      final type = row['rule_type'] as String? ?? '';
      final targetId = row['target_id'] as String?;
      if (type == 'vendor' && targetId != null) {
        vendorRules[targetId] = row;
      } else if (type == 'category' && targetId != null) {
        categoryRules[targetId] = row;
      } else if (type == 'global') {
        globalRule = row;
      }
    }
    return (
      vendorRules: vendorRules,
      categoryRules: categoryRules,
      globalRule: globalRule,
    );
  }

  // ── Per-vendor booking rows ────────────────────────────────────────────────

  /// Returns all completed bookings for [vendorId] with per-booking commission
  /// and settlement status.
  ///
  /// Paid bookings use immutable snapshots from vendor_settlement_bookings.
  /// Unpaid bookings use the current catalog commission config (re-resolved on
  /// each call so the admin always sees live rates before settling).
  Future<List<VendorBookingRow>> fetchBookingRows(String vendorId) async {
    final bookingsData = await _supabase
        .from('bookings')
        .select('id, total_amount, created_at')
        .eq('vendor_id', vendorId)
        .eq('status', 'completed')
        .order('created_at', ascending: false);

    if ((bookingsData as List).isEmpty) return [];

    final bookingIds = bookingsData.map((b) => b['id'] as String).toList();

    // Fetch items, settled rows, and commission_rules fallback in parallel.
    final itemsFuture = _supabase
        .from('booking_items')
        .select('booking_id, service_id, catalog_parent_node_id, total_price')
        .inFilter('booking_id', bookingIds);
    final settledFuture = _supabase
        .from('vendor_settlement_bookings')
        .select(
            'booking_id, settlement_id, booking_gross, commission_amount, net_vendor_amount')
        .inFilter('booking_id', bookingIds);
    final rulesFuture = _supabase
        .from('commission_rules')
        .select('rule_type, target_id, commission_type, commission_value')
        .eq('is_enabled', true);

    final itemsData = await itemsFuture;
    final settledData = await settledFuture;
    final allRulesRaw = await rulesFuture;

    // Fetch settlement details (settledAt, referenceNumber) for paid bookings.
    final settlementIds = (settledData as List)
        .map((s) => s['settlement_id'] as String)
        .toSet()
        .toList();
    final settlementsById = <String, Map<String, dynamic>>{};
    if (settlementIds.isNotEmpty) {
      final details = await _supabase
          .from('vendor_settlements')
          .select('id, settled_at, reference_number')
          .inFilter('id', settlementIds);
      for (final s in details as List) {
        settlementsById[s['id'] as String] = s as Map<String, dynamic>;
      }
    }

    // Build item lookup and unique pairs for commission resolution.
    final itemsByBooking = <String, List<Map<String, dynamic>>>{};
    final uniquePairs = <String, (String, String?)>{};
    for (final item in itemsData as List) {
      final bid = item['booking_id'] as String? ?? '';
      if (bid.isNotEmpty) {
        itemsByBooking.putIfAbsent(bid, () => []).add(item as Map<String, dynamic>);
      }
      final serviceId = item['service_id'] as String? ?? '';
      final parentNodeId = item['catalog_parent_node_id'] as String?;
      if (serviceId.isNotEmpty) {
        uniquePairs['$serviceId:$parentNodeId'] = (serviceId, parentNodeId);
      }
    }

    final rulesIndex = _indexRules(allRulesRaw.cast<Map<String, dynamic>>());
    final fallbackRule = _resolveRule(
      vendorId, null,
      rulesIndex.vendorRules, rulesIndex.categoryRules, rulesIndex.globalRule,
    );
    final scopedConfigs = <String, Map<String, dynamic>?>{};
    await _batchResolveScopedCommission(uniquePairs, scopedConfigs);

    // Build settled lookup by booking_id.
    final settledByBookingId = <String, Map<String, dynamic>>{};
    for (final s in settledData) {
      settledByBookingId[s['booking_id'] as String] = s;
    }

    return bookingsData.map<VendorBookingRow>((b) {
      final bookingId = b['id'] as String;
      final rawGross = (b['total_amount'] as num?)?.toDouble() ?? 0.0;
      final completedAt =
          DateTime.tryParse(b['created_at'] as String? ?? '') ?? DateTime.now();
      final items = itemsByBooking[bookingId] ?? [];
      final settledRow = settledByBookingId[bookingId];
      final isPaid = settledRow != null;

      final double bookingGross;
      final double commissionAmount;
      final double netVendorAmount;

      if (isPaid) {
        // Use immutable snapshots — commission config changes after settlement
        // must NOT affect these values.
        bookingGross =
            (settledRow['booking_gross'] as num?)?.toDouble() ?? rawGross;
        commissionAmount =
            (settledRow['commission_amount'] as num?)?.toDouble() ?? 0.0;
        netVendorAmount =
            (settledRow['net_vendor_amount'] as num?)?.toDouble() ?? 0.0;
      } else {
        // Compute from current config (live until the moment admin settles).
        commissionAmount = _computeVendorCommission(
          items: items,
          scopedConfigs: scopedConfigs,
          fallbackRule: fallbackRule,
        );
        netVendorAmount =
            (rawGross - commissionAmount).clamp(0.0, double.infinity);
        bookingGross = rawGross;
      }

      final effectivePct =
          bookingGross > 0 ? commissionAmount / bookingGross * 100 : 0.0;
      final commissionLabel = isPaid
          ? '${effectivePct.toStringAsFixed(1)}% (locked)'
          : '${effectivePct.toStringAsFixed(1)}%';

      String? settlementId;
      DateTime? settledAt;
      String? referenceNumber;
      if (isPaid) {
        settlementId = settledRow['settlement_id'] as String?;
        final detail = settlementsById[settlementId];
        settledAt =
            DateTime.tryParse(detail?['settled_at'] as String? ?? '');
        referenceNumber = detail?['reference_number'] as String?;
      }

      return VendorBookingRow(
        bookingId: bookingId,
        vendorId: vendorId,
        completedAt: completedAt,
        bookingGross: bookingGross,
        commissionAmount: commissionAmount,
        netVendorAmount: netVendorAmount,
        commissionLabel: commissionLabel,
        isPaid: isPaid,
        settlementId: settlementId,
        settledAt: settledAt,
        referenceNumber: referenceNumber,
      );
    }).toList();
  }

  // ── Earnings summaries ─────────────────────────────────────────────────────

  Future<List<VendorEarningsSummary>> fetchEarningsSummaries() async {
    // Phase 1: four independent queries in parallel.
    final vendorsFuture = _supabase
        .from('vendors')
        .select('id, business_name, owner_name, is_active')
        .order('business_name');
    final bookingsFuture = _supabase
        .from('bookings')
        .select('id, vendor_id, total_amount')
        .eq('status', 'completed')
        .not('vendor_id', 'is', null);
    final settlementsFuture = _supabase
        .from('vendor_settlements')
        .select('vendor_id, settled_at');
    final rulesFuture = _supabase
        .from('commission_rules')
        .select('rule_type, target_id, commission_type, commission_value')
        .eq('is_enabled', true);

    final vendors = await vendorsFuture;
    final bookings = await bookingsFuture;
    final settlements = await settlementsFuture;
    final allRulesRaw = await rulesFuture;

    final bookingIds =
        (bookings as List).map((b) => b['id'] as String).toList();

    List<Map<String, dynamic>> items = const [];
    // settledNet: booking_id → net_vendor_amount snapshot (from junction table)
    final settledNet = <String, double>{};

    if (bookingIds.isNotEmpty) {
      final itemsFuture2 = _supabase
          .from('booking_items')
          .select('booking_id, service_id, catalog_parent_node_id, total_price')
          .inFilter('booking_id', bookingIds);
      final settledFuture2 = _supabase
          .from('vendor_settlement_bookings')
          .select('booking_id, net_vendor_amount')
          .inFilter('booking_id', bookingIds);

      final itemsRaw = await itemsFuture2;
      final settledRaw = await settledFuture2;

      items = (itemsRaw as List).cast<Map<String, dynamic>>();
      for (final s in settledRaw as List) {
        settledNet[s['booking_id'] as String] =
            (s['net_vendor_amount'] as num?)?.toDouble() ?? 0.0;
      }
    }

    final rulesIndex = _indexRules(allRulesRaw.cast<Map<String, dynamic>>());

    final bookingsByVendor = <String, List<Map<String, dynamic>>>{};
    for (final b in bookings) {
      final vid = b['vendor_id'] as String? ?? '';
      if (vid.isNotEmpty) {
        bookingsByVendor.putIfAbsent(vid, () => []).add(b);
      }
    }

    final itemsByBooking = <String, List<Map<String, dynamic>>>{};
    final uniquePairs = <String, (String, String?)>{};
    for (final item in items) {
      final bid = item['booking_id'] as String? ?? '';
      if (bid.isNotEmpty) itemsByBooking.putIfAbsent(bid, () => []).add(item);
      final serviceId = item['service_id'] as String? ?? '';
      final parentNodeId = item['catalog_parent_node_id'] as String?;
      if (serviceId.isNotEmpty) {
        uniquePairs['$serviceId:$parentNodeId'] = (serviceId, parentNodeId);
      }
    }

    final settlementsByVendor = <String, List<Map<String, dynamic>>>{};
    for (final s in settlements as List) {
      final vid = s['vendor_id'] as String? ?? '';
      if (vid.isNotEmpty) {
        settlementsByVendor.putIfAbsent(vid, () => []).add(s as Map<String, dynamic>);
      }
    }

    final scopedConfigs = <String, Map<String, dynamic>?>{};
    await _batchResolveScopedCommission(uniquePairs, scopedConfigs);

    return (vendors as List).map<VendorEarningsSummary>((v) {
      final vendorId = v['id'] as String;
      final vb = bookingsByVendor[vendorId] ?? [];
      final vs = settlementsByVendor[vendorId] ?? [];

      final fallbackRule = _resolveRule(
        vendorId, null,
        rulesIndex.vendorRules, rulesIndex.categoryRules, rulesIndex.globalRule,
      );

      var pendingOrdersCount = 0;
      var paidOrdersCount = 0;
      var totalPending = 0.0;
      var totalPaid = 0.0;

      for (final b in vb) {
        final bookingId = b['id'] as String;
        final gross = (b['total_amount'] as num?)?.toDouble() ?? 0.0;
        final bookingItems = itemsByBooking[bookingId] ?? [];

        if (settledNet.containsKey(bookingId)) {
          // Use the stored snapshot — commission changes don't affect paid orders.
          paidOrdersCount++;
          totalPaid += settledNet[bookingId]!;
        } else {
          // Compute from current config for unpaid orders.
          final commission = _computeVendorCommission(
            items: bookingItems,
            scopedConfigs: scopedConfigs,
            fallbackRule: fallbackRule,
          );
          pendingOrdersCount++;
          totalPending += (gross - commission).clamp(0.0, double.infinity);
        }
      }

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
        pendingOrdersCount: pendingOrdersCount,
        paidOrdersCount: paidOrdersCount,
        totalPending: totalPending,
        totalPaid: totalPaid,
        lastSettlementAt: lastSettlementAt,
      );
    }).toList();
  }

  Future<VendorEarningsSummary?> fetchEarningsSummaryForVendor(
      String vendorId) async {
    if (vendorId.isEmpty) return null;

    final vendorFuture = _supabase
        .from('vendors')
        .select('business_name, owner_name, is_active')
        .eq('id', vendorId)
        .single();
    final bookingsFuture = _supabase
        .from('bookings')
        .select('id, total_amount')
        .eq('vendor_id', vendorId)
        .eq('status', 'completed');
    final settlementsFuture = _supabase
        .from('vendor_settlements')
        .select('settled_at')
        .eq('vendor_id', vendorId)
        .order('settled_at', ascending: false);
    final rulesFuture = _supabase
        .from('commission_rules')
        .select('rule_type, target_id, commission_type, commission_value')
        .eq('is_enabled', true);

    final vendorData = await vendorFuture;
    final bookingsData = await bookingsFuture;
    final settlementsData = await settlementsFuture;
    final allRulesRaw = await rulesFuture;

    final bookingIds =
        (bookingsData as List).map((b) => b['id'] as String).toList();

    List<Map<String, dynamic>> items = const [];
    final settledNet = <String, double>{};

    if (bookingIds.isNotEmpty) {
      final itemsFuture2 = _supabase
          .from('booking_items')
          .select('booking_id, service_id, catalog_parent_node_id, total_price')
          .inFilter('booking_id', bookingIds);
      final settledFuture2 = _supabase
          .from('vendor_settlement_bookings')
          .select('booking_id, net_vendor_amount')
          .inFilter('booking_id', bookingIds);

      items = ((await itemsFuture2) as List).cast<Map<String, dynamic>>();
      for (final s in (await settledFuture2) as List) {
        settledNet[s['booking_id'] as String] =
            (s['net_vendor_amount'] as num?)?.toDouble() ?? 0.0;
      }
    }

    final rulesIndex = _indexRules(allRulesRaw.cast<Map<String, dynamic>>());
    final fallbackRule = _resolveRule(
      vendorId, null,
      rulesIndex.vendorRules, rulesIndex.categoryRules, rulesIndex.globalRule,
    );

    final uniquePairs = <String, (String, String?)>{};
    final itemsByBooking = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      final bid = item['booking_id'] as String? ?? '';
      if (bid.isNotEmpty) itemsByBooking.putIfAbsent(bid, () => []).add(item);
      final serviceId = item['service_id'] as String? ?? '';
      final parentNodeId = item['catalog_parent_node_id'] as String?;
      if (serviceId.isNotEmpty) {
        uniquePairs['$serviceId:$parentNodeId'] = (serviceId, parentNodeId);
      }
    }

    final scopedConfigs = <String, Map<String, dynamic>?>{};
    await _batchResolveScopedCommission(uniquePairs, scopedConfigs);

    var pendingOrdersCount = 0;
    var paidOrdersCount = 0;
    var totalPending = 0.0;
    var totalPaid = 0.0;

    for (final b in bookingsData) {
      final bookingId = b['id'] as String;
      final gross = (b['total_amount'] as num?)?.toDouble() ?? 0.0;
      final bookingItems = itemsByBooking[bookingId] ?? [];

      if (settledNet.containsKey(bookingId)) {
        paidOrdersCount++;
        totalPaid += settledNet[bookingId]!;
      } else {
        final commission = _computeVendorCommission(
          items: bookingItems,
          scopedConfigs: scopedConfigs,
          fallbackRule: fallbackRule,
        );
        pendingOrdersCount++;
        totalPending += (gross - commission).clamp(0.0, double.infinity);
      }
    }

    DateTime? lastSettlementAt;
    if ((settlementsData as List).isNotEmpty) {
      lastSettlementAt = DateTime.tryParse(
          settlementsData.first['settled_at'] as String? ?? '');
    }

    return VendorEarningsSummary(
      vendorId: vendorId,
      vendorName: vendorData['business_name'] as String? ?? '',
      ownerName: vendorData['owner_name'] as String?,
      isActive: vendorData['is_active'] as bool? ?? false,
      pendingOrdersCount: pendingOrdersCount,
      paidOrdersCount: paidOrdersCount,
      totalPending: totalPending,
      totalPaid: totalPaid,
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
            .eq('vendor_id', vendorId)
            .order('settled_at', ascending: false)
        : _supabase
            .from('vendor_settlements')
            .select()
            .order('settled_at', ascending: false));
    return (data as List<dynamic>)
        .map((r) => VendorSettlement.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Atomically settles a batch of bookings via the DB function
  /// [create_vendor_settlement_batch].  All validations and inserts happen in a
  /// single DB transaction — if any booking is already settled or does not belong
  /// to the vendor, the entire call fails and no data is changed.
  Future<String> createSettlementBatch({
    required String vendorId,
    required String vendorName,
    required List<VendorBookingRow> bookings,
    required String settledBy,
    String? paymentMethod,
    String? referenceNumber,
    String? notes,
  }) async {
    final bookingsJson = bookings
        .map((b) => {
              'booking_id': b.bookingId,
              'booking_gross': b.bookingGross,
              'commission_amount': b.commissionAmount,
              'net_vendor_amount': b.netVendorAmount,
            })
        .toList();

    final result = await _supabase.rpc(
      'create_vendor_settlement_batch',
      params: {
        'p_vendor_id': vendorId,
        'p_vendor_name': vendorName,
        'p_settled_by': settledBy,
        'p_payment_method': paymentMethod ?? '',
        'p_reference_number': referenceNumber ?? '',
        'p_notes': notes ?? '',
        'p_bookings': bookingsJson,
      },
    );
    return result as String;
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
        0.0,
        (sum, s) =>
            sum + ((s['amount'] as num?)?.toDouble() ?? 0.0));
    return (total, list.length);
  }
}
