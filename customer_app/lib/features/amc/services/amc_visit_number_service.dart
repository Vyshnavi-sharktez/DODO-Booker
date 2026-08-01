import 'package:supabase_flutter/supabase_flutter.dart';

/// Returns the next [amc_visit_number] to assign when creating a new AMC
/// booking for [contractId].
///
/// Queries [max(amc_visit_number)] from the [bookings] table so the result
/// accounts for bookings already inserted by the DB trigger
/// [fn_amc_visit_completed], which auto-creates the next-visit row on each
/// completion. Using [visits_completed + 1] from [amc_contracts] collides
/// with that trigger-created row because the counter and the max visit number
/// are always equal after a completion — this function reads the actual max
/// and adds 1, guaranteeing no duplicate.
///
/// Returns 1 when no bookings exist yet for the contract (first visit).
Future<int> resolveNextAmcVisitNumber(
  SupabaseClient client,
  String contractId,
) async {
  final rows = await client
      .from('bookings')
      .select('amc_visit_number')
      .eq('amc_contract_id', contractId)
      .not('amc_visit_number', 'is', null)
      .order('amc_visit_number', ascending: false)
      .limit(1);
  final list = rows as List;
  if (list.isEmpty) return 1;
  return ((list.first['amc_visit_number'] as num?)?.toInt() ?? 0) + 1;
}

/// Returns the [id] of the unscheduled pending AMC visit for [contractId],
/// or null if none exists.
///
/// The DB trigger [fn_amc_visit_completed] auto-creates a next-visit
/// placeholder (status = 'pending', service_date = NULL) after each visit
/// is completed. The booking flow calls this before INSERTing to decide
/// whether to UPDATE the placeholder (Option B lifecycle) instead.
Future<String?> findUnscheduledAmcVisit(
  SupabaseClient client,
  String contractId,
) async {
  final rows = await client
      .from('bookings')
      .select('id')
      .eq('amc_contract_id', contractId)
      .eq('status', 'pending')
      .filter('service_date', 'is', null)
      .limit(1);
  final list = rows as List;
  if (list.isEmpty) return null;
  return list.first['id'] as String?;
}
