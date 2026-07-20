import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/service_image_registry.dart';
import '../../../models/faq_model.dart';
import '../../../models/service_attribute_model.dart';
import '../../../models/addon_model.dart';
import '../../cart/providers/cart_provider.dart';
import '../../cart/utils/cart_launcher.dart';
import '../../category/services/category_providers.dart';
import '../../reviews/widgets/service_reviews_section.dart';
import '../../service/widgets/faq_section.dart';
import '../../service/widgets/service_addon_section.dart';
import '../../service/widgets/service_attribute_section.dart';
import '../../loyalty/providers/loyalty_providers.dart';
import '../../loyalty/utils/loyalty_utils.dart';
import '../../wishlist/widgets/heart_button.dart';
import '../models/catalog_node_model.dart';
import '../providers/catalog_providers.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CatalogNodeModal — premium centered dialog with blurred backdrop.
//
// Supports the full behaviour matrix:
//   hasChildren             → hero + floating card + vertical child list
//   isLeafBookable          → hero + floating card + booking content + sticky bar
//   !hasChildren !isBookable → hero + floating card + Coming Soon
//
// Use [CatalogNodeModal.open] to show; it handles its own transition.
// ═══════════════════════════════════════════════════════════════════════════════

class CatalogNodeModal extends ConsumerStatefulWidget {
  const CatalogNodeModal({
    super.key,
    required this.node,
    this.parentNodeId,
  });

  final CatalogNodeModel node;

  /// The catalog_node.id of the parent through which this node was navigated.
  /// Null for root-level nodes or deep-link entry points.
  final String? parentNodeId;

  /// Shows the modal with a fade+scale transition over a blurred backdrop.
  /// Stacks safely — tapping a child node opens another modal on top.
  static Future<void> open(
    BuildContext context,
    CatalogNodeModel node, {
    String? parentId,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: '',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, _, _) =>
          CatalogNodeModal(node: node, parentNodeId: parentId),
      transitionBuilder: (ctx, anim, _, child) {
        final curved =
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  ConsumerState<CatalogNodeModal> createState() => _CatalogNodeModalState();
}

class _CatalogNodeModalState extends ConsumerState<CatalogNodeModal> {
  final Map<String, String> _selections = {};
  double _priceAdjustment = 0.0;
  final Set<String> _selectedAddonIds = {};

  CatalogNodeModel get node => widget.node;

  @override
  void initState() {
    super.initState();
    // Invalidate loyaltySettingsProvider on each modal open so the loyalty badge
    // always reflects the latest global earn_per_100, even when the admin changed
    // settings since the provider was last fetched.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(loyaltySettingsProvider);
    });
  }

  void _onOptionSelected(
      String attrId, String optId, List<ServiceAttributeModel> attrs) {
    setState(() {
      _selections[attrId] = optId;
      _priceAdjustment = attrs.fold(0.0, (sum, attr) {
        final sel = _selections[attr.id];
        if (sel == null) return sum;
        final opt = attr.options.where((o) => o.id == sel).firstOrNull;
        return sum + (opt?.priceAdjustment ?? 0.0);
      });
    });
  }

