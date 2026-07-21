import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/application/providers/auth_provider.dart';
import '../../../service_attributes/application/providers/service_attributes_providers.dart';
import '../../../service_attributes/data/service_attributes_repository.dart';
import '../../../service_attributes/domain/models/service_attribute.dart';
import '../../../service_attributes/domain/models/service_attribute_option.dart';
import '../../data/catalog_node_repository.dart';
import '../../domain/models/catalog_node.dart';

// ── Repository provider ────────────────────────────────────────────────────────

final catalogNodeRepositoryProvider = Provider<CatalogNodeRepository>((ref) {
  return CatalogNodeRepository(ref.watch(supabaseClientProvider));
});

// ── Node list notifier ─────────────────────────────────────────────────────────

class CatalogNodeNotifier
    extends StateNotifier<AsyncValue<List<CatalogNode>>> {
  final CatalogNodeRepository _repo;

  CatalogNodeNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchAll);
  }

  Future<void> refresh() => _load();

  Future<void> createNode({
    String? parentId,
    required String name,
    required String slug,
    String? description,
    String? imageUrl,
    String? iconKey,
    required int sortOrder,
    required bool isActive,
    required bool isBookable,
    double? basePrice,
    int? estimatedDuration,
    double? minimumOrderAmount,
  }) async {
    await _repo.createNode(
      parentId: parentId,
      name: name,
      slug: slug,
      description: description,
      imageUrl: imageUrl,
      iconKey: iconKey,
      sortOrder: sortOrder,
      isActive: isActive,
      isBookable: isBookable,
      basePrice: basePrice,
      estimatedDuration: estimatedDuration,
      minimumOrderAmount: minimumOrderAmount,
    );
    await _load();
  }

  Future<void> updateNode(
    String id, {
    required String name,
    required String slug,
    String? description,
    String? imageUrl,
    String? iconKey,
    required int sortOrder,
    required bool isActive,
    required bool isBookable,
    double? basePrice,
    int? estimatedDuration,
    double? minimumOrderAmount,
  }) async {
    await _repo.updateNode(
      id,
      name: name,
      slug: slug,
      description: description,
      imageUrl: imageUrl,
      iconKey: iconKey,
      sortOrder: sortOrder,
      isActive: isActive,
      isBookable: isBookable,
      basePrice: basePrice,
      estimatedDuration: estimatedDuration,
      minimumOrderAmount: minimumOrderAmount,
    );
    await _load();
  }

  Future<void> deleteNode(String id) async {
    await _repo.deleteNode(id);
    await _load();
  }

  // ── Category relationship management ───────────────────────────────────────

  Future<void> addParent(String nodeId, String parentId) async {
    await _repo.addParent(nodeId, parentId);
    await _load();
  }

  Future<void> removeParent(String nodeId, String parentId) async {
    await _repo.removeParent(nodeId, parentId);
    await _load();
  }

  // ── Availability ───────────────────────────────────────────────────────────

  /// Sets availability for [nodeId].
  /// When [parentIdContext] is non-null: updates the relationship row (path-scoped).
  /// When null: updates the node row directly (node-scoped; use for root nodes).
  Future<void> setAvailability(
    String nodeId,
    String? parentIdContext,
    String status,
    String? message,
  ) async {
    if (parentIdContext != null) {
      await _repo.setRelationshipAvailability(parentIdContext, nodeId, status, message);
    } else {
      await _repo.setNodeAvailability(nodeId, status, message);
    }
    await _load();
  }

  // ── Optimistic toggles ─────────────────────────────────────────────────────

  Future<void> toggleActive(String id, {required bool isActive}) async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current
            .map((n) => n.id == id ? n.copyWith(isActive: isActive) : n)
            .toList(),
      );
    }
    try {
      await _repo.toggleActive(id, isActive: isActive);
    } catch (_) {
      await _load();
      rethrow;
    }
  }

  Future<void> toggleBookable(String id, {required bool isBookable}) async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current
            .map((n) => n.id == id ? n.copyWith(isBookable: isBookable) : n)
            .toList(),
      );
    }
    try {
      await _repo.toggleBookable(id, isBookable: isBookable);
    } catch (_) {
      await _load();
      rethrow;
    }
  }
}

final catalogNodeNotifierProvider = StateNotifierProvider<CatalogNodeNotifier,
    AsyncValue<List<CatalogNode>>>((ref) {
  return CatalogNodeNotifier(ref.watch(catalogNodeRepositoryProvider));
});

// ── Node attributes notifier ───────────────────────────────────────────────────

class CatalogNodeAttributesNotifier
    extends StateNotifier<AsyncValue<List<ServiceAttribute>>> {
  final ServiceAttributesRepository _repo;
  String? _currentNodeId;

  CatalogNodeAttributesNotifier(this._repo)
      : super(const AsyncValue.data([]));

  Future<void> loadForNode(String nodeId) async {
    _currentNodeId = nodeId;
    await _reload();
  }

  Future<void> _reload() async {
    if (_currentNodeId == null) return;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _repo.fetchByNode(_currentNodeId!),
    );
  }

  Future<String> createAttribute({
    required String nodeId,
    required String name,
    required String fieldType,
    required bool isRequired,
  }) async {
    final attr = await _repo.createAttributeForNode(
      nodeId: nodeId,
      name: name,
      fieldType: fieldType,
      isRequired: isRequired,
    );
    await _reload();
    return attr.id;
  }

  Future<String> updateAttribute(
    String id, {
    required String name,
    required String fieldType,
    required bool isRequired,
  }) async {
    await _repo.updateAttributeName(
      id,
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

  Future<void> createOption({
    required String attributeId,
    required String optionName,
    required double priceAdjustment,
  }) async {
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

  Future<void> reorderOptions(
    String attributeId,
    List<ServiceAttributeOption> reorderedOptions,
  ) async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current.map((attr) {
          if (attr.id != attributeId) return attr;
          return attr.copyWith(options: reorderedOptions);
        }).toList(),
      );
    }
    await _repo.reorderOptions(
      reorderedOptions
          .asMap()
          .entries
          .map((e) => (id: e.value.id, sortOrder: e.key))
          .toList(),
    );
  }
}

// ── Relationship availability map ──────────────────────────────────────────────
// Keyed by "$parentId|$childId" → availability_status.
// Loaded once and invalidated after any setAvailability save so the admin tree
// immediately reflects the updated per-path icon without a full page reload.

final relAvailabilityProvider =
    FutureProvider<Map<String, String>>((ref) {
  final repo = ref.watch(catalogNodeRepositoryProvider);
  return repo.fetchAllRelationshipStatuses();
});

final catalogNodeAttributesNotifierProvider = StateNotifierProvider<
    CatalogNodeAttributesNotifier,
    AsyncValue<List<ServiceAttribute>>>((ref) {
  return CatalogNodeAttributesNotifier(
    ref.watch(serviceAttributesRepositoryProvider),
  );
});
