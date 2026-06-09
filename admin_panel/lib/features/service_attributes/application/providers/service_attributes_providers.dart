import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/service_attributes_repository.dart';
import '../../domain/models/service_attribute.dart';

final serviceAttributesRepositoryProvider =
    Provider<ServiceAttributesRepository>((ref) {
  return ServiceAttributesRepository(ref.watch(supabaseClientProvider));
});

class ServiceAttributesNotifier
    extends StateNotifier<AsyncValue<List<ServiceAttribute>>> {
  final ServiceAttributesRepository _repo;
  String? _currentServiceId;

  ServiceAttributesNotifier(this._repo) : super(const AsyncValue.data([]));

  Future<void> loadForService(String serviceId) async {
    _currentServiceId = serviceId;
    await _reload();
  }

  Future<void> refresh() => _reload();

  Future<void> _reload() async {
    if (_currentServiceId == null) return;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _repo.fetchByService(_currentServiceId!),
    );
  }

  Future<void> createAttribute({
    required String serviceId,
    required String name,
    required String fieldType,
    required bool isRequired,
  }) async {
    await _repo.createAttribute(
      serviceId: serviceId,
      name: name,
      fieldType: fieldType,
      isRequired: isRequired,
    );
    await _reload();
  }

  Future<void> updateAttribute(
    String id, {
    required String serviceId,
    required String name,
    required String fieldType,
    required bool isRequired,
  }) async {
    await _repo.updateAttribute(
      id,
      serviceId: serviceId,
      name: name,
      fieldType: fieldType,
      isRequired: isRequired,
    );
    await _reload();
  }

  Future<void> deleteAttribute(String id) async {
    await _repo.deleteAttribute(id);
    await _reload();
  }

  // ── Options ────────────────────────────────────────────────────────────────

  Future<void> createOption({
    required String attributeId,
    required String optionName,
    required double priceAdjustment,
  }) async {
    await _repo.createOption(
      attributeId: attributeId,
      optionName: optionName,
      priceAdjustment: priceAdjustment,
    );
    await _reload();
  }

  Future<void> updateOption(
    String optionId, {
    required String optionName,
    required double priceAdjustment,
  }) async {
    await _repo.updateOption(
      optionId,
      optionName: optionName,
      priceAdjustment: priceAdjustment,
    );
    await _reload();
  }

  Future<void> deleteOption(String optionId) async {
    await _repo.deleteOption(optionId);
    await _reload();
  }
}

final serviceAttributesNotifierProvider = StateNotifierProvider<
    ServiceAttributesNotifier, AsyncValue<List<ServiceAttribute>>>((ref) {
  return ServiceAttributesNotifier(
      ref.watch(serviceAttributesRepositoryProvider));
});

final singleAttributeProvider =
    Provider.family<ServiceAttribute?, String>((ref, attributeId) {
  final list = ref.watch(serviceAttributesNotifierProvider).valueOrNull ?? [];
  return list.where((a) => a.id == attributeId).firstOrNull;
});
