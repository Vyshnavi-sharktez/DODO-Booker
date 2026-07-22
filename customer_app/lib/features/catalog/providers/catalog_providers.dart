import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/faq_model.dart';
import '../models/catalog_node_model.dart';
import '../services/catalog_service.dart';

final catalogServiceProvider =
    Provider<CatalogService>((ref) => CatalogService());

/// All active top-level catalog items (no parent category).
final rootCatalogNodesProvider =
    FutureProvider<List<CatalogNodeModel>>((ref) {
  return ref.read(catalogServiceProvider).fetchRootNodes();
});

/// A single catalog node by ID (used for deep-link recovery).
final catalogNodeProvider =
    FutureProvider.family<CatalogNodeModel?, String>((ref, id) {
  return ref.read(catalogServiceProvider).fetchNode(id);
});

/// Active direct children of a catalog node.
final catalogNodeChildrenProvider =
    FutureProvider.family<List<CatalogNodeModel>, String>((ref, parentId) {
  return ref.read(catalogServiceProvider).fetchChildren(parentId);
});

/// FAQs for a catalog node (queried by node_id).
final catalogNodeFaqsProvider =
    FutureProvider.family<List<FaqModel>, String>((ref, nodeId) {
  return ref.read(catalogServiceProvider).fetchFaqsForNode(nodeId);
});

/// Effective availability of a node for a given parent context.
/// Pass parentId = node.parentId as fallback when the true path is unknown
/// (deep-link entry) so the canonical path is used instead.
/// Provide lat/lng from the customer's default address to also enforce
/// location restrictions; omit to skip the location check.
typedef _AvailabilityParams = ({
  String nodeId,
  String? parentId,
  double? lat,
  double? lng,
});

final nodeAvailabilityProvider = FutureProvider.family<
    ({String status, String? message}), _AvailabilityParams>(
  (ref, params) => ref.read(catalogServiceProvider).checkAvailability(
        params.nodeId,
        params.parentId,
        lat: params.lat,
        lng: params.lng,
      ),
);
