import 'package:flutter/material.dart';

import '../models/catalog_node_model.dart';
import '../widgets/catalog_node_modal.dart';

/// Opens a catalog node as a centered modal dialog over a blurred backdrop.
/// Stacks safely — tapping a child node opens another modal on top.
///
/// Deep-link navigation (`/catalog/:nodeId`) continues to use the full-screen
/// CatalogNodeFetchScreen so push-notification deep-links keep working.
void openCatalogNode(BuildContext context, CatalogNodeModel node,
    {String? parentId}) {
  CatalogNodeModal.open(context, node, parentId: parentId);
}
