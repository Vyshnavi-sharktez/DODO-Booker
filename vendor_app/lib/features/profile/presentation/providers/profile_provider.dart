import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../data/datasources/profile_remote_datasource.dart';
import '../../data/repositories/profile_repository_impl.dart';
import '../../domain/models/vendor_profile.dart';
import '../../domain/repositories/i_profile_repository.dart';
import '../../domain/usecases/get_vendor_profile_usecase.dart';
import '../../domain/usecases/update_vendor_profile_usecase.dart';

final profileDatasourceProvider = Provider<ProfileRemoteDatasource>((ref) {
  return ProfileRemoteDatasource(ref.watch(supabaseClientProvider));
});

final profileRepositoryProvider = Provider<IProfileRepository>((ref) {
  return ProfileRepositoryImpl(ref.watch(profileDatasourceProvider));
});

final getVendorProfileUseCaseProvider = Provider<GetVendorProfileUseCase>((ref) {
  return GetVendorProfileUseCase(ref.watch(profileRepositoryProvider));
});

final updateVendorProfileUseCaseProvider = Provider<UpdateVendorProfileUseCase>((ref) {
  return UpdateVendorProfileUseCase(ref.watch(profileRepositoryProvider));
});

final vendorProfileProvider = FutureProvider<VendorProfile?>((ref) async {
  final user = ref.watch(currentVendorUserProvider);
  if (user == null) return null;
  return ref.read(getVendorProfileUseCaseProvider)(user.phone);
});

class EditProfileNotifier extends StateNotifier<AsyncValue<void>> {
  EditProfileNotifier(this._useCase) : super(const AsyncValue.data(null));
  final UpdateVendorProfileUseCase _useCase;

  Future<void> save({
    required String phone,
    required Map<String, dynamic> fields,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _useCase(phone: phone, fields: fields),
    );
  }
}

final editProfileProvider =
    StateNotifierProvider.autoDispose<EditProfileNotifier, AsyncValue<void>>(
  (ref) => EditProfileNotifier(ref.read(updateVendorProfileUseCaseProvider)),
);
