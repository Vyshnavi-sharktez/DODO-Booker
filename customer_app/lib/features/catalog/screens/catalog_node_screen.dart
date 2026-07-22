import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import '../../wishlist/widgets/heart_button.dart';
import '../../loyalty/providers/loyalty_providers.dart';
import '../../loyalty/utils/loyalty_utils.dart';
import '../../address/services/address_providers.dart';
import '../models/catalog_node_model.dart';
import '../providers/catalog_providers.dart';
import '../utils/catalog_launcher.dart';
import '../widgets/catalog_unavailability_widgets.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CatalogNodeScreen — generic screen for any catalog node at any depth.
//
// Behaviour matrix (data-driven, applies at every depth):
//   hasChildren  (any)                → navigation list; booking never shown
//   !hasChildren && isBookable        → full service-detail + sticky booking bar
//   !hasChildren && !isBookable       → informational / Coming Soon state
// ═══════════════════════════════════════════════════════════════════════════════

class CatalogNodeScreen extends ConsumerStatefulWidget {
  const CatalogNodeScreen({
    super.key,
    required this.node,
    this.parentNodeId,
  });

  final CatalogNodeModel node;

  /// The catalog_node.id of the parent through which this screen was reached.
  /// Null for deep-link entry points where the path is unknown.
  final String? parentNodeId;

  @override
  ConsumerState<CatalogNodeScreen> createState() => _CatalogNodeScreenState();
}

class _CatalogNodeScreenState extends ConsumerState<CatalogNodeScreen> {
  final Map<String, String> _selections = {};
  double _priceAdjustment = 0.0;
  final Set<String> _selectedAddonIds = {};

  CatalogNodeModel get node => widget.node;

  void _onOptionSelected(String attrId, String optId,
      List<ServiceAttributeModel> attrs) {
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
    final attrs =
        node.isLeafBookable
            ? (ref.watch(serviceAttributesProvider(node.id)).valueOrNull ?? [])
            : <ServiceAttributeModel>[];
    final addOns =
        node.isLeafBookable
            ? (ref.watch(allActiveAddonsProvider).valueOrNull ?? [])
            : <AddOnModel>[];
    final faqs =
        node.isLeafBookable
            ? (ref.watch(catalogNodeFaqsProvider(node.id)).valueOrNull ?? [])
            : <FaqModel>[];

    // Use the customer's default address coordinates for location restriction checks.
    final addresses =
        ref.watch(addressNotifierProvider).valueOrNull ?? [];
    final defaultAddress = addresses.where((a) => a.isDefault).firstOrNull ??
        (addresses.isNotEmpty ? addresses.first : null);

    // Availability check — uses canonical parent as fallback for deep-link entry
    final availAsync = ref.watch(nodeAvailabilityProvider((
      nodeId: node.id,
      parentId: widget.parentNodeId ?? node.parentId,
      lat: defaultAddress?.latitude,
      lng: defaultAddress?.longitude,
    )));
    final avail = availAsync.valueOrNull;
    final isUnavailable = avail?.status == 'unavailable';
    final isEffectivelyHidden = avail?.status == 'hidden';

    final addonsTotal =
        totalAddonsPrice(buildSelectedAddons(addOns, _selectedAddonIds));
    final displayPrice =
        (node.basePrice ?? 0.0) + _priceAdjustment + addonsTotal;
    final hasAdjustment = _priceAdjustment > 0 || addonsTotal > 0;

    // Category/navigation nodes always show a hero using the image registry
    // fallback so every browse page has a themed image.
    // Service-detail leaf nodes only show a hero when an explicit imageUrl
    // has been set in the admin panel.
    final heroUrl = node.hasChildren
        ? ServiceImageRegistry.resolve(node.imageUrl, node.name)
        : node.imageUrl;
    final hasHero = node.hasChildren || (heroUrl != null && heroUrl.isNotEmpty);

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: hasHero,
      appBar: hasHero
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              foregroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              actions: [
                if (node.isLeafBookable)
                  HeartButton(serviceId: node.id, mini: false),
                const SizedBox(width: 4),
              ],
            )
          : AppBar(
              title: Text(
                node.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: AppColors.textPrimary,
                ),
              ),
              backgroundColor: AppColors.background,
              foregroundColor: AppColors.textPrimary,
              elevation: 0,
              scrolledUnderElevation: 1,
              surfaceTintColor: Colors.transparent,
              actions: [
                if (node.isLeafBookable)
                  HeartButton(serviceId: node.id, mini: false),
                const SizedBox(width: 4),
              ],
            ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Hero image + floating info card (Stack, no SliverAppBar) ──
                if (hasHero) ...[
                  _HeroWithCard(
                    imageUrl: heroUrl!,
                    node: node,
                    displayPrice: displayPrice,
                    hasAdjustment: hasAdjustment,
                  ),
                  // Spacer: card extends 60 px below the Stack + 20 px gap.
                  const SizedBox(height: 80),
                ],

