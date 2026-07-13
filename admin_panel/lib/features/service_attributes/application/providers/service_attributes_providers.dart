import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/service_attributes_repository.dart';
import '../../domain/models/service_attribute.dart';
import '../../domain/models/service_attribute_option.dart';

final serviceAttributesRepositoryProvider =
    Provider<ServiceAttributesRepository>((ref) {
  return ServiceAttributesRepository(ref.watch(supabaseClientProvider));
});

class ServiceAttributesNotifier
    extends StateNotifier<AsyncValue<List<ServiceAttribute>>> {
  final ServiceAttributesRepository _repo;
  String? _currentServiceId;
  String? _currentNodeId;

  ServiceAttributesNotifier(this._repo) : super(const AsyncValue.data([]));

  Future<void> loadForService(String serviceId) async {
    _currentServiceId = serviceId;
    _currentNodeId = null;
    await _reload();
  }

  /// Loads attributes for a catalog node (Phase 2+). Used by
  /// [AttributeOptionsDialog] when opened from the catalog node drawer so it
  /// reads and writes the correct rows via node_id.
  Future<void> loadForNode(String nodeId) async {
    _currentNodeId = nodeId;
    _currentServiceId = null;
    await _reload();
  }

  Future<void> refresh() => _reload();

  Future<void> _reload() async {
    if (_currentServiceId == null && _currentNodeId == null) return;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      _currentServiceId != null
          ? () => _repo.fetchByService(_currentServiceId!)
          : () => _repo.fetchByNode(_currentNodeId!),
    );
  }

  Future<String> createAttribute({
    required String serviceId,
    required String name,
    required String fieldType,
    required bool isRequired,
  }) async {
    final attr = await _repo.createAttribute(
      serviceId: serviceId,
      name: name,
      fieldType: fieldType,
      isRequired: isRequired,
    );
    await _reload();
    return attr.id;
  }

  Future<String> updateAttribute(
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
    return id;
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
    // Append at the end of the current list.
    final attrs = state.valueOrNull ?? [];
    final attr = attrs.where((a) => a.id == attributeId).firstOrNull;
    final nextSortOrder = attr?.options.length ?? 0;

    await _repo.createOption(
      attributeId: attributeId,
      optionName: optionName,
      priceAdjustment: priceAdjustment,
      sortOrder: nextSortOrder,
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

  /// Optimistically reorders the options for [attributeId] and persists the
  /// new sort_order values to Supabase in a single batch upsert.
  Future<void> reorderOptions(
    String attributeId,
    List<ServiceAttributeOption> reorderedOptions,
  ) async {
    // Optimistic update so the UI reflects the drag immediately.
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current.map((attr) {
          if (attr.id != attributeId) return attr;
          return attr.copyWith(options: reorderedOptions);
        }).toList(),
      );
    }

    // Assign contiguous sort_order values (0, 1, 2, …) and persist.
    await _repo.reorderOptions(
      reorderedOptions
          .asMap()
          .entries
          .map((e) => (id: e.value.id, sortOrder: e.key))
          .toList(),
    );
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

/// Self-contained service list for the service picker in this module.
/// Fetches only id + name — no dependency on the services module's provider.
final serviceDropdownsProvider =
    FutureProvider<List<({String id, String name})>>((ref) =>
        ref
            .watch(serviceAttributesRepositoryProvider)
            .fetchServiceDropdowns());
