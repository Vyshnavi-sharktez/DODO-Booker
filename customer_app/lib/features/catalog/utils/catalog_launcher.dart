import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/catalog_node_model.dart';
import '../screens/catalog_node_screen.dart';
import '../../../routes/app_router.dart';

/// Opens a catalog node:
///   • Leaf bookable node on mobile: bottom sheet with CatalogNodeScreen
///   • Leaf bookable node on web: floating modal with CatalogNodeScreen
///   • Category / non-bookable node: full-page CategoryExplorerScreen
void openCatalogNode(BuildContext context, CatalogNodeModel node,
    {String? parentId, String? rootCategoryId}) {
  if (node.isLeafBookable) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    if (isMobile) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        // Root navigator ensures the sheet overlay is above _MobileCartShell's
        // Positioned cart bar, which otherwise paints on top of the sheet's
        // sticky booking footer when the cart is non-empty.
        useRootNavigator: true,
        backgroundColor: Colors.transparent,
        builder: (_) => CatalogNodeScreen(
          node: node,
          parentNodeId: parentId,
          rootCategoryId: rootCategoryId,
          inSheet: true,
        ),
      );
    } else {
      _showNodeAsWebModal(context, node,
          parentId: parentId, rootCategoryId: rootCategoryId);
    }
  } else {
    context.push(AppRoutes.categoryExplorer, extra: {'node': node});
  }
}

Future<void> _showNodeAsWebModal(
  BuildContext context,
  CatalogNodeModel node, {
  String? parentId,
  String? rootCategoryId,
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
            child: const ColoredBox(color: Color(0x55000000)),
          ),
        ),
        CatalogNodeScreen(
            node: node,
            parentNodeId: parentId,
            rootCategoryId: rootCategoryId,
            inModal: true),
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
