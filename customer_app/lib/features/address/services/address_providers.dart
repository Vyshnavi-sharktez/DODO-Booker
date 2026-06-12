import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/address_model.dart';
import 'address_service.dart';

final addressServiceProvider = Provider<AddressService>(
  (ref) => AddressService(),
);

class AddressNotifier
    extends StateNotifier<AsyncValue<List<AddressModel>>> {
  final AddressService _service;

  AddressNotifier(this._service) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final list = await _service.fetchAddresses();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<AddressModel> create({
    required String addressType,
    required String addressLine1,
    String? addressLine2,
    required String city,
    required String province,
    required String pincode,
  }) async {
    final isDefault = (state.valueOrNull ?? []).isEmpty;
    final address = await _service.createAddress(
      addressType: addressType,
      addressLine1: addressLine1,
      addressLine2: addressLine2,
      city: city,
      state: province,
      pincode: pincode,
      isDefault: isDefault,
    );
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([...current, address]);
    return address;
  }

  Future<AddressModel> update(
    String id, {
    required String addressType,
    required String addressLine1,
    String? addressLine2,
    required String city,
    required String province,
    required String pincode,
  }) async {
    final updated = await _service.updateAddress(
      id,
      addressType: addressType,
      addressLine1: addressLine1,
      addressLine2: addressLine2,
      city: city,
      state: province,
      pincode: pincode,
    );
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(
      current.map((a) => a.id == id ? updated : a).toList(),
    );
    return updated;
  }

  Future<void> delete(String id) async {
    await _service.deleteAddress(id);
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(
      current.where((a) => a.id != id).toList(),
    );
  }
}

final addressNotifierProvider = StateNotifierProvider<AddressNotifier,
    AsyncValue<List<AddressModel>>>(
  (ref) => AddressNotifier(ref.read(addressServiceProvider)),
);
