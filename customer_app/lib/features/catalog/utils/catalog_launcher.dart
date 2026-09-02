import 'dart:ui';

import 'package:flutter/material.dart';
import '../models/catalog_node_model.dart';
import '../screens/catalog_node_screen.dart';
import '../widgets/catalog_node_modal.dart';

/// Opens a catalog node:
///   • Any node on web (≥768): floating modal over the app
///   • Any node on mobile (<768): proper bottom sheet using CatalogNodeScreen
void openCatalogNode(BuildContext context, CatalogNodeModel node,
    {String? parentId}) {
  final isMobile = MediaQuery.of(context).size.width < 768;
  if (node.isLeafBookable) {
    if (isMobile) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => CatalogNodeScreen(
          node: node,
          parentNodeId: parentId,
          inSheet: true,
        ),
      );
    } else {
      _showNodeAsWebModal(context, node, parentId: parentId);
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
