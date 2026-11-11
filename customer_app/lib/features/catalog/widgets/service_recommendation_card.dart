import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/service_image_registry.dart';
import '../models/catalog_node_model.dart';
import '../utils/catalog_launcher.dart';

/// Horizontal recommendation card (162 × 248) used in the cart
/// "You might also want" strip and the InstaHelp checkout "More Services"
/// section.  Tapping View or Add both navigate to the service detail/booking
/// flow via [openCatalogNode].
class ServiceRecommendationCard extends StatelessWidget {
  const ServiceRecommendationCard({super.key, required this.node});
  final CatalogNodeModel node;

  @override
  Widget build(BuildContext context) {
    final imageUrl = ServiceImageRegistry.resolveMobile(
      node.mobileImageUrl,
      node.imageUrl,
      node.name,
    );
    final price = node.finalPrice ?? node.basePrice;

    return SizedBox(
      width: 162,
      child: GestureDetector(
        onTap: () => openCatalogNode(context, node, parentId: node.parentId),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(10),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Hero image ─────────────────────────────────────────────
                SizedBox(
                  height: 96,
                  width: double.infinity,
                  child: imageUrl != null
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _placeholder,
                        )
                      : _placeholder,
                ),

                // ── Content ────────────────────────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.name,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),

                        const SizedBox(height: 4),

                        if (price != null)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '₹${price.toInt()}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              if (node.hasDiscount &&
                                  node.basePrice != null) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '₹${node.basePrice!.toInt()}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textHint,
                                    decoration: TextDecoration.lineThrough,
                                    decorationColor: AppColors.textHint,
                                  ),
                                ),
                              ],
                            ],
                          ),

                        if (node.rating > 0 && node.reviewCount > 0) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              const Icon(Icons.star_rounded,
                                  size: 12, color: AppColors.gold),
                              const SizedBox(width: 2),
                              Text(
                                node.rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '(${node.reviewCount})',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textHint,
                                ),
                              ),
                            ],
                          ),
                        ],

                        const Spacer(),

                        Row(
                          children: [
                            Expanded(
                              child: RecButton(
                                label: 'View',
                                filled: false,
                                onTap: () => openCatalogNode(context, node,
                                    parentId: node.parentId),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: RecButton(
                                label: 'Add',
                                filled: true,
                                onTap: () => openCatalogNode(context, node,
                                    parentId: node.parentId),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const Widget _placeholder = ColoredBox(
    color: AppColors.primaryLight,
    child: Center(
      child: Icon(
        Icons.home_repair_service_rounded,
        size: 34,
        color: AppColors.primary,
      ),
    ),
  );
}

// ── Small action button ───────────────────────────────────────────────────────

class RecButton extends StatelessWidget {
  const RecButton({
    super.key,
    required this.label,
    required this.filled,
    required this.onTap,
  });
  final String label;
  final bool filled;
  final VoidCallback onTap;

  static const _shape =
      RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8)));
  static const _textStyle =
      TextStyle(fontSize: 11, fontWeight: FontWeight.w600);

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return SizedBox(
        height: 28,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 28),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: _textStyle,
            shape: _shape,
          ),
          child: Text(label),
        ),
      );
    }
    return SizedBox(
      height: 28,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border, width: 0.8),
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: _textStyle,
          shape: _shape,
        ),
        child: Text(label),
      ),
    );
  }
}