                // ── No-hero: breadcrumb + info header ──────────────────────
                if (!hasHero) ...[
                  if (!node.isRoot)
                    _Breadcrumb(
                      parentName: node.parentName ?? '',
                      nodeName: node.name,
                      onParentTap: () => context.pop(),
                    ),
                  _NodeInfoHeader(
                    node: node,
                    displayPrice: displayPrice,
                    hasAdjustment: hasAdjustment,
                  ),
                ],

                // ── Attribute selection ────────────────────────────────────
                if (node.isLeafBookable && attrs.isNotEmpty)
                  ServiceAttributeSection(
                    attrs: attrs,
                    selections: _selections,
                    onChanged: (attrId, optId) =>
                        _onOptionSelected(attrId, optId, attrs),
                  ),

                // ── Description ────────────────────────────────────────────
                if (node.description?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.isLeafBookable
                              ? 'About this service'
                              : node.name,
                          style: const TextStyle(
                            fontSize: 17,
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

                // ── Children list ──────────────────────────────────────────
                if (node.hasChildren)
                  (isUnavailable || isEffectivelyHidden)
                      ? CatalogUnavailabilityBanner(
                          message:
                              isUnavailable ? avail?.message : null,
                          isHidden: isEffectivelyHidden,
                        )
                      : _ChildrenSection(
                          node: node,
                          children: children,
                        ),

                // ── Add-ons ────────────────────────────────────────────────
                if (node.isLeafBookable && addOns.isNotEmpty)
                  ServiceAddonSection(
                    addOns: addOns,
                    selectedIds: _selectedAddonIds,
                    onToggle: _onAddonToggled,
                  ),

                // ── FAQs ───────────────────────────────────────────────────
                if (node.isLeafBookable && faqs.isNotEmpty)
                  FaqSection(faqs: faqs),

                // ── Reviews ────────────────────────────────────────────────
                if (node.isLeafBookable)
                  ServiceReviewsSection(serviceId: node.id),

                // ── Coming Soon ────────────────────────────────────────────
                if (!node.hasChildren && !node.isBookable)
                  const _ComingSoonBanner(),

                SizedBox(height: node.isLeafBookable ? 100 : 40),
              ],
            ),
          ),
        ],
      ),

      // ── Sticky cart bar / unavailability bar ────────────────────────────
      bottomNavigationBar: node.isLeafBookable
          ? (isUnavailable || isEffectivelyHidden)
              ? CatalogUnavailabilityBar(
                  message: isUnavailable ? avail?.message : null,
                )
              : _NodeBookingBar(
                  node: node,
                  displayPrice: displayPrice,
                  priceAdjustment: _priceAdjustment,
                  addonsTotal: addonsTotal,
                  parentNodeId: widget.parentNodeId,
                )
          : null,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Deep-link recovery
// ═══════════════════════════════════════════════════════════════════════════════

class CatalogNodeFetchScreen extends ConsumerWidget {
  const CatalogNodeFetchScreen({super.key, required this.nodeId});
  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(catalogNodeProvider(nodeId));
    return async.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Service not found.')),
      ),
      data: (node) {
        if (node == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Service not found.')),
          );
        }
        return CatalogNodeScreen(node: node);
      },
    );
  }
}

