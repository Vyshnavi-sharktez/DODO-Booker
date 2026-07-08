import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/service_image_registry.dart';
import '../models/catalog_node_model.dart';

/// Card widget used in the children grid of [CatalogNodeScreen] and the root
/// grid of [CatalogBrowseScreen]. Mirrors the visual style of the home
/// categories carousel cards.
class CatalogNodeCard extends StatefulWidget {
  const CatalogNodeCard({
    super.key,
    required this.node,
    required this.colorIndex,
    required this.onTap,
  });

  final CatalogNodeModel node;
  final int colorIndex;
  final VoidCallback onTap;

  @override
  State<CatalogNodeCard> createState() => _CatalogNodeCardState();
}

class _CatalogNodeCardState extends State<CatalogNodeCard> {
  bool _hovered = false;
  bool _navigating = false;

  void _navigate() {
    if (_navigating) return;
    _navigating = true;
    widget.onTap();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _navigating = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _navigate,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFEBEBEB),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(_hovered ? 26 : 14),
                blurRadius: _hovered ? 22 : 10,
                spreadRadius: 0,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _CardImage(node: widget.node)),
                _CardInfo(node: widget.node, onTap: _navigate),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardImage extends StatelessWidget {
  final CatalogNodeModel node;
  const _CardImage({required this.node});

  @override
  Widget build(BuildContext context) {
    final url = ServiceImageRegistry.resolve(node.imageUrl, node.name);
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (_, child, p) =>
          p == null ? child : const ColoredBox(color: Color(0xFFEEEEEE)),
      errorBuilder: (_, _, _) => Container(
        color: AppColors.goldLight,
        alignment: Alignment.center,
        child: const Icon(
          Icons.home_repair_service_rounded,
          size: 32,
          color: AppColors.gold,
        ),
      ),
    );
  }
}

class _CardInfo extends StatelessWidget {
  final CatalogNodeModel node;
  final VoidCallback onTap;
  const _CardInfo({required this.node, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              node.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A),
                height: 1.25,
              ),
            ),
            if (node.description?.isNotEmpty == true) ...[
              const SizedBox(height: 3),
              Text(
                node.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textHint,
                  height: 1.2,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Show price if bookable, child count otherwise
                if (node.isBookable && node.basePrice != null)
                  Text(
                    '₹${node.basePrice!.toInt()}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A1A),
                      height: 1.2,
                    ),
                  )
                else if (node.hasChildren)
                  Text(
                    '${node.childrenCount} ${node.childrenCount == 1 ? 'option' : 'options'}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A1A),
                      height: 1.2,
                    ),
                  )
                else
                  const SizedBox.shrink(),

                GestureDetector(
                  onTap: onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.textPrimary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'View',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
