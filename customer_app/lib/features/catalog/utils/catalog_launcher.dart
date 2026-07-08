import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/catalog_node_model.dart';

/// Navigate to a catalog node. Always pushes the route so the back-stack is
/// preserved for multi-level tree traversal.
///
/// Prefer this over direct `context.push('/catalog/...')` calls so
/// Phase 4 can add desktop-modal behaviour in one place.
void openCatalogNode(BuildContext context, CatalogNodeModel node) {
  context.push('/catalog/${node.id}', extra: node);
}