// ── Hero + floating card (Stack-based overlap) ────────────────────────────────

class _HeroWithCard extends StatelessWidget {
  const _HeroWithCard({
    required this.imageUrl,
    required this.node,
    required this.displayPrice,
    required this.hasAdjustment,
  });

  final String imageUrl;
  final CatalogNodeModel node;
  final double displayPrice;
  final bool hasAdjustment;

  @override
  Widget build(BuildContext context) {
    // Include status bar + AppBar height so the image fills behind the
    // transparent AppBar when extendBodyBehindAppBar is true.
    final topInset =
        MediaQuery.of(context).padding.top + kToolbarHeight;
    final heroHeight = topInset + 200.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          height: heroHeight,
          width: double.infinity,
          child: _HeroImage(url: imageUrl),
        ),
        // Card positioned so its bottom edge is 60 px below the Stack's
        // bottom, creating a 60 px visible overlap into the hero image.
        Positioned(
          bottom: -60,
          left: 16,
          right: 16,
          child: _FloatingInfoCard(
            node: node,
            displayPrice: displayPrice,
            hasAdjustment: hasAdjustment,
          ),
        ),
      ],
    );
  }
}

// ── Hero image ────────────────────────────────────────────────────────────────

class _HeroImage extends StatelessWidget {
  const _HeroImage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
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
              size: 48,
              color: AppColors.gold,
            ),
          ),
        ),
        // Bottom gradient for AppBar title readability when scrolled
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withAlpha(100),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Floating info card ────────────────────────────────────────────────────────

