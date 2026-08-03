import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/amc_contract_model.dart';

/// Returns the ID of the active (status='pending') scheduling request for
/// [contractId], or null when none exists.  Exposed as a provider so it can
/// be invalidated by realtime events when the admin approves or rejects.
final pendingAmcRequestProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, contractId) async {
  final rows = await Supabase.instance.client
      .from('amc_scheduling_requests')
      .select('id')
      .eq('amc_contract_id', contractId)
      .eq('status', 'pending')
      .limit(1);
  final list = rows as List;
  if (list.isEmpty) return null;
  return list.first['id'] as String?;
});

/// Returns the ID of the pending pause request for [contractId], or null.
final pendingAmcPauseRequestProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, contractId) async {
  final rows = await Supabase.instance.client
      .from('amc_pause_requests')
      .select('id')
      .eq('amc_contract_id', contractId)
      .eq('status', 'pending')
      .limit(1);
  final list = rows as List;
  if (list.isEmpty) return null;
  return list.first['id'] as String?;
});

/// Returns the ID of the pending resume request for [contractId], or null.
final pendingAmcResumeRequestProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, contractId) async {
  final rows = await Supabase.instance.client
      .from('amc_resume_requests')
      .select('id')
      .eq('amc_contract_id', contractId)
      .eq('status', 'pending')
      .limit(1);
  final list = rows as List;
  if (list.isEmpty) return null;
  return list.first['id'] as String?;
});

final amcContractProvider = FutureProvider.autoDispose
    .family<AmcContractModel?, String>((ref, contractId) async {
  final client = Supabase.instance.client;

  final raw = await client
      .from('amc_contracts')
      .select(
        'id, customer_id, service_id, service_name, plan_name, recurrence_interval, '
        'price_per_visit, status, total_visits, created_at, '
        'amc_plan_id, package_duration, service_interval, num_visits, '
        'original_total, discount_type, discount_value, discount_amount, final_price, '
        'cancellation_reason, cancellation_remarks, cancellation_requested_at, '
        'quantity, previous_contract_id, is_renewal, '
        'pause_requested_at, pause_started_at, resumed_at',
      )
      .eq('id', contractId)
      .maybeSingle();

  if (raw == null) {
    debugPrint('[DODO][AMC] Contract not found: $contractId');
    return null;
  }

  final row = Map<String, dynamic>.from(raw);
  debugPrint('[AMC][Customer] Raw contract row: $row');

  final visitsRaw = await client
      .from('bookings')
      .select('id, amc_visit_number, status, service_date, planned_due_date, scheduled_time, total_amount, created_at, otp_verified_at, vendor_id')
      .eq('amc_contract_id', contractId)
      .order('amc_visit_number', ascending: true, nullsFirst: false)
      .order('created_at', ascending: true);

  final rawList = visitsRaw as List<dynamic>;

  // Resolve vendor names in one round-trip.
  final vendorIds = rawList
      .map((v) => (v as Map)['vendor_id'] as String?)
      .whereType<String>()
      .toSet()
      .toList();

  Map<String, String> vendorNames = {};
  if (vendorIds.isNotEmpty) {
    final vendorRows = await client
        .from('vendors')
        .select('id, business_name')
        .inFilter('id', vendorIds);
    for (final row in vendorRows as List) {
      final m = row as Map<String, dynamic>;
      final vid = m['id'] as String?;
      final name = m['business_name'] as String?;
      if (vid != null && name != null) vendorNames[vid] = name;
    }
  }

  final visits = rawList.map((v) {
    final m = Map<String, dynamic>.from(v as Map);
    final vid = m['vendor_id'] as String?;
    return AmcVisitModel.fromMap(m, vendorName: vid != null ? vendorNames[vid] : null);
  }).toList();

  debugPrint('[AMC][Customer] contractId=$contractId  DB returned ${visits.length} bookings:');
  for (final v in visits) {
    final shortId = v.id.length > 8 ? v.id.substring(0, 8) : v.id;
    debugPrint('[AMC][Customer]   id=$shortId  visitNumber=${v.visitNumber}  status=${v.status}  date=${v.serviceDate}');
  }

  final contract = AmcContractModel.fromMap(row, visits: visits);
  debugPrint('[AMC][Customer] Parsed → planName=${contract.planName}  status=${contract.status}');
  debugPrint('[AMC][Customer] Visits → totalVisits=${contract.totalVisits}  numVisits=${contract.numVisits}  effectiveTotalVisits=${contract.effectiveTotalVisits}');
  debugPrint('[AMC][Customer] Pricing → originalTotal=${contract.originalTotal}  discountType=${contract.discountType}  discountValue=${contract.discountValue}  discountAmount=${contract.discountAmount}  finalPrice=${contract.finalPrice}');
  debugPrint('[AMC][Customer] Visits list → count=${visits.length}  completed=${contract.completedVisits}');
  return contract;
});

