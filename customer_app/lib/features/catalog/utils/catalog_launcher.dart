import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/catalog_node_model.dart';
import '../widgets/catalog_node_modal.dart';
import '../widgets/catalog_service_detail_web_modal.dart';

/// Opens a catalog node:
///   • Leaf-bookable on web (≥768): two-column service detail dialog
///   • Leaf-bookable on mobile (<768): full-screen CatalogNodeScreen push
///   • Category nodes (hasChildren): existing browse modal on all sizes
void openCatalogNode(BuildContext context, CatalogNodeModel node,
    {String? parentId}) {
  if (node.isLeafBookable) {
    if (MediaQuery.of(context).size.width >= 768) {
      CatalogServiceDetailWebModal.show(context, node, parentId: parentId);
    } else {
      context.push('/catalog/${node.id}', extra: node);
    }
  } else {
    CatalogNodeModal.open(context, node, parentId: parentId);
  }
}
