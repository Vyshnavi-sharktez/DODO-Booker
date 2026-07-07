import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/customer_search_repository.dart';
import '../../domain/models/customer_search_record.dart';

final customerSearchRepositoryProvider =
    Provider<CustomerSearchRepository>((ref) {
  return CustomerSearchRepository(ref.watch(supabaseClientProvider));
});

/// Loads the full customer search index once and caches it for the session.
///
/// Invalidate with [ref.invalidate(customerSearchIndexProvider)] after any
/// mutation that might affect searchable fields (create, update).
final customerSearchIndexProvider =
    FutureProvider<Map<String, CustomerSearchRecord>>((ref) {
  return ref.watch(customerSearchRepositoryProvider).fetchSearchIndex();
});