class _FloatingInfoCard extends StatelessWidget {
  const _FloatingInfoCard({
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
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(22),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Parent breadcrumb tag
            if (!node.isRoot && node.parentName != null) ...[
              Row(
                children: [
                  const Icon(Icons.chevron_left_rounded,
                      size: 14, color: AppColors.textHint),
                  const SizedBox(width: 2),
                  Text(
                    node.parentName!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],

            // Node name
            Text(
              node.name,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                height: 1.2,
              ),
            ),

            // Meta row: rating + duration
            if (node.rating > 0 || node.estimatedDuration != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (node.rating > 0) ...[
                    const Icon(Icons.star_rounded,
                        size: 14, color: AppColors.gold),
                    const SizedBox(width: 3),
                    Text(
                      node.rating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (node.reviewCount > 0) ...[
                      const SizedBox(width: 3),
                      Text(
                        '(${node.reviewCount})',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(width: 12),
                  ],
                  if (node.estimatedDuration != null) ...[
                    const Icon(Icons.schedule_rounded,
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      '${node.estimatedDuration} min',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ],

            // Price (service detail) or child count (category)
            if (node.isLeafBookable && node.basePrice != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1, color: AppColors.divider),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '₹${displayPrice.toInt()}',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    hasAdjustment ? 'incl. adjustments' : 'onwards',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ] else if (node.hasChildren) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${node.childrenCount} ${node.childrenCount == 1 ? 'service' : 'services'} available',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Breadcrumb ────────────────────────────────────────────────────────────────

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({
    required this.parentName,
    required this.nodeName,
    required this.onParentTap,
  });
  final String parentName;
  final String nodeName;
  final VoidCallback onParentTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: onParentTap,
            child: Text(
              parentName,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.chevron_right_rounded,
                size: 14, color: AppColors.textHint),
          ),
          Expanded(
            child: Text(
              nodeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Node info header (no-image fallback) ──────────────────────────────────────

class _NodeInfoHeader extends StatelessWidget {
  const _NodeInfoHeader({
    required this.node,
    required this.displayPrice,
    required this.hasAdjustment,
  });
  final CatalogNodeModel node;
  final double displayPrice;
  final bool hasAdjustment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            node.name,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (node.rating > 0) ...[
                const Icon(Icons.star_rounded,
                    size: 15, color: AppColors.gold),
                const SizedBox(width: 3),
                Text(
                  node.rating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (node.reviewCount > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '(${node.reviewCount})',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(width: 12),
              ],
              if (node.estimatedDuration != null) ...[
                const Icon(Icons.schedule_rounded,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '${node.estimatedDuration} min',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          if (node.isLeafBookable && node.basePrice != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '₹${displayPrice.toInt()}',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  hasAdjustment ? 'incl. adjustments' : 'onwards',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Children list section ─────────────────────────────────────────────────────

class _ChildrenSection extends StatelessWidget {
  const _ChildrenSection({
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
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 4),
          child: Text(
            node.isRoot ? 'All Services' : 'Browse ${node.name}',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),

        if (children.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
            itemBuilder: (ctx, i) => _ChildListItem(
              node: children[i],
              parentNodeId: node.id,
              onTap: () => openCatalogNode(ctx, children[i], parentId: node.id),
            ),
          ),

        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Child list item (vertical card) ──────────────────────────────────────────

class _ChildListItem extends StatefulWidget {
  const _ChildListItem({
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
  State<_ChildListItem> createState() => _ChildListItemState();
}

class _ChildListItemState extends State<_ChildListItem> {
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
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(_pressed ? 8 : 14),
              blurRadius: _pressed ? 4 : 12,
              spreadRadius: 0,
              offset: Offset(0, _pressed ? 1 : 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Thumbnail
              SizedBox(
                width: 90,
                height: 90,
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
                    child: const Icon(
                      Icons.home_repair_service_rounded,
                      size: 28,
                      color: AppColors.gold,
                    ),
                  ),
                ),
              ),

              // Info
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                      if (node.relAvailabilityStatus == 'unavailable') ...[
                        const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.pause_circle_outline_rounded,
                                size: 11, color: Color(0xFFF59E0B)),
                            SizedBox(width: 3),
                            Text(
                              'Temporarily unavailable',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFF59E0B),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (node.description?.isNotEmpty == true) ...[
                        const SizedBox(height: 3),
                        Text(
                          node.description!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      // Bottom row: price/options + duration
                      Row(
                        children: [
                          if (node.isLeafBookable && node.basePrice != null) ...[
                            Text(
                              '₹${node.basePrice!.toInt()}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'onwards',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textHint,
                              ),
                            ),
                          ] else if (node.hasChildren)
                            Text(
                              '${node.childrenCount} ${node.childrenCount == 1 ? 'option' : 'options'}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          if (node.estimatedDuration != null) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.schedule_rounded,
                                size: 12, color: AppColors.textHint),
                            const SizedBox(width: 2),
                            Text(
                              '${node.estimatedDuration} min',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textHint,
                              ),
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
                              padding: const EdgeInsets.only(top: 5),
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
                padding: const EdgeInsets.only(right: 14),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
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

// ── Coming Soon banner ────────────────────────────────────────────────────────

class _ComingSoonBanner extends StatelessWidget {
  const _ComingSoonBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.goldLight,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.gold.withAlpha(60)),
        ),
        child: Column(
          children: [
            const Icon(Icons.schedule_rounded, size: 36, color: AppColors.gold),
            const SizedBox(height: 12),
            const Text(
              'Coming Soon',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'This service is not yet available for booking.\nCheck back soon.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sticky cart bar ───────────────────────────────────────────────────────────

class _NodeBookingBar extends ConsumerWidget {
  const _NodeBookingBar({
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
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        14 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(
          top: BorderSide(color: AppColors.border, width: 0.8),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(16),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '₹${displayPrice.toInt()}',
                style: const TextStyle(
                  fontSize: 22,
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
                    fontSize: 11, color: AppColors.textHint),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: inCart
                ? FilledButton.icon(
                    onPressed: () => openCart(context),
                    icon: const Icon(Icons.shopping_cart_rounded, size: 18),
                    label: const Text(
                      'View Cart',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  )
                : FilledButton.icon(
                    onPressed: () => ref
                        .read(cartProvider.notifier)
                        .addToCart(node,
                            priceAdjustment: priceAdjustment + addonsTotal,
                            parentNodeId: parentNodeId),
                    icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                    label: const Text(
                      'Add to Cart',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
