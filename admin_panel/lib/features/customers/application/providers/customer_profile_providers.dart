import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/customer_profile_repository.dart';
import '../../domain/models/customer_profile.dart';

final customerProfileRepositoryProvider =
    Provider<CustomerProfileRepository>((ref) {
  return CustomerProfileRepository(ref.watch(supabaseClientProvider));
});

final customerProfileProvider =
    FutureProvider.autoDispose.family<CustomerProfile, String>(
  (ref, customerId) => ref
      .watch(customerProfileRepositoryProvider)
      .fetchCustomerProfile(customerId),
);
