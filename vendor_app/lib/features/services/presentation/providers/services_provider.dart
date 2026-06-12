import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../data/services_repository.dart';
import '../../domain/models/assigned_service.dart';

final servicesRepositoryProvider = Provider<ServicesRepository>(
  (ref) => ServicesRepository(ref.watch(supabaseClientProvider)),
);

final vendorServicesProvider =
    FutureProvider.family<List<AssignedService>, String>(
  (ref, vendorId) =>
      ref.watch(servicesRepositoryProvider).fetchVendorServices(vendorId),
);
