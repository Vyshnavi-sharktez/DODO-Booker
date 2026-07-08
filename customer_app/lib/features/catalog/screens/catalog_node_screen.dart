import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/faq_model.dart';
import '../../../models/service_attribute_model.dart';
import '../../../models/addon_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/utils/auth_modal_gate.dart';
import '../../booking/utils/booking_gate.dart';
import '../../cart/providers/cart_provider.dart';
import '../../category/services/category_providers.dart';
import '../../reviews/widgets/service_reviews_section.dart';
import '../../service/widgets/faq_section.dart';
import '../../service/widgets/service_addon_section.dart';
import '../../service/widgets/service_attribute_section.dart';
import '../../wishlist/widgets/heart_button.dart';
import '../models/catalog_node_model.dart';
import '../providers/catalog_providers.dart';
import '../utils/catalog_launcher.dart';
import '../widgets/catalog_node_card.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CatalogNodeScreen — generic screen for any catalog node at any depth.
//
// Behaviour matrix:
//   hasChildren only  → child-node navigation grid
//   isBookable only   → full service-detail content + sticky booking bar
//   both              → children grid above service detail + sticky bar
//   neither           → informational node (name, description, image)
// ═══════════════════════════════════════════════════════════════════════════════

class CatalogNodeScreen extends ConsumerStatefulWidget {
  const CatalogNodeScreen({super.key, required this.node});

  final CatalogNodeModel node;

  @override
  ConsumerState<CatalogNodeScreen> createState() => _CatalogNodeScreenState();
}

class _CatalogNodeScreenState extends ConsumerState<CatalogNodeScreen> {
  // Attribute + add-on selection state (used when isBookable).
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

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final children =
        ref.watch(catalogNodeChildrenProvider(node.id)).valueOrNull ?? [];
    final attrs =
        node.isBookable
            ? (ref.watch(serviceAttributesProvider(node.id)).valueOrNull ?? [])
            : <ServiceAttributeModel>[];
    final addOns =
        node.isBookable
            ? (ref.watch(allActiveAddonsProvider).valueOrNull ?? [])
            : <AddOnModel>[];
    final faqs =
        node.isBookable
            ? (ref.watch(catalogNodeFaqsProvider(node.id)).valueOrNull ?? [])
            : <FaqModel>[];

    final addonsTotal =
        totalAddonsPrice(buildSelectedAddons(addOns, _selectedAddonIds));
    final displayPrice =
        (node.basePrice ?? 0.0) + _priceAdjustment + addonsTotal;

    final hasImage =
        node.imageUrl != null && node.imageUrl!.isNotEmpty;
    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: hasImage
          ? null
          : AppBar(
              title: Text(
                node.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              backgroundColor: AppColors.background,
              foregroundColor: AppColors.textPrimary,
              elevation: 0,
              scrolledUnderElevation: 1,
              surfaceTintColor: Colors.transparent,
              actions: [
                if (node.isBookable)
                  HeartButton(serviceId: node.id, mini: false),
                const SizedBox(width: 4),
              ],
            ),
      body: CustomScrollView(
        slivers: [
          // ── Hero image (if present) ──────────────────────────────────────
          if (hasImage)
            SliverAppBar(
              expandedHeight: 260,
              pinned: true,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              actions: [
                if (node.isBookable)
                  HeartButton(serviceId: node.id, mini: false),
                const SizedBox(width: 4),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: _HeroImage(url: node.imageUrl!),
              ),
            ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Breadcrumb ─────────────────────────────────────────────
                if (!node.isRoot)
                  _Breadcrumb(
                    parentName: node.parentName ?? '',
                    nodeName: node.name,
                    onParentTap: () => context.pop(),
                  ),

                // ── Info header ────────────────────────────────────────────
                _NodeInfoHeader(
                  node: node,
                  displayPrice: displayPrice,
                  hasAdjustment: _priceAdjustment > 0 || addonsTotal > 0,
                ),

                // ── Attribute selection ────────────────────────────────────
                if (node.isBookable && attrs.isNotEmpty)
                  ServiceAttributeSection(
                    attrs: attrs,
                    selections: _selections,
                    onChanged: (attrId, optId) =>
                        _onOptionSelected(attrId, optId, attrs),
                  ),

                // ── Description ────────────────────────────────────────────
                if (node.description?.isNotEmpty == true)
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.isBookable
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
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),

                // ── Children grid ──────────────────────────────────────────
                if (node.hasChildren)
                  _ChildrenSection(
                    node: node,
                    children: children,
                    screenWidth: width,
                  ),

                // ── Add-ons ────────────────────────────────────────────────
                if (node.isBookable && addOns.isNotEmpty)
                  ServiceAddonSection(
                    addOns: addOns,
                    selectedIds: _selectedAddonIds,
                    onToggle: _onAddonToggled,
                  ),

                // ── FAQs ───────────────────────────────────────────────────
                if (node.isBookable && faqs.isNotEmpty)
                  FaqSection(faqs: faqs),

                // ── Reviews ────────────────────────────────────────────────
                if (node.isBookable)
                  ServiceReviewsSection(serviceId: node.id),

                SizedBox(height: node.isBookable ? 100 : 32),
              ],
            ),
          ),
        ],
      ),

      // ── Sticky booking bar ───────────────────────────────────────────────
      bottomNavigationBar: node.isBookable
          ? _NodeBookingBar(
              node: node,
              attrs: attrs,
              selections: _selections,
              addOns: addOns,
              selectedAddonIds: _selectedAddonIds,
              displayPrice: displayPrice,
              priceAdjustment: _priceAdjustment,
              addonsTotal: addonsTotal,
            )
          : null,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Deep-link recovery: node was opened without an 'extra' payload
