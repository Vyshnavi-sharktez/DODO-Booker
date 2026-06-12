import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../data/profile_repository.dart';
import '../../domain/models/vendor_profile.dart';

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(supabaseClientProvider)),
);

class ProfileNotifier extends StateNotifier<AsyncValue<VendorProfile?>> {
  ProfileNotifier(this._repo) : super(const AsyncValue.data(null));

  final ProfileRepository _repo;

  Future<void> load(String vendorId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.fetchProfile(vendorId));
  }

  Future<void> update(
    String vendorId,
    Map<String, dynamic> fields,
  ) async {}
}

final profileNotifierProvider =
    StateNotifierProvider<ProfileNotifier, AsyncValue<VendorProfile?>>(
  (ref) => ProfileNotifier(ref.watch(profileRepositoryProvider)),
);
