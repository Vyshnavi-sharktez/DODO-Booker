import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/cancellation_policy_repository.dart';
import '../../domain/models/cancellation_policy.dart';

final _repoProvider = Provider<CancellationPolicyRepository>(
  (ref) => CancellationPolicyRepository(Supabase.instance.client),
);

final cancellationPoliciesProvider =
    FutureProvider<List<CancellationPolicy>>((ref) async {
  return ref.read(_repoProvider).fetchPolicies();
});