// (e.g. notification deep-link or browser refresh).
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

// ── Hero image ────────────────────────────────────────────────────────────────

class _HeroImage extends StatelessWidget {
  const _HeroImage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
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
          size: 48,
          color: AppColors.gold,
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

// ── Node info header ──────────────────────────────────────────────────────────

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
              fontSize: 22,
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
          if (node.isBookable && node.basePrice != null) ...[
            const SizedBox(height: 10),
            Text(
              '₹${displayPrice.toInt()}',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
                height: 1.1,
              ),
            ),
            Text(
              hasAdjustment ? 'incl. adjustments' : 'onwards',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textHint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Children grid section ─────────────────────────────────────────────────────

class _ChildrenSection extends StatelessWidget {
  const _ChildrenSection({
    required this.node,
    required this.children,
    required this.screenWidth,
  });
  final CatalogNodeModel node;
  final List<CatalogNodeModel> children;
  final double screenWidth;

  int get _cols {
    if (screenWidth < 480) return 2;
    if (screenWidth < 768) return 3;
    if (screenWidth < 1100) return 4;
    return 5;
  }

  @override
  Widget build(BuildContext context) {
    final cols = _cols;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 24, 20, 14),
          child: Text(
            'Browse',
            style: TextStyle(
              fontSize: 17,
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
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                childAspectRatio: 0.75,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: children.length,
              itemBuilder: (ctx, i) => CatalogNodeCard(
                node: children[i],
                colorIndex: i,
                onTap: () => openCatalogNode(ctx, children[i]),
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Sticky booking bar ────────────────────────────────────────────────────────

class _NodeBookingBar extends ConsumerWidget {
  const _NodeBookingBar({
    required this.node,
    required this.attrs,
    required this.selections,
    required this.addOns,
    required this.selectedAddonIds,
    required this.displayPrice,
    required this.priceAdjustment,
    required this.addonsTotal,
  });

  final CatalogNodeModel node;
  final List<ServiceAttributeModel> attrs;
  final Map<String, String> selections;
  final List<AddOnModel> addOns;
  final Set<String> selectedAddonIds;
  final double displayPrice;
  final double priceAdjustment;
  final double addonsTotal;

  bool get _requiredFilled => attrs
      .where((a) => a.isRequired && a.hasOptions)
      .every((a) => selections.containsKey(a.id));

  bool get _hasRequiredAttrs =>
      attrs.any((a) => a.isRequired && a.hasOptions);

  Future<void> _addToCart(BuildContext context, WidgetRef ref) async {
    if (!ref.read(isAuthenticatedProvider)) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Text('Login Required'),
          content:
              const Text('Please log in to add items to your cart.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Login'),
            ),
          ],
        ),
      );
      if (!context.mounted || proceed != true) return;
      final authed = await requireAuth(context, ref);
      if (!context.mounted || !authed) return;
    }

    ref
        .read(cartProvider.notifier)
        .addToCart(node, priceAdjustment: priceAdjustment + addonsTotal);

    if (!context.mounted) return;
    try {
      final currentPath = GoRouterState.of(context).uri.path;
      if (currentPath == '/cart') return;
    } catch (_) {}

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
        content: Text('Added to cart'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _book(BuildContext context, WidgetRef ref) async {
    final selectedAttrs = buildSelectedAttributes(attrs, selections);
    final selectedAddons = buildSelectedAddons(addOns, selectedAddonIds);
    await launchBookingFlow(context, ref, node,
        selectedAttributes: selectedAttrs,
        selectedAddons: selectedAddons);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canBook = !_hasRequiredAttrs || _requiredFilled;

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(18),
            blurRadius: 12,
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
          OutlinedButton.icon(
            onPressed: () => _addToCart(context, ref),
            icon: const Icon(Icons.shopping_cart_outlined, size: 16),
            label: const Text('Add'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: canBook ? () => _book(context, ref) : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(
                canBook ? 'Book Now' : 'Select options',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
