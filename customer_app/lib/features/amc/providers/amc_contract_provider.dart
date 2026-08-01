import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/amc_contract_model.dart';

final amcContractProvider = FutureProvider.autoDispose
    .family<AmcContractModel?, String>((ref, contractId) async {
  final client = Supabase.instance.client;

  final raw = await client
      .from('amc_contracts')
      .select(
        'id, service_id, service_name, plan_name, recurrence_interval, '
        'price_per_visit, status, total_visits, created_at, '
        'amc_plan_id, package_duration, service_interval, num_visits, '
        'original_total, discount_type, discount_value, discount_amount, final_price, '
        'cancellation_reason, cancellation_remarks, cancellation_requested_at, '
        'quantity, previous_contract_id, is_renewal',
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
      .select('id, amc_visit_number, status, service_date, scheduled_time, total_amount, created_at, otp_verified_at, vendor_id')
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
