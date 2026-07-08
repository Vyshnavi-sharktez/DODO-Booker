import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/faq_model.dart';
import '../models/catalog_node_model.dart';
import '../services/catalog_service.dart';

final catalogServiceProvider =
    Provider<CatalogService>((ref) => CatalogService());

/// All active root-level catalog nodes (parent_id IS NULL).
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