// ── Pause / Resume request history items ─────────────────────────────────────

class AmcPauseRequestItem {
  final String id;
  final String status; // pending | approved | rejected | cancelled
  final String reason;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  const AmcPauseRequestItem({
    required this.id,
    required this.status,
    required this.reason,
    required this.createdAt,
    this.resolvedAt,
  });

  factory AmcPauseRequestItem.fromMap(Map<String, dynamic> m) =>
      AmcPauseRequestItem(
        id: m['id'] as String,
        status: m['status'] as String? ?? 'pending',
        reason: m['reason'] as String? ?? '',
        createdAt: DateTime.parse(m['created_at'] as String),
        resolvedAt: m['resolved_at'] != null
            ? DateTime.tryParse(m['resolved_at'] as String)
            : null,
      );
}

class AmcResumeRequestItem {
  final String id;
  final String status; // pending | approved | rejected | cancelled
  final String? reason;
  final int? pauseDurationDays;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  const AmcResumeRequestItem({
    required this.id,
    required this.status,
    this.reason,
    this.pauseDurationDays,
    required this.createdAt,
    this.resolvedAt,
  });

  factory AmcResumeRequestItem.fromMap(Map<String, dynamic> m) =>
      AmcResumeRequestItem(
        id: m['id'] as String,
        status: m['status'] as String? ?? 'pending',
        reason: m['reason'] as String?,
        pauseDurationDays: (m['pause_duration_days'] as num?)?.toInt(),
        createdAt: DateTime.parse(m['created_at'] as String),
        resolvedAt: m['resolved_at'] != null
            ? DateTime.tryParse(m['resolved_at'] as String)
            : null,
      );
}

/// All pause requests for a contract, newest first.
final amcPauseRequestsForContractProvider = FutureProvider.autoDispose
    .family<List<AmcPauseRequestItem>, String>((ref, contractId) async {
  final rows = await Supabase.instance.client
      .from('amc_pause_requests')
      .select('id, status, reason, created_at, resolved_at')
      .eq('amc_contract_id', contractId)
      .order('created_at', ascending: false);
  return (rows as List)
      .map((r) => AmcPauseRequestItem.fromMap(
            Map<String, dynamic>.from(r as Map),
          ))
      .toList();
});

/// All resume requests for a contract, newest first.
final amcResumeRequestsForContractProvider = FutureProvider.autoDispose
    .family<List<AmcResumeRequestItem>, String>((ref, contractId) async {
  final rows = await Supabase.instance.client
      .from('amc_resume_requests')
      .select('id, status, reason, pause_duration_days, created_at, resolved_at')
      .eq('amc_contract_id', contractId)
      .order('created_at', ascending: false);
  return (rows as List)
      .map((r) => AmcResumeRequestItem.fromMap(
            Map<String, dynamic>.from(r as Map),
          ))
      .toList();
});
