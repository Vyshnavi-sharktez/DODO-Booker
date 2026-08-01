import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AmcPlanRecord {
  final String contractId;
  final String serviceId;
  final String serviceName;
  final String planName;
  final String status;
  final DateTime createdAt;
  final DateTime? expiryDate;
  final int totalVisits;
  final int visitsCompleted;
  // Next visit state
  final String? pendingVisitId;      // trigger-created, no date yet
  final DateTime? scheduledVisitDate; // admin has scheduled
  final String? scheduledVisitTime;
  // Scheduling request state
  final bool hasPendingRequest;
  final String? pendingRequestId;
  final int quantity;

  const AmcPlanRecord({
    required this.contractId,
    required this.serviceId,
    required this.serviceName,
    required this.planName,
    required this.status,
    required this.createdAt,
    this.expiryDate,
    required this.totalVisits,
    required this.visitsCompleted,
    this.pendingVisitId,
    this.scheduledVisitDate,
    this.scheduledVisitTime,
    this.hasPendingRequest = false,
    this.pendingRequestId,
    this.quantity = 1,
  });

  int get remainingVisits => (totalVisits - visitsCompleted).clamp(0, 9999);
  bool get isActive => status == 'active';
  bool get isScheduled => scheduledVisitDate != null;

  static DateTime? _computeExpiry(DateTime createdAt, String? packageDuration) {
    final days = switch (packageDuration) {
      'monthly'     => 30,
      'quarterly'   => 91,
      'half_yearly' => 182,
      'yearly'      => 365,
      _             => null,
    };
    return days != null ? createdAt.add(Duration(days: days)) : null;
  }

  factory AmcPlanRecord.fromRow(
    Map<String, dynamic> row, {
    Map<String, Map<String, dynamic>>? nextVisitByContract,
    Set<String>? contractsWithRequests,
    Map<String, String>? requestIdByContract,
  }) {
    final id = row['id'] as String;
    final createdAt = DateTime.parse(row['created_at'] as String);
    // Compute expiry from local midnight so the resulting date matches the
    // calendar day the customer purchased, regardless of UTC offset.
    final expiryDate =
        _computeExpiry(createdAt.toLocal(), row['package_duration'] as String?);

    final nextVisit = nextVisitByContract?[id];
    final serviceDate = nextVisit?['service_date'] != null
        ? DateTime.tryParse(nextVisit!['service_date'] as String)
        : null;
    final pendingId = (nextVisit != null && serviceDate == null)
        ? nextVisit['id'] as String?
        : null;

    return AmcPlanRecord(
      contractId: id,
      serviceId: row['service_id'] as String? ?? '',
      serviceName: row['service_name'] as String? ?? '',
      planName: row['plan_name'] as String? ?? '',
      status: row['status'] as String? ?? 'active',
      createdAt: createdAt,
      expiryDate: expiryDate,
      totalVisits: (row['num_visits'] as num?)?.toInt() ??
          (row['total_visits'] as num?)?.toInt() ?? 0,
      visitsCompleted: (row['visits_completed'] as num?)?.toInt() ?? 0,
      pendingVisitId: pendingId,
      scheduledVisitDate: serviceDate,
      scheduledVisitTime: nextVisit?['scheduled_time'] as String?,
      hasPendingRequest: contractsWithRequests?.contains(id) ?? false,
      pendingRequestId: requestIdByContract?[id],
      quantity: (row['quantity'] as num?)?.toInt() ?? 1,
    );
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final allAmcContractsProvider =
    FutureProvider.autoDispose<List<AmcPlanRecord>>((ref) async {
  try {
    debugPrint('[AMC][Plans] Step 1: reading phone from SharedPreferences');
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('dodo_auth_phone');
    debugPrint('[AMC][Plans] Step 1: phone=$phone');
    if (phone == null) return [];

    final client = Supabase.instance.client;

    debugPrint('[AMC][Plans] Step 2: looking up customer_id for phone=$phone');
    final custRows = await client
        .from('customers')
        .select('id')
        .eq('phone', phone)
        .limit(1);
    debugPrint('[AMC][Plans] Step 2: custRows=${(custRows as List).length} rows');
    if (custRows.isEmpty) return [];
    final customerId = custRows.first['id'] as String;
    debugPrint('[AMC][Plans] Step 2: customerId=$customerId');

    debugPrint('[AMC][Plans] Step 3: querying amc_contracts');
    final contracts = await client
        .from('amc_contracts')
        .select(
          'id, service_id, service_name, plan_name, status, '
          'visits_completed, num_visits, total_visits, created_at, '
          'package_duration, quantity',
        )
        .eq('customer_id', customerId)
        .order('created_at', ascending: false);
    debugPrint('[AMC][Plans] Step 3: contracts=${(contracts as List).length} rows');

    if (contracts.isEmpty) return [];
    final contractIds = contracts.map((c) => c['id'] as String).toList();

    debugPrint('[AMC][Plans] Step 4: querying bookings for contractIds=$contractIds');
    final pendingVisits = await client
        .from('bookings')
        .select('id, amc_contract_id, service_date, scheduled_time, status')
        .inFilter('amc_contract_id', contractIds)
        .inFilter('status', ['pending', 'assigned', 'accepted'])
        .order('service_date', ascending: true, nullsFirst: true);
    debugPrint('[AMC][Plans] Step 4: pendingVisits=${(pendingVisits as List).length} rows');

    final nextVisitByContract = <String, Map<String, dynamic>>{};
    for (final row in pendingVisits) {
      final cid = row['amc_contract_id'] as String;
      if (!nextVisitByContract.containsKey(cid)) {
        nextVisitByContract[cid] = Map<String, dynamic>.from(row as Map);
      }
    }

    debugPrint('[AMC][Plans] Step 5: querying amc_scheduling_requests');
    final requests = await client
        .from('amc_scheduling_requests')
        .select('id, amc_contract_id')
        .inFilter('amc_contract_id', contractIds)
        .eq('status', 'pending');
    debugPrint('[AMC][Plans] Step 5: requests=${(requests as List).length} rows');

    final contractsWithRequests = <String>{};
    final requestIdByContract = <String, String>{};
    for (final row in requests) {
      final cid = row['amc_contract_id'] as String;
      contractsWithRequests.add(cid);
      requestIdByContract[cid] = row['id'] as String;
    }

    debugPrint('[AMC][Plans] Step 6: building AmcPlanRecord list');
    final result = contracts
        .map((row) => AmcPlanRecord.fromRow(
              Map<String, dynamic>.from(row as Map),
              nextVisitByContract: nextVisitByContract,
              contractsWithRequests: contractsWithRequests,
              requestIdByContract: requestIdByContract,
            ))
        .toList();
    debugPrint('[AMC][Plans] Done: ${result.length} records');
    return result;
  } catch (e, st) {
    debugPrint('[AMC][Plans] ERROR: $e');
    debugPrint('[AMC][Plans] STACK: $st');
    rethrow;
  }
});
