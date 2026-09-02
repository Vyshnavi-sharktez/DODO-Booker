import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/service_image_registry.dart';
import '../../category/services/category_providers.dart';
import '../../loyalty/providers/loyalty_providers.dart';
import '../../loyalty/utils/loyalty_utils.dart';
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

            // Loyalty earn badge — directly below name, before price
            if (node.isLeafBookable && node.loyaltyEarnEnabled)
              Consumer(
                builder: (_, ref, _) {
                  final settings =
                      ref.watch(loyaltySettingsProvider).valueOrNull;
                  if (settings == null ||
                      !settings.isEnabled ||
                      !settings.earnEnabled) {
                    return const SizedBox.shrink();
                  }
                  final cfgAsync = ref.watch(resolvedLoyaltyConfigProvider((
                    serviceId: node.id,
                    parentNodeId: node.parentId,
                  )));
                  if (!cfgAsync.hasValue) return const SizedBox.shrink();
                  final pts = computeLoyaltyPoints(
                    cfgAsync.valueOrNull,
                    settings,
                    node.basePrice ?? 0,
                  );
                  if (pts <= 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: LoyaltyEarnBadge(points: pts),
                  );
                },
              ),

            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Consumer(
                    builder: (_, ref, _) {
                      final attrs =
                          ref.watch(serviceAttributesProvider(node.id)).valueOrNull ?? [];
                      final attrOpts =
                          attrs.where((a) => a.options.isNotEmpty).toList();
                      if (attrOpts.isNotEmpty) {
                        final lowestOpt = attrOpts
                            .map((a) => a.options.first)
                            .reduce((a, b) =>
                                a.finalPrice <= b.finalPrice ? a : b);
                        final startsAt = lowestOpt.finalPrice;
                        final origStartsAt = lowestOpt.priceAdjustment;
                        final hasDisc = lowestOpt.hasDiscount;
                        return Wrap(
                          spacing: 5,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Starts at ₹${startsAt.toInt()}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1A1A1A),
                                height: 1.2,
                              ),
                            ),
                            if (hasDisc)
                              Text(
                                '₹${origStartsAt.toInt()}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF888888),
                                  decoration: TextDecoration.lineThrough,
                                  height: 1.2,
                                ),
                              ),
                          ],
                        );
                      }
                      if (node.basePrice != null) {
                        return Wrap(
                          spacing: 5,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '₹${(node.finalPrice ?? node.basePrice)!.toInt()}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1A1A1A),
                                height: 1.2,
                              ),
                            ),
                            if (node.hasDiscount)
                              Text(
                                '₹${node.basePrice!.toInt()}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF888888),
                                  decoration: TextDecoration.lineThrough,
                                  height: 1.2,
                                ),
                              ),
                          ],
                        );
                      }
                      if (node.hasChildren) {
                        return Text(
                          '${node.childrenCount} ${node.childrenCount == 1 ? 'option' : 'options'}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A1A),
                            height: 1.2,
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),

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

// ── Loyalty earn badge ────────────────────────────────────────────────────────

class LoyaltyEarnBadge extends StatelessWidget {
  final int points;
  const LoyaltyEarnBadge({required this.points});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.gold.withAlpha(22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.gold.withAlpha(80), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.workspace_premium_rounded,
              size: 14, color: AppColors.gold),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              'Earn $points loyalty points (₹$points)',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.gold,
                height: 1.2,
                letterSpacing: 0.1,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