  void _onAddonToggled(String addonId, bool selected) {
    setState(() {
      if (selected) {
        _selectedAddonIds.add(addonId);
      } else {
        _selectedAddonIds.remove(addonId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final children =
        ref.watch(catalogNodeChildrenProvider(node.id)).valueOrNull ?? [];
    final attrs = node.isLeafBookable
        ? (ref.watch(serviceAttributesProvider(node.id)).valueOrNull ?? [])
        : <ServiceAttributeModel>[];
    final addOns = node.isLeafBookable
        ? (ref.watch(allActiveAddonsProvider).valueOrNull ?? [])
        : <AddOnModel>[];
    final faqs = node.isLeafBookable
        ? (ref.watch(catalogNodeFaqsProvider(node.id)).valueOrNull ?? [])
        : <FaqModel>[];

    final addonsTotal =
        totalAddonsPrice(buildSelectedAddons(addOns, _selectedAddonIds));
    final displayPrice =
        (node.basePrice ?? 0.0) + _priceAdjustment + addonsTotal;
    final hasAdjustment = _priceAdjustment > 0 || addonsTotal > 0;

    final heroUrl = node.hasChildren
        ? ServiceImageRegistry.resolve(node.imageUrl, node.name)
        : node.imageUrl;
    final hasHero = node.hasChildren || (heroUrl != null && heroUrl.isNotEmpty);

    return Stack(
      children: [
        // ── Blurred dimmed backdrop ──────────────────────────────────────
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: const ColoredBox(color: Color(0x72000000)),
            ),
          ),
        ),

        // ── Centered modal card ──────────────────────────────────────────
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 580,
                maxHeight: MediaQuery.of(context).size.height * 0.88,
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(64),
                          blurRadius: 56,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          // ── Hero image + floating info card ────────────
                          if (hasHero) ...[
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                SizedBox(
                                  height: 220,
                                  width: double.infinity,
                                  child: _ModalHeroImage(url: heroUrl!),
                                ),
                                // Heart button (service detail only)
                                if (node.isLeafBookable)
                                  Positioned(
                                    top: 10,
                                    right: 52,
                                    child: HeartButton(
                                        serviceId: node.id, mini: true),
                                  ),
                                // Close button
                                Positioned(
                                  top: 10,
                                  right: 10,
                                  child: _HeroCloseButton(),
                                ),
                                // Floating info card (overlaps hero bottom)
                                Positioned(
                                  bottom: -52,
                                  left: 16,
                                  right: 16,
                                  child: _ModalInfoCard(
                                    node: node,
                                    displayPrice: displayPrice,
                                    hasAdjustment: hasAdjustment,
                                  ),
                                ),
                              ],
                            ),
                            // Reserve space for card overflow + gap
                            const SizedBox(height: 68),
                          ],

                          // ── No-hero: plain header ──────────────────────
                          if (!hasHero)
                            _ModalPlainHeader(
                              node: node,
                              displayPrice: displayPrice,
                              hasAdjustment: hasAdjustment,
                            ),

                          // ── Scrollable content ─────────────────────────
                          Flexible(
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(context)
                                  .copyWith(scrollbars: false),
                              child: SingleChildScrollView(
                                padding: EdgeInsets.only(
                                    bottom: node.isLeafBookable ? 8 : 24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Attribute selection
                                    if (node.isLeafBookable && attrs.isNotEmpty)
                                      ServiceAttributeSection(
                                        attrs: attrs,
                                        selections: _selections,
                                        onChanged: (attrId, optId) =>
                                            _onOptionSelected(
                                                attrId, optId, attrs),
                                      ),

                                    // Description
                                    if (node.description?.isNotEmpty == true)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            20, 20, 20, 0),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              node.isLeafBookable
                                                  ? 'About this service'
                                                  : node.name,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              node.description!,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                color: AppColors.textSecondary,
                                                height: 1.65,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                    // Children list (category nodes)
                                    if (node.hasChildren)
                                      _ModalChildrenList(
                                        node: node,
                                        children: children,
                                      ),

                                    // Add-ons
                                    if (node.isLeafBookable && addOns.isNotEmpty)
                                      ServiceAddonSection(
                                        addOns: addOns,
                                        selectedIds: _selectedAddonIds,
                                        onToggle: _onAddonToggled,
                                      ),

                                    // FAQs
                                    if (node.isLeafBookable && faqs.isNotEmpty)
                                      FaqSection(faqs: faqs),

                                    // Reviews
                                    if (node.isLeafBookable)
                                      ServiceReviewsSection(
                                          serviceId: node.id),

                                    // Coming Soon
                                    if (!node.hasChildren && !node.isBookable)
                                      const _ModalComingSoon(),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // ── Sticky cart bar ───────────────────────────
                          if (node.isLeafBookable)
                            _ModalBookingBar(
                              node: node,
                              displayPrice: displayPrice,
                              priceAdjustment: _priceAdjustment,
                              addonsTotal: addonsTotal,
                              parentNodeId: widget.parentNodeId,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Hero image ────────────────────────────────────────────────────────────────

class _ModalHeroImage extends StatelessWidget {
  const _ModalHeroImage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          url,
          fit: BoxFit.cover,
          loadingBuilder: (_, child, p) =>
              p == null ? child : const ColoredBox(color: Color(0xFFEEEEEE)),
          errorBuilder: (_, _, _) => Container(
            color: AppColors.goldLight,
            alignment: Alignment.center,
            child: const Icon(Icons.home_repair_service_rounded,
                size: 48, color: AppColors.gold),
          ),
        ),
        // Bottom gradient for info card readability
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withAlpha(110)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Close button overlaid on hero ─────────────────────────────────────────────

class _HeroCloseButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(115),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
      ),
    );
  }
}

// ── Floating information card ─────────────────────────────────────────────────

class _ModalInfoCard extends StatelessWidget {
  const _ModalInfoCard({
    required this.node,
    required this.displayPrice,
    required this.hasAdjustment,
  });
  final CatalogNodeModel node;
  final double displayPrice;
  final bool hasAdjustment;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(22),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Parent breadcrumb tag
          if (!node.isRoot && node.parentName != null) ...[
            Row(
              children: [
                const Icon(Icons.chevron_left_rounded,
                    size: 13, color: AppColors.textHint),
                const SizedBox(width: 2),
                Text(
                  node.parentName!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textHint,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
          ],

          // Node name
          Text(
            node.name,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              height: 1.2,
            ),
          ),

          // Rating + duration
          if (node.rating > 0 || node.estimatedDuration != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (node.rating > 0) ...[
                  const Icon(Icons.star_rounded,
                      size: 13, color: AppColors.gold),
                  const SizedBox(width: 3),
                  Text(
                    node.rating.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (node.reviewCount > 0) ...[
                    const SizedBox(width: 3),
                    Text(
                      '(${node.reviewCount})',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                  const SizedBox(width: 12),
                ],
                if (node.estimatedDuration != null) ...[
                  const Icon(Icons.schedule_rounded,
                      size: 12, color: AppColors.textSecondary),
                  const SizedBox(width: 3),
                  Text(
                    '${node.estimatedDuration} min',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ],

          // Price row (service) or count chip (category)
          if (node.isLeafBookable && node.basePrice != null) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '₹${displayPrice.toInt()}',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  hasAdjustment ? 'incl. adjustments' : 'onwards',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textHint),
                ),
              ],
            ),
          ] else if (node.hasChildren) ...[
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${node.childrenCount} '
                '${node.childrenCount == 1 ? 'service' : 'services'} available',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Plain header (no hero image) ──────────────────────────────────────────────

class _ModalPlainHeader extends StatelessWidget {
  const _ModalPlainHeader({
    required this.node,
    required this.displayPrice,
    required this.hasAdjustment,
  });
  final CatalogNodeModel node;
  final double displayPrice;
  final bool hasAdjustment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!node.isRoot && node.parentName != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.chevron_left_rounded,
                          size: 13, color: AppColors.textHint),
                      const SizedBox(width: 2),
                      Text(
                        node.parentName!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  node.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    height: 1.2,
                  ),
                ),
                if (node.rating > 0 || node.estimatedDuration != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (node.rating > 0) ...[
                        const Icon(Icons.star_rounded,
                            size: 13, color: AppColors.gold),
                        const SizedBox(width: 3),
                        Text(node.rating.toStringAsFixed(1),
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        if (node.reviewCount > 0) ...[
                          const SizedBox(width: 3),
                          Text('(${node.reviewCount})',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary)),
                        ],
                        const SizedBox(width: 12),
                      ],
                      if (node.estimatedDuration != null) ...[
                        const Icon(Icons.schedule_rounded,
                            size: 12, color: AppColors.textSecondary),
                        const SizedBox(width: 3),
                        Text('${node.estimatedDuration} min',
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary)),
                      ],
                    ],
                  ),
                ],
                if (node.isLeafBookable && node.basePrice != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '₹${displayPrice.toInt()}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        hasAdjustment ? 'incl. adjustments' : 'onwards',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textHint),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                const Divider(height: 1, color: AppColors.divider),
              ],
            ),
          ),
          // Close + heart column
          Column(
            children: [
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                style: IconButton.styleFrom(
                    foregroundColor: AppColors.textSecondary),
              ),
              if (node.isLeafBookable)
                HeartButton(serviceId: node.id, mini: true),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Children list ─────────────────────────────────────────────────────────────

class _ModalChildrenList extends StatelessWidget {
  const _ModalChildrenList({
    required this.node,
    required this.children,
  });
  final CatalogNodeModel node;
  final List<CatalogNodeModel> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
          child: Text(
            'Browse ${node.name}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        if (children.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(
              'Loading…',
              style: TextStyle(color: AppColors.textHint, fontSize: 13),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            itemCount: children.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) => _ModalChildItem(
              node: children[i],
              parentNodeId: node.id,
              onTap: () => CatalogNodeModal.open(
                ctx,
                children[i],
                parentId: node.id,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Child list item ───────────────────────────────────────────────────────────

class _ModalChildItem extends StatefulWidget {
  const _ModalChildItem({
    required this.node,
    required this.onTap,
    this.parentNodeId,
  });
  final CatalogNodeModel node;
  final VoidCallback onTap;
  /// The node.id of the parent through which this item is being displayed.
  /// Drives path-scoped loyalty resolution for shared services.
  final String? parentNodeId;

  @override
  State<_ModalChildItem> createState() => _ModalChildItemState();
}

class _ModalChildItemState extends State<_ModalChildItem> {
  bool _pressed = false;
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
    final node = widget.node;
    final imageUrl = ServiceImageRegistry.resolve(node.imageUrl, node.name);

    return GestureDetector(
      onTap: _navigate,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(_pressed ? 8 : 14),
              blurRadius: _pressed ? 4 : 10,
              offset: Offset(0, _pressed ? 1 : 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Thumbnail
              SizedBox(
                width: 82,
                height: 82,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, p) =>
                      p == null
                          ? child
                          : const ColoredBox(color: Color(0xFFEEEEEE)),
                  errorBuilder: (_, _, _) => Container(
                    color: AppColors.goldLight,
                    alignment: Alignment.center,
                    child: const Icon(Icons.home_repair_service_rounded,
                        size: 26, color: AppColors.gold),
                  ),
                ),
              ),
              // Info
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        node.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          height: 1.3,
                        ),
                      ),
                      if (node.description?.isNotEmpty == true) ...[
                        const SizedBox(height: 2),
                        Text(
                          node.description!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          if (node.isLeafBookable &&
                              node.basePrice != null) ...[
                            Text(
                              '₹${node.basePrice!.toInt()}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 3),
                            const Text(
                              'onwards',
                              style: TextStyle(
                                  fontSize: 10, color: AppColors.textHint),
                            ),
                          ] else if (node.hasChildren)
                            Text(
                              '${node.childrenCount} '
                              '${node.childrenCount == 1 ? 'option' : 'options'}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          if (node.estimatedDuration != null) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.schedule_rounded,
                                size: 11, color: AppColors.textHint),
                            const SizedBox(width: 2),
                            Text(
                              '${node.estimatedDuration} min',
                              style: const TextStyle(
                                  fontSize: 10, color: AppColors.textHint),
                            ),
                          ],
                        ],
                      ),

                      // Loyalty earn badge — uses catalog-scoped resolved config
                      // so parent-level loyalty rules are inherited correctly.
                      if (node.isLeafBookable && node.loyaltyEarnEnabled)
                        Consumer(
                          builder: (_, ref, _) {
                            final settings = ref
                                .watch(loyaltySettingsProvider)
                                .valueOrNull;
                            if (settings == null ||
                                !settings.isEnabled ||
                                !settings.earnEnabled) {
                              return const SizedBox.shrink();
                            }
                            final cfgAsync = ref.watch(
                              resolvedLoyaltyConfigProvider((
                                serviceId: node.id,
                                parentNodeId: widget.parentNodeId ?? node.parentId,
                              )),
                            );
                            if (!cfgAsync.hasValue) {
                              return const SizedBox.shrink();
                            }
                            final pts = computeLoyaltyPoints(
                              cfgAsync.valueOrNull,
                              settings,
                              node.basePrice ?? 0,
                            );
                            if (pts <= 0) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: _LoyaltyEarnBadge(points: pts),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
              // Arrow
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Loyalty earn badge ────────────────────────────────────────────────────────

class _LoyaltyEarnBadge extends StatelessWidget {
  final int points;
  const _LoyaltyEarnBadge({required this.points});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.gold.withAlpha(22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.gold.withAlpha(60), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.workspace_premium_rounded,
              size: 10, color: AppColors.gold),
          const SizedBox(width: 3),
          Text(
            'Earn $points Loyalty Points',
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: AppColors.gold,
              height: 1.2,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Coming Soon ───────────────────────────────────────────────────────────────

class _ModalComingSoon extends StatelessWidget {
  const _ModalComingSoon();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.goldLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.gold.withAlpha(60)),
        ),
        child: const Column(
          children: [
            Icon(Icons.schedule_rounded, size: 34, color: AppColors.gold),
            SizedBox(height: 10),
            Text(
              'Coming Soon',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'This service is not yet available for booking.\nCheck back soon.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sticky cart bar ───────────────────────────────────────────────────────────

class _ModalBookingBar extends ConsumerWidget {
  const _ModalBookingBar({
    required this.node,
    required this.displayPrice,
    required this.priceAdjustment,
    required this.addonsTotal,
    this.parentNodeId,
  });

  final CatalogNodeModel node;
  final double displayPrice;
  final double priceAdjustment;
  final double addonsTotal;
  final String? parentNodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartItems = ref.watch(cartProvider);
    final inCart = cartItems.any((item) => item.serviceId == node.id);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(
          top: BorderSide(color: AppColors.border, width: 0.8),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(12),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '₹${displayPrice.toInt()}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    height: 1.1,
                  ),
                ),
                Text(
                  (priceAdjustment > 0 || addonsTotal > 0)
                      ? 'incl. adjustments'
                      : 'onwards',
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textHint),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: inCart
                  ? FilledButton.icon(
                      onPressed: () => openCart(context),
                      icon: const Icon(Icons.shopping_cart_rounded, size: 16),
                      label: const Text(
                        'View Cart',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11)),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: () => ref
                          .read(cartProvider.notifier)
                          .addToCart(
                            node,
                            priceAdjustment: priceAdjustment + addonsTotal,
                            parentNodeId: parentNodeId,
                          ),
                      icon: const Icon(Icons.add_shopping_cart_rounded,
                          size: 16),
                      label: const Text(
                        'Add to Cart',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11)),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
