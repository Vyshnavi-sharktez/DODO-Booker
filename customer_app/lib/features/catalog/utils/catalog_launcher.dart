import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/catalog_node_model.dart';
import '../screens/catalog_node_screen.dart';
import '../widgets/catalog_node_modal.dart';

/// Opens a catalog node:
///   • Leaf-bookable on web (≥768): floating _WebScaffold modal over the app
///   • Leaf-bookable on mobile (<768): full-screen CatalogNodeScreen push
///   • Category nodes (hasChildren): existing browse modal on all sizes
void openCatalogNode(BuildContext context, CatalogNodeModel node,
    {String? parentId}) {
  if (node.isLeafBookable) {
    if (MediaQuery.of(context).size.width >= 768) {
      _showNodeAsWebModal(context, node, parentId: parentId);
    } else {
      context.push(
        '/catalog/${node.id}',
        extra: {'node': node, 'parentNodeId': parentId},
      );
    }
  } else {
    CatalogNodeModal.open(context, node, parentId: parentId);
  }
}

Future<void> _showNodeAsWebModal(
  BuildContext context,
  CatalogNodeModel node, {
  String? parentId,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: '',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, _, _) => Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(ctx).pop(),
            behavior: HitTestBehavior.opaque,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: const ColoredBox(color: Color(0x70000000)),
            ),
          ),
        ),
        CatalogNodeScreen(node: node, parentNodeId: parentId, inModal: true),
      ],
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curved =
          CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}
