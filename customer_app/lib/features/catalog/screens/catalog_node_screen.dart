import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/service_image_registry.dart';
import '../../../core/widgets/horizontal_carousel.dart';
import '../../../models/faq_model.dart';
import '../../../models/service_attribute_model.dart';
import '../../../models/addon_model.dart';
import '../../cart/providers/cart_provider.dart';
import '../../cart/utils/cart_launcher.dart';
import '../../category/services/category_providers.dart';
import '../../reviews/widgets/service_reviews_section.dart';
import '../../service/widgets/faq_section.dart';
import '../../service/widgets/service_attribute_section.dart';
import '../../wishlist/widgets/heart_button.dart';
import '../../loyalty/providers/loyalty_providers.dart';
import '../../loyalty/utils/loyalty_utils.dart';
import '../../address/services/address_providers.dart';
import '../../amc/providers/amc_provider.dart';
import '../models/catalog_node_model.dart';
import '../providers/catalog_providers.dart';
import '../utils/catalog_launcher.dart';
import '../widgets/catalog_node_modal.dart';
import '../widgets/catalog_unavailability_widgets.dart';
import 'category_explorer_screen.dart';

// ── Design tokens (from handoff) ──────────────────────────────────────────────
const _kInk = Color(0xFF1A1714);
const _kMuted = Color(0xFF6E6A64);
const _kMuted2 = Color(0xFF9A948C);
const _kGold = Color(0xFFF4A81D);
const _kBorder = Color(0xFFECE7DE);
const _kBg = Color(0xFFFBF8F3);
const _kAmcPopularBg = Color(0xFFFDF2D9);

// ── Striped placeholder painter (for image areas with no real photo) ──────────
class _StripedBox extends StatelessWidget {
  const _StripedBox({this.width, this.height});
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEAE3D4), Color(0xFFE1DAC9)],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CatalogNodeScreen
// ═══════════════════════════════════════════════════════════════════════════════

class CatalogNodeScreen extends ConsumerStatefulWidget {
  const CatalogNodeScreen({super.key, required this.node, this.parentNodeId});

  final CatalogNodeModel node;
  final String? parentNodeId;

  @override
  ConsumerState<CatalogNodeScreen> createState() => _CatalogNodeScreenState();
}

class _CatalogNodeScreenState extends ConsumerState<CatalogNodeScreen> {
  final Map<String, String> _selections = {};
  double _priceAdjustment = 0.0;
  final Set<String> _selectedAddonIds = {};
  AmcPlanModel? _selectedAmcPlan;

  CatalogNodeModel get node => widget.node;

  void _onOptionSelected(
    String attrId,
    String optId,
    List<ServiceAttributeModel> attrs,
  ) {
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
    final width = MediaQuery.sizeOf(context).width;
    final isWeb = width >= 768;

    final children =
        ref.watch(catalogNodeChildrenProvider(node.id)).valueOrNull ?? [];
    final attrs = node.isLeafBookable
        ? (ref.watch(serviceAttributesProvider(node.id)).valueOrNull ?? [])
        : <ServiceAttributeModel>[];
    final addOns = node.isLeafBookable
        ? (ref.watch(allActiveAddonsProvider).valueOrNull ?? [])
        : <AddOnModel>[];
    final faqs = node.isLeafBookable
        ? (ref
                .watch(catalogNodeFaqsProvider(
                    (nodeId: node.id, parentNodeId: widget.parentNodeId)))
                .valueOrNull ??
            [])
        : <FaqModel>[];

    final addresses = ref.watch(addressNotifierProvider).valueOrNull ?? [];
    final defaultAddress =
        addresses.where((a) => a.isDefault).firstOrNull ??
        (addresses.isNotEmpty ? addresses.first : null);

    final availAsync = ref.watch(
      nodeAvailabilityProvider((
        nodeId: node.id,
        parentId: widget.parentNodeId ?? node.parentId,
        lat: defaultAddress?.latitude,
        lng: defaultAddress?.longitude,
      )),
    );
    final avail = availAsync.valueOrNull;
    final isUnavailable = avail?.status == 'unavailable';
    final isEffectivelyHidden = avail?.status == 'hidden';

    final addonsTotal = totalAddonsPrice(
      buildSelectedAddons(addOns, _selectedAddonIds),
    );
    final displayPrice = _selectedAmcPlan != null
        ? _selectedAmcPlan!.finalPrice
        : (node.basePrice ?? 0.0) + _priceAdjustment + addonsTotal;
    final hasAdjustment = _priceAdjustment > 0 || addonsTotal > 0;

    final heroUrl = node.hasChildren
        ? ServiceImageRegistry.resolve(node.imageUrl, node.name)
        : node.imageUrl;
    final hasHero = node.hasChildren || (heroUrl != null && heroUrl.isNotEmpty);

    // ── Web ──────────────────────────────────────────────────────────────────
    if (isWeb) {
      return _WebScaffold(
        node: node,
        heroUrl: heroUrl,
        hasHero: hasHero,
        children: children,
        attrs: attrs,
        addOns: addOns,
        faqs: faqs,
        displayPrice: displayPrice,
        hasAdjustment: hasAdjustment,
        isUnavailable: isUnavailable,
        isEffectivelyHidden: isEffectivelyHidden,
        avail: avail,
        priceAdjustment: _priceAdjustment,
        addonsTotal: addonsTotal,
        parentNodeId: widget.parentNodeId,
        selections: _selections,
        selectedAddonIds: _selectedAddonIds,
        selectedAmcPlan: _selectedAmcPlan,
        onOptionSelected: _onOptionSelected,
        onAddonToggled: _onAddonToggled,
        onAmcPlanSelected: (plan) => setState(() => _selectedAmcPlan = plan),
      );
    }

    // ── Mobile ───────────────────────────────────────────────────────────────
    return Scaffold(
      backgroundColor: _kBg,
      extendBodyBehindAppBar: hasHero,
      appBar: hasHero
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              automaticallyImplyLeading: false,
            )
          : AppBar(
              title: Text(
                node.name,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 17, color: _kInk),
              ),
              backgroundColor: _kBg,
              foregroundColor: _kInk,
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
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Hero photo ─────────────────────────────────────────────
                if (hasHero)
                  _MobileHero(
                    imageUrl: heroUrl!,
                    node: node,
                    showHeart: node.isLeafBookable,
                  ),

                // ── Service content header ─────────────────────────────────
                if (hasHero && node.isLeafBookable)
                  _ServiceContentBlock(
                    node: node,
                    displayPrice: displayPrice,
                    hasAdjustment: hasAdjustment,
                  ),

                // ── Category hero fallback ─────────────────────────────────
                if (hasHero && !node.isLeafBookable)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                    child: Text(
                      node.name,
                      style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: _kInk),
                    ),
                  ),

                // ── No-hero path ───────────────────────────────────────────
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

                // ── Children (category navigation) ─────────────────────────
                if (node.hasChildren)
                  (isUnavailable || isEffectivelyHidden)
                      ? CatalogUnavailabilityBanner(
                          message: isUnavailable ? avail?.message : null,
                          isHidden: isEffectivelyHidden,
                        )
                      : _ChildrenSection(node: node, children: children),

                // ── Suggested Add-ons ──────────────────────────────────────
                if (node.isLeafBookable && addOns.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                    child: _SectionHeaderRow(title: 'Suggested Add-ons'),
                  ),
                  _InlineAddonCards(
                    addOns: addOns,
                    selectedIds: _selectedAddonIds,
                    onToggle: _onAddonToggled,
                    isWeb: false,
                  ),
                ],

                // ── AMC Plans ──────────────────────────────────────────────
                if (node.isLeafBookable)
                  Consumer(
                    builder: (ctx, ref, _) {
                      final plans =
                          ref.watch(amcPlansProvider(node.id)).valueOrNull;
                      if (plans == null || plans.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                            child: _SectionHeaderRow(title: 'AMC Plans'),
                          ),
                          _InlineAmcPlans(
                            serviceId: node.id,
                            selectedPlan: _selectedAmcPlan,
                            onPlanSelected: (plan) =>
                                setState(() => _selectedAmcPlan = plan),
                            regularPrice: node.basePrice,
                            isWeb: false,
                          ),
                        ],
                      );
                    },
                  ),

                // ── What's Included ───────────────────────────────────────
                if (node.isLeafBookable && node.includedItems.isNotEmpty)
                  _IncludedSection(items: node.includedItems),

                // ── What's Excluded ───────────────────────────────────────
                if (node.isLeafBookable && node.excludedItems.isNotEmpty)
                  _ExcludedSection(items: node.excludedItems),

                // ── Before & After ────────────────────────────────────────
                if (node.isLeafBookable && node.beforeAfterPairs.isNotEmpty)
                  _BeforeAfterSection(pairs: node.beforeAfterPairs),

                // ── Customer Content blocks ───────────────────────────────
                if (node.isLeafBookable && node.contentBlocks.isNotEmpty)
                  _ContentBlocksSection(blocks: node.contentBlocks),

                // ── Accordion: About / FAQs / Reviews ─────────────────────
                if (node.isLeafBookable) ...[
                  const SizedBox(height: 24),
                  _AccordionSection(
                    label: 'About this service',
                    isFirst: true,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 14),
                      child: Text(
                        node.description?.isNotEmpty == true
                            ? node.description!
                            : 'No description available.',
                        style: const TextStyle(
                            fontSize: 13, color: _kMuted, height: 1.6),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Text('FAQs',
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _kInk)),
                  ),
                  if (faqs.isEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
                      child: Text('No FAQs yet.',
                          style: TextStyle(fontSize: 13, color: _kMuted)),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 20, top: 2),
                      child: AskQuestionLink(serviceId: node.id, parentId: widget.parentNodeId),
                    ),
                    const SizedBox(height: 8),
                  ] else ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: FaqSection(faqs: faqs),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 20, top: 6),
                      child: AskQuestionLink(serviceId: node.id, parentId: widget.parentNodeId),
                    ),
                    const SizedBox(height: 8),
                  ],
                  _AccordionSection(
                    label: node.reviewCount > 0
                        ? 'Reviews (${node.reviewCount})'
                        : 'Reviews',
                    isLast: true,
                    child: ServiceReviewsSection(serviceId: node.id, showHeader: false),
                  ),
                ],

                // ── Coming Soon ────────────────────────────────────────────
                if (!node.hasChildren && !node.isBookable)
                  const _ComingSoonBanner(),

                SizedBox(height: node.isLeafBookable ? 100 : 40),
              ],
            ),
          ),
        ],
      ),

      // ── Sticky booking bar ────────────────────────────────────────────────
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
                    attrs: attrs,
                    selections: _selections,
                    addOns: addOns,
                    selectedAddonIds: _selectedAddonIds,
                    amcPlan: _selectedAmcPlan,
                    amcQuantity: 1,
                  )
          : null,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Deep-link recovery
// ═══════════════════════════════════════════════════════════════════════════════

class CatalogNodeFetchScreen extends ConsumerStatefulWidget {
  const CatalogNodeFetchScreen({super.key, required this.nodeId});
  final String nodeId;

  @override
  ConsumerState<CatalogNodeFetchScreen> createState() =>
      _CatalogNodeFetchScreenState();
}

class _CatalogNodeFetchScreenState
    extends ConsumerState<CatalogNodeFetchScreen> {
  bool _modalOpened = false;
  CatalogNodeModel? _node;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(catalogNodeProvider(widget.nodeId));

    // Mobile: keep existing full-screen behavior unchanged.
    if (!kIsWeb) {
      return async.when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
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

    // Web: once node loads, show its category explorer as background and open
    // the catalog modal on top. AppNavigation is shown only during the brief load.
    if (!_modalOpened && async.hasValue && async.value != null) {
      _node = async.value;
      _modalOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) CatalogNodeModal.open(context, _node!);
      });
    }

    if (_node != null) {
      return CategoryExplorerScreen(initialNode: _node);
    }

    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Mobile hero: 260px photo + overlay buttons
// ═══════════════════════════════════════════════════════════════════════════════

class _MobileHero extends StatelessWidget {
  const _MobileHero({
    required this.imageUrl,
    required this.node,
    required this.showHeart,
  });

  final String imageUrl;
  final CatalogNodeModel node;
  final bool showHeart;

  @override
  Widget build(BuildContext context) {
    final statusBarH = MediaQuery.of(context).padding.top;
    final totalH = statusBarH + 260.0;

    return SizedBox(
      height: totalH,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _HeroImage(url: imageUrl),

          // Back
          Positioned(
            top: statusBarH + 16,
            left: 16,
            child: _CircleNavBtn(
              icon: Icons.arrow_back_rounded,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),

          // Heart
          if (showHeart)
            Positioned(
              top: statusBarH + 16,
              right: 16,
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
                child: Center(
                    child: HeartButton(serviceId: node.id, mini: true)),
              ),
            ),

          // Counter pill
          Positioned(
            bottom: 14,
            right: 16,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1714).withAlpha(166),
                borderRadius: BorderRadius.circular(100),
              ),
              child: const Text('1/6',
                  style: TextStyle(
                      color: Colors.white, fontSize: 11, height: 1.4)),
            ),
          ),

          // Dot indicators
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                    width: 16,
                    height: 4,
                    decoration: BoxDecoration(
                        color: _kGold,
                        borderRadius: BorderRadius.circular(100))),
                const SizedBox(width: 5),
                Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.white.withAlpha(180),
                        borderRadius: BorderRadius.circular(100))),
                const SizedBox(width: 5),
                Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.white.withAlpha(180),
                        borderRadius: BorderRadius.circular(100))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleNavBtn extends StatelessWidget {
  const _CircleNavBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
            color: Colors.white, shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: _kInk),
      ),
    ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Service content block (below hero on mobile)
// badge → title → rating → description → price row
// ═══════════════════════════════════════════════════════════════════════════════

class _ServiceContentBlock extends StatelessWidget {
  const _ServiceContentBlock({
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
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category badge
          if (node.parentName?.isNotEmpty == true) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: _kInk,
                  borderRadius: BorderRadius.circular(100)),
              child: Text(node.parentName!,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.3)),
            ),
            const SizedBox(height: 10),
          ],

          // Title
          Text(node.name,
              style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _kInk,
                  height: 1.2)),
          const SizedBox(height: 6),

          // Rating row
          if (node.rating > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Text('★',
                      style: TextStyle(color: _kGold, fontSize: 13)),
                  const SizedBox(width: 4),
                  Text(node.rating.toStringAsFixed(1),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _kInk)),
                  if (node.reviewCount > 0) ...[
                    const SizedBox(width: 4),
                    Text('(${node.reviewCount} reviews)',
                        style: const TextStyle(
                            fontSize: 13, color: _kMuted2)),
                  ],
                ],
              ),
            ),

          // Description
          if (node.description?.isNotEmpty == true) ...[
            Text(node.description!,
                style: const TextStyle(
                    fontSize: 13, color: _kMuted, height: 1.6)),
            const SizedBox(height: 14),
          ] else
            const SizedBox(height: 8),

          // Price row: "From ₹X"
          if (node.basePrice != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Text('From',
                    style: TextStyle(fontSize: 13, color: _kMuted2)),
                const SizedBox(width: 8),
                Text('₹${displayPrice.toInt()}',
                    style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _kInk,
                        height: 1.0)),
                if (hasAdjustment) ...[
                  const SizedBox(width: 8),
                  const Text('incl. add-ons',
                      style: TextStyle(fontSize: 12, color: _kMuted2)),
                ],
              ],
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Section header row
// ═══════════════════════════════════════════════════════════════════════════════

class _SectionHeaderRow extends StatelessWidget {
  const _SectionHeaderRow({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(title,
            style: GoogleFonts.poppins(
                fontSize: 15, fontWeight: FontWeight.w700, color: _kInk)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Inline add-on cards
// Mobile: horizontal scroll, 110px cards with image-top design
// Web: 4-column grid with thumbnail-left design
// ═══════════════════════════════════════════════════════════════════════════════

class _InlineAddonCards extends StatelessWidget {
  const _InlineAddonCards({
    required this.addOns,
    required this.selectedIds,
    required this.onToggle,
    required this.isWeb,
  });

  final List<AddOnModel> addOns;
  final Set<String> selectedIds;
  final void Function(String, bool) onToggle;
  final bool isWeb;

  @override
  Widget build(BuildContext context) {
    if (isWeb) {
      return Column(
        children: addOns
            .map((a) => _AddonWebRow(
                  addOn: a,
                  isSelected: selectedIds.contains(a.id),
                  onToggle: (sel) => onToggle(a.id, sel),
                ))
            .toList(),
      );
    }

    return HorizontalCarousel(
      height: 210,
      itemCount: addOns.length,
      scrollStep: 3 * (160.0 + 12.0),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemBuilder: (_, i) => Padding(
        padding: EdgeInsets.only(right: i < addOns.length - 1 ? 12 : 0),
        child: _AddonMobileCard(
          addOn: addOns[i],
          isSelected: selectedIds.contains(addOns[i].id),
          onToggle: (sel) => onToggle(addOns[i].id, sel),
        ),
      ),
    );
  }
}

// Mobile add-on card: 110px wide, image top
class _AddonMobileCard extends StatefulWidget {
  const _AddonMobileCard({
    required this.addOn,
    required this.isSelected,
    required this.onToggle,
  });

  final AddOnModel addOn;
  final bool isSelected;
  final ValueChanged<bool> onToggle;

  @override
  State<_AddonMobileCard> createState() => _AddonMobileCardState();
}

class _AddonMobileCardState extends State<_AddonMobileCard> {
  @override
  Widget build(BuildContext context) {
    final sel = widget.isSelected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
      onTap: () => widget.onToggle(!sel),
      child: SizedBox(
        width: 160,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image area
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: sel
                    ? Border.all(color: _kGold, width: 1.5)
                    : Border.all(color: _kBorder, width: 0.8),
                color: sel
                    ? const Color(0xFFFDF2D9)
                    : const Color(0xFFEAE3D4),
                gradient: sel
                    ? null
                    : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFF1ECE1), Color(0xFFEAE3D4)],
                      ),
              ),
              child: sel
                  ? const Center(
                      child: Icon(Icons.check_rounded,
                          color: _kGold, size: 28))
                  : null,
            ),
            const SizedBox(height: 6),

            // Name
            Text(
              widget.addOn.name,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _kInk,
                  height: 1.3),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),

            // Price + toggle button
            Row(
              children: [
                Text(
                  '₹${widget.addOn.price.toInt()}',
                  style: const TextStyle(fontSize: 11, color: _kMuted),
                ),
                const Spacer(),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                  onTap: () => widget.onToggle(!sel),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: sel ? _kGold : const Color(0xFFECE7DE),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        sel ? Icons.check_rounded : Icons.add_rounded,
                        size: 12,
                        color: sel ? Colors.white : _kInk,
                      ),
                    ),
                  ),
                ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    );
  }
}

// Web add-on row: [thumbnail 44px | name+price | "+" button]
class _AddonWebRow extends StatelessWidget {
  const _AddonWebRow({
    required this.addOn,
    required this.isSelected,
    required this.onToggle,
  });

  final AddOnModel addOn;
  final bool isSelected;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          // Thumbnail
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF1ECE1), Color(0xFFEAE3D4)],
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Name + price
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(addOn.name,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _kInk),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text('₹${addOn.price.toInt()}',
                    style: const TextStyle(fontSize: 12, color: _kMuted)),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // "+" button
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
            onTap: () => onToggle(!isSelected),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isSelected ? _kGold : const Color(0xFFECE7DE),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  isSelected ? Icons.check_rounded : Icons.add_rounded,
                  size: 13,
                  color: isSelected ? Colors.white : _kInk,
                ),
              ),
            ),
          ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Inline AMC plan cards (replaces bottom-sheet trigger)
// ═══════════════════════════════════════════════════════════════════════════════

class _InlineAmcPlans extends ConsumerWidget {
  const _InlineAmcPlans({
    required this.serviceId,
    required this.selectedPlan,
    required this.onPlanSelected,
    this.regularPrice,
    required this.isWeb,
  });

  final String serviceId;
  final AmcPlanModel? selectedPlan;
  final void Function(AmcPlanModel?) onPlanSelected;
  final double? regularPrice;
  final bool isWeb;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amcAsync = ref.watch(amcPlansProvider(serviceId));

    return amcAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (plans) {
        if (plans.isEmpty) return const SizedBox.shrink();

        final padding = isWeb
            ? const EdgeInsets.symmetric(horizontal: 0)
            : const EdgeInsets.symmetric(horizontal: 20);

        return Padding(
          padding: padding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: plans
                .take(2)
                .map((plan) {
                  final isSelected = selectedPlan?.id == plan.id;
                  final isFirst = plans.indexOf(plan) == 0;
                  return [
                    Expanded(
                      child: _AmcPlanCard(
                        plan: plan,
                        isSelected: isSelected,
                        isPopular: isFirst,
                        onTap: () =>
                            onPlanSelected(isSelected ? null : plan),
                      ),
                    ),
                    if (plan != plans.take(2).last)
                      const SizedBox(width: 12),
                  ];
                })
                .expand((w) => w)
                .toList(),
          ),
        );
      },
    );
  }
}

class _AmcPlanCard extends StatelessWidget {
  const _AmcPlanCard({
    required this.plan,
    required this.isSelected,
    required this.isPopular,
    required this.onTap,
  });

  final AmcPlanModel plan;
  final bool isSelected;
  final bool isPopular;
  final VoidCallback onTap;

  List<String> get _features {
    final f = <String>[
      '✓ ${plan.numVisits} ${plan.numVisits == 1 ? 'Visit' : 'Visits'} / ${plan.packageDurationLabel}',
      '✓ ${plan.serviceIntervalLabel} schedule',
    ];
    if (plan.discountValue > 0) {
      if (plan.discountType == 'percentage') {
        f.add('✓ ${plan.discountValue.toInt()}% off on repairs');
      } else {
        f.add('✓ ₹${plan.discountValue.toInt()} discount');
      }
    }
    return f;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isSelected ? _kAmcPopularBg : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: isSelected
                  ? Border.all(color: _kGold, width: 1.5)
                  : Border.all(color: _kBorder, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Space for "Popular" badge
                if (isPopular) const SizedBox(height: 4),

                // Title + selection indicator
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(plan.planName,
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _kInk)),
                    ),
                    const SizedBox(width: 8),
                    isSelected
                        ? Container(
                            width: 18,
                            height: 18,
                            decoration: const BoxDecoration(
                                color: _kInk, shape: BoxShape.circle),
                            child: const Icon(Icons.check_rounded,
                                size: 10, color: Colors.white),
                          )
                        : Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: _kBorder, width: 1.5),
                            ),
                          ),
                  ],
                ),

                // Features
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _features
                        .map((f) => Text(f,
                            style: const TextStyle(
                                fontSize: 11,
                                color: _kMuted,
                                height: 1.7)))
                        .toList(),
                  ),
                ),

                // Price
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '₹${plan.finalPrice.toInt()}',
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _kInk),
                      ),
                      TextSpan(
                        text: ' / ${plan.packageDurationLabel}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: _kMuted2,
                            fontWeight: FontWeight.w400),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // "Popular" badge
          if (isPopular)
            Positioned(
              top: -9,
              left: 14,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: _kGold,
                    borderRadius: BorderRadius.circular(100)),
                child: const Text('Popular',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: _kInk)),
              ),
            ),
        ],
      ),
    ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Accordion section
// ═══════════════════════════════════════════════════════════════════════════════

class _AccordionSection extends StatefulWidget {
  const _AccordionSection({
    required this.label,
    required this.child,
    this.isFirst = false,
    this.isLast = false,
  });

  final String label;
  final Widget child;
  final bool isFirst;
  final bool isLast;

  @override
  State<_AccordionSection> createState() => _AccordionSectionState();
}

class _AccordionSectionState extends State<_AccordionSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
            onTap: () => setState(() => _open = !_open),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                border: Border(
                  top: const BorderSide(color: _kBorder, width: 1),
                  bottom: widget.isLast && !_open
                      ? const BorderSide(color: _kBorder, width: 1)
                      : BorderSide.none,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.label,
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _kInk)),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    child: const Text('⌄',
                        style: TextStyle(
                            fontSize: 18, color: _kMuted2, height: 1)),
                  ),
                ],
              ),
            ),
          ),
          ),
          AnimatedCrossFade(
            alignment: Alignment.topLeft,
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              decoration: widget.isLast
                  ? const BoxDecoration(
                      border: Border(
                          bottom: BorderSide(color: _kBorder, width: 1)))
                  : null,
              child: widget.child,
            ),
            crossFadeState:
                _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Hero image
// ═══════════════════════════════════════════════════════════════════════════════

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
          loadingBuilder: (_, child, p) =>
              p == null ? child : const ColoredBox(color: Color(0xFFEAE3D4)),
          errorBuilder: (_, _, _) => const _StripedBox(),
        ),
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
                colors: [Colors.transparent, Colors.black.withAlpha(80)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Breadcrumb (no-hero path)
// ═══════════════════════════════════════════════════════════════════════════════

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
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
            onTap: onParentTap,
            child: Text(parentName,
                style: const TextStyle(
                    fontSize: 12,
                    color: _kMuted2,
                    fontWeight: FontWeight.w500)),
          ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.chevron_right_rounded, size: 14, color: _kMuted2),
          ),
          Expanded(
            child: Text(nodeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12,
                    color: _kInk,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Node info header (no-hero path)
// ═══════════════════════════════════════════════════════════════════════════════

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
          if (node.parentName?.isNotEmpty == true) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: _kInk,
                  borderRadius: BorderRadius.circular(100)),
              child: Text(node.parentName!,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 10),
          ],
          Text(node.name,
              style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: _kInk,
                  height: 1.2)),
          const SizedBox(height: 8),
          if (node.rating > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  const Text('★',
                      style: TextStyle(color: _kGold, fontSize: 13)),
                  const SizedBox(width: 4),
                  Text(node.rating.toStringAsFixed(1),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _kInk)),
                  if (node.reviewCount > 0) ...[
                    const SizedBox(width: 4),
                    Text('(${node.reviewCount})',
                        style: const TextStyle(
                            fontSize: 12, color: _kMuted2)),
                  ],
                ],
              ),
            ),
          if (node.isLeafBookable && node.basePrice != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Text('From',
                    style: TextStyle(fontSize: 13, color: _kMuted2)),
                const SizedBox(width: 8),
                Text('₹${displayPrice.toInt()}',
                    style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _kInk,
                        height: 1.0)),
                if (hasAdjustment) ...[
                  const SizedBox(width: 8),
                  const Text('incl. add-ons',
                      style: TextStyle(fontSize: 12, color: _kMuted2)),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Children section (category navigation)
// ═══════════════════════════════════════════════════════════════════════════════

class _ChildrenSection extends StatelessWidget {
  const _ChildrenSection({required this.node, required this.children});
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
            style: GoogleFonts.poppins(
                fontSize: 17, fontWeight: FontWeight.w700, color: _kInk),
          ),
        ),
        if (children.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Text('Loading…',
                style: TextStyle(color: _kMuted2, fontSize: 13)),
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
              onTap: () =>
                  openCatalogNode(ctx, children[i], parentId: node.id),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Child list item ───────────────────────────────────────────────────────────

class _ChildListItem extends StatefulWidget {
  const _ChildListItem({
    required this.node,
    required this.onTap,
    this.parentNodeId,
  });
  final CatalogNodeModel node;
  final VoidCallback onTap;
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

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
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
          border: Border.all(color: _kBorder, width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(_pressed ? 8 : 14),
              blurRadius: _pressed ? 4 : 12,
              offset: Offset(0, _pressed ? 1 : 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Row(
            children: [
              SizedBox(
                width: 90,
                height: 90,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, p) => p == null
                      ? child
                      : const ColoredBox(color: Color(0xFFEEEEEE)),
                  errorBuilder: (_, _, _) => Container(
                    color: AppColors.goldLight,
                    alignment: Alignment.center,
                    child: const Icon(Icons.home_repair_service_rounded,
                        size: 28, color: AppColors.gold),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(node.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _kInk,
                              height: 1.3)),
                      if (node.relAvailabilityStatus == 'unavailable') ...[
                        const SizedBox(height: 3),
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.pause_circle_outline_rounded,
                                size: 11, color: Color(0xFFF59E0B)),
                            SizedBox(width: 3),
                            Text('Temporarily unavailable',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFF59E0B))),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (node.isLeafBookable &&
                              node.basePrice != null) ...[
                            Text('₹${node.basePrice!.toInt()}',
                                style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: _kInk)),
                            const SizedBox(width: 4),
                            const Text('onwards',
                                style: TextStyle(
                                    fontSize: 11, color: _kMuted2)),
                          ] else if (node.hasChildren)
                            Text(
                              '${node.childrenCount} ${node.childrenCount == 1 ? 'option' : 'options'}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: _kMuted),
                            ),
                          if (node.estimatedDuration != null) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.schedule_rounded,
                                size: 12, color: _kMuted2),
                            const SizedBox(width: 2),
                            Text('${node.estimatedDuration} min',
                                style: const TextStyle(
                                    fontSize: 11, color: _kMuted2)),
                          ],
                        ],
                      ),
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
                                parentNodeId:
                                    widget.parentNodeId ?? node.parentId,
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
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.chevron_right_rounded,
                      size: 20, color: _kMuted),
                ),
              ),
            ],
          ),
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
          Text('Earn $points Loyalty Points',
              style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: AppColors.gold,
                  height: 1.2,
                  letterSpacing: 0.1)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Coming Soon
// ═══════════════════════════════════════════════════════════════════════════════

class _ComingSoonBanner extends StatelessWidget {
  const _ComingSoonBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 8),
      child: Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.goldLight,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.gold.withAlpha(60)),
        ),
        child: const Column(
          children: [
            Icon(Icons.schedule_rounded, size: 36, color: AppColors.gold),
            SizedBox(height: 12),
            Text('Coming Soon',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _kInk)),
            SizedBox(height: 6),
            Text(
              'This service is not yet available for booking.\nCheck back soon.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 13, color: _kMuted, height: 1.55),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Sticky booking bar — gold pill CTA
// ═══════════════════════════════════════════════════════════════════════════════

class _NodeBookingBar extends ConsumerWidget {
  const _NodeBookingBar({
    required this.node,
    required this.displayPrice,
    required this.priceAdjustment,
    required this.addonsTotal,
    this.parentNodeId,
    required this.attrs,
    required this.selections,
    required this.addOns,
    required this.selectedAddonIds,
    this.amcPlan,
    this.amcQuantity = 1,
  });

  final CatalogNodeModel node;
  final double displayPrice;
  final double priceAdjustment;
  final double addonsTotal;
  final String? parentNodeId;
  final List<ServiceAttributeModel> attrs;
  final Map<String, String> selections;
  final List<AddOnModel> addOns;
  final Set<String> selectedAddonIds;
  final AmcPlanModel? amcPlan;
  final int amcQuantity;

  void _addToCart(WidgetRef ref) {
    ref.read(cartProvider.notifier).addToCart(
          node,
          priceAdjustment:
              amcPlan != null ? 0.0 : priceAdjustment + addonsTotal,
          parentNodeId: parentNodeId,
          amcPlan: amcPlan,
          amcQuantity: amcQuantity,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inCart =
        ref.watch(cartProvider).any((i) => i.serviceId == node.id);

    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, 14 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _kBorder, width: 1)),
      ),
      child: Row(
        children: [
          // Price
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('From',
                  style: TextStyle(fontSize: 10, color: _kMuted2)),
              Text('₹${displayPrice.toInt()}',
                  style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: _kInk,
                      height: 1.1)),
            ],
          ),
          const SizedBox(width: 12),

          // Gold pill CTA
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
              onTap: inCart ? () => openCart(context) : () => _addToCart(ref),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                    color: _kInk,
                    borderRadius: BorderRadius.circular(100)),
                child: Center(
                  child: Text(
                    inCart
                        ? '🛒  View Cart'
                        : '🛒  ${amcPlan != null ? 'Book Now' : 'Add to Cart'}',
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Web scaffold — modal card layout
// ═══════════════════════════════════════════════════════════════════════════════

class _WebScaffold extends ConsumerWidget {
  const _WebScaffold({
    required this.node,
    required this.heroUrl,
    required this.hasHero,
    required this.children,
    required this.attrs,
    required this.addOns,
    required this.faqs,
    required this.displayPrice,
    required this.hasAdjustment,
    required this.isUnavailable,
    required this.isEffectivelyHidden,
    required this.avail,
    required this.priceAdjustment,
    required this.addonsTotal,
    required this.parentNodeId,
    required this.selections,
    required this.selectedAddonIds,
    required this.selectedAmcPlan,
    required this.onOptionSelected,
    required this.onAddonToggled,
    required this.onAmcPlanSelected,
  });

  final CatalogNodeModel node;
  final String? heroUrl;
  final bool hasHero;
  final List<CatalogNodeModel> children;
  final List<ServiceAttributeModel> attrs;
  final List<AddOnModel> addOns;
  final List<FaqModel> faqs;
  final double displayPrice;
  final bool hasAdjustment;
  final bool isUnavailable;
  final bool isEffectivelyHidden;
  final dynamic avail;
  final double priceAdjustment;
  final double addonsTotal;
  final String? parentNodeId;
  final Map<String, String> selections;
  final Set<String> selectedAddonIds;
  final AmcPlanModel? selectedAmcPlan;
  final void Function(String, String, List<ServiceAttributeModel>)
      onOptionSelected;
  final void Function(String, bool) onAddonToggled;
  final void Function(AmcPlanModel?) onAmcPlanSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inCart =
        ref.watch(cartProvider).any((i) => i.serviceId == node.id);

    void addToCart() {
      ref.read(cartProvider.notifier).addToCart(
            node,
            priceAdjustment: selectedAmcPlan != null
                ? 0.0
                : priceAdjustment + addonsTotal,
            parentNodeId: parentNodeId,
            amcPlan: selectedAmcPlan,
            amcQuantity: 1,
          );
    }

    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 24),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1A1714).withAlpha(90),
                        blurRadius: 70,
                        spreadRadius: -20,
                        offset: const Offset(0, 30),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Header: photo | info ───────────────────────────────
                      _WebHeader(
                        node: node,
                        heroUrl: heroUrl,
                        hasHero: hasHero,
                        displayPrice: displayPrice,
                        hasAdjustment: hasAdjustment,
                        onClose: () => Navigator.of(context).maybePop(),
                      ),

                      // ── Attribute selection ────────────────────────────────
                      if (node.isLeafBookable && attrs.isNotEmpty)
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(28, 20, 28, 0),
                          child: ServiceAttributeSection(
                            attrs: attrs,
                            selections: selections,
                            onChanged: (a, o) =>
                                onOptionSelected(a, o, attrs),
                          ),
                        ),

                      // ── Add-ons ────────────────────────────────────────────
                      if (node.isLeafBookable && addOns.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                          decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(color: _kBorder),
                              bottom: BorderSide(color: _kBorder),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionHeaderRow(title: 'Suggested Add-ons'),
                              const SizedBox(height: 14),
                              // 4-col grid
                              _WebAddonsGrid(
                                addOns: addOns,
                                selectedIds: selectedAddonIds,
                                onToggle: onAddonToggled,
                              ),
                            ],
                          ),
                        ),

                      // ── AMC + About + FAQs + Reviews ───────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (node.isLeafBookable)
                              Consumer(
                                builder: (ctx, ref, _) {
                                  final plans = ref
                                      .watch(amcPlansProvider(node.id))
                                      .valueOrNull;
                                  if (plans == null || plans.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _SectionHeaderRow(title: 'AMC Plans'),
                                      const SizedBox(height: 12),
                                      _InlineAmcPlans(
                                        serviceId: node.id,
                                        selectedPlan: selectedAmcPlan,
                                        onPlanSelected: onAmcPlanSelected,
                                        regularPrice: node.basePrice,
                                        isWeb: true,
                                      ),
                                      const SizedBox(height: 26),
                                    ],
                                  );
                                },
                              ),

                            if (node.isLeafBookable) ...[
                              // About — flat on web
                              Text('About this service',
                                  style: GoogleFonts.poppins(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: _kInk)),
                              const SizedBox(height: 10),
                              Text(
                                node.description?.isNotEmpty == true
                                    ? node.description!
                                    : 'No description available.',
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: _kMuted,
                                    height: 1.6),
                              ),
                              const SizedBox(height: 18),

                              if (node.includedItems.isNotEmpty)
                                _IncludedSection(items: node.includedItems),
                              if (node.excludedItems.isNotEmpty)
                                _ExcludedSection(items: node.excludedItems),
                              if (node.beforeAfterPairs.isNotEmpty)
                                _BeforeAfterSection(
                                    pairs: node.beforeAfterPairs),

                              if (node.contentBlocks.isNotEmpty)
                                _ContentBlocksSection(
                                    blocks: node.contentBlocks),

                              Text('FAQs',
                                  style: GoogleFonts.poppins(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: _kInk)),
                              const SizedBox(height: 12),
                              if (faqs.isEmpty) ...[
                                const Text('No FAQs yet.',
                                    style: TextStyle(
                                        fontSize: 13, color: _kMuted)),
                                const SizedBox(height: 6),
                                AskQuestionLink(serviceId: node.id, parentId: parentNodeId),
                                const SizedBox(height: 8),
                              ] else ...[
                                FaqSection(faqs: faqs),
                                const SizedBox(height: 6),
                                AskQuestionLink(serviceId: node.id, parentId: parentNodeId),
                                const SizedBox(height: 12),
                              ],
                              _AccordionSection(
                                label: node.reviewCount > 0
                                    ? 'Reviews (${node.reviewCount})'
                                    : 'Reviews',
                                isLast: true,
                                child: ServiceReviewsSection(
                                    serviceId: node.id, showHeader: false),
                              ),
                              const SizedBox(height: 4),
                            ],

                            if (node.hasChildren)
                              (isUnavailable || isEffectivelyHidden)
                                  ? CatalogUnavailabilityBanner(
                                      message: isUnavailable
                                          ? avail?.message
                                          : null,
                                      isHidden: isEffectivelyHidden,
                                    )
                                  : _ChildrenSection(
                                      node: node,
                                      children: children,
                                    ),

                            if (!node.hasChildren && !node.isBookable)
                              const _ComingSoonBanner(),
                          ],
                        ),
                      ),

                      // ── Footer bar ─────────────────────────────────────────
                      if (node.isLeafBookable)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 18),
                          decoration: const BoxDecoration(
                            border:
                                Border(top: BorderSide(color: _kBorder)),
                          ),
                          child: Row(
                            children: [
                              Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('From',
                                      style: TextStyle(
                                          fontSize: 11, color: _kMuted2)),
                                  Text('₹${displayPrice.toInt()}',
                                      style: GoogleFonts.poppins(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                          color: _kInk,
                                          height: 1.1)),
                                ],
                              ),
                              const Spacer(),
                              MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                onTap: inCart
                                    ? () => openCart(context)
                                    : addToCart,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 13),
                                  decoration: BoxDecoration(
                                      color: _kInk,
                                      borderRadius:
                                          BorderRadius.circular(100)),
                                  child: Text(
                                    inCart
                                        ? '🛒  View Cart'
                                        : '🛒  ${selectedAmcPlan != null ? 'Book Now' : 'Add to Cart'}',
                                    style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white),
                                  ),
                                ),
                              ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Web 4-column add-ons grid ─────────────────────────────────────────────────

class _WebAddonsGrid extends StatelessWidget {
  const _WebAddonsGrid({
    required this.addOns,
    required this.selectedIds,
    required this.onToggle,
  });

  final List<AddOnModel> addOns;
  final Set<String> selectedIds;
  final void Function(String, bool) onToggle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      const cols = 4;
      const gap = 16.0;
      final itemW = (constraints.maxWidth - gap * (cols - 1)) / cols;

      final rows = <List<AddOnModel>>[];
      for (var i = 0; i < addOns.length; i += cols) {
        rows.add(addOns.sublist(
            i, i + cols > addOns.length ? addOns.length : i + cols));
      }

      return Column(
        children: rows.map((row) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: row.asMap().entries.map((e) {
                final a = e.value;
                final isSelected = selectedIds.contains(a.id);
                return [
                  SizedBox(
                    width: itemW,
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFFF1ECE1),
                                Color(0xFFEAE3D4)
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.name,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _kInk),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              Text('₹${a.price.toInt()}',
                                  style: const TextStyle(
                                      fontSize: 12, color: _kMuted)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                          onTap: () => onToggle(a.id, !isSelected),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? _kGold
                                  : const Color(0xFFECE7DE),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Icon(
                                isSelected
                                    ? Icons.check_rounded
                                    : Icons.add_rounded,
                                size: 13,
                                color: isSelected ? Colors.white : _kInk,
                              ),
                            ),
                          ),
                        ),
                        ),
                      ],
                    ),
                  ),
                  if (e.key < row.length - 1) const SizedBox(width: gap),
                ];
              }).expand((w) => w).toList(),
            ),
          );
        }).toList(),
      );
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// What's Included
// ═══════════════════════════════════════════════════════════════════════════════

class _IncludedSection extends StatelessWidget {
  const _IncludedSection({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("What's Included",
              style: GoogleFonts.poppins(
                  fontSize: 15, fontWeight: FontWeight.w700, color: _kInk)),
          const SizedBox(height: 10),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.check_circle_rounded,
                        size: 15, color: Color(0xFF22C55E)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(item,
                        style: const TextStyle(
                            fontSize: 13, color: _kInk, height: 1.5)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// What's Excluded
// ═══════════════════════════════════════════════════════════════════════════════

class _ExcludedSection extends StatelessWidget {
  const _ExcludedSection({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("What's Excluded",
              style: GoogleFonts.poppins(
                  fontSize: 15, fontWeight: FontWeight.w700, color: _kInk)),
          const SizedBox(height: 10),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.cancel_rounded,
                        size: 15, color: Color(0xFFEF4444)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(item,
                        style: const TextStyle(
                            fontSize: 13, color: _kMuted, height: 1.5)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Before & After — 2-column image pairs
// ═══════════════════════════════════════════════════════════════════════════════

class _BeforeAfterSection extends StatelessWidget {
  const _BeforeAfterSection({required this.pairs});
  final List<Map<String, String>> pairs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Before & After',
              style: GoogleFonts.poppins(
                  fontSize: 15, fontWeight: FontWeight.w700, color: _kInk)),
          const SizedBox(height: 12),
          ...pairs.map((pair) {
            final beforeUrl = pair['before_url'] ?? '';
            final afterUrl = pair['after_url'] ?? '';
            if (beforeUrl.isEmpty && afterUrl.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  if (beforeUrl.isNotEmpty)
                    Expanded(child: _BAPhoto(url: beforeUrl, label: 'Before')),
                  if (beforeUrl.isNotEmpty && afterUrl.isNotEmpty)
                    const SizedBox(width: 8),
                  if (afterUrl.isNotEmpty)
                    Expanded(child: _BAPhoto(url: afterUrl, label: 'After')),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _BAPhoto extends StatelessWidget {
  const _BAPhoto({required this.url, required this.label});
  final String url;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        children: [
          SizedBox(
            height: 150,
            width: double.infinity,
            child: Image.network(
              url,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, p) =>
                  p == null ? child : const ColoredBox(color: Color(0xFFEAE3D4)),
              errorBuilder: (_, _, _) => Container(
                color: const Color(0xFFF1ECE1),
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined,
                    color: _kMuted2, size: 28),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withAlpha(150)],
                ),
              ),
              child: Center(
                child: Text(
                  label,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContentBlocksSection extends StatelessWidget {
  const _ContentBlocksSection({required this.blocks});
  final List<Map<String, dynamic>> blocks;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: blocks.map<Widget>(_buildBlock).toList(),
      ),
    );
  }

  Widget _buildBlock(Map<String, dynamic> block) {
    final type = (block['type'] as String?) ?? 'text';
    final text = ((block['text'] as String?) ?? '').trim();
    final imageUrl = ((block['image_url'] as String?) ?? '').trim();

    Widget imageWidget(String url) => ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            url,
            width: double.infinity,
            fit: BoxFit.cover,
            loadingBuilder: (_, child, p) =>
                p == null ? child : const ColoredBox(color: Color(0xFFEAE3D4)),
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        );

    Widget? content;

    if (type == 'image') {
      if (imageUrl.isEmpty) return const SizedBox.shrink();
      content = imageWidget(imageUrl);
    } else if (type == 'image_text') {
      if (imageUrl.isEmpty && text.isEmpty) return const SizedBox.shrink();
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageUrl.isNotEmpty) imageWidget(imageUrl),
          if (imageUrl.isNotEmpty && text.isNotEmpty) const SizedBox(height: 10),
          if (text.isNotEmpty)
            Text(text,
                style:
                    const TextStyle(fontSize: 13, color: _kMuted, height: 1.6)),
        ],
      );
    } else {
      if (text.isEmpty) return const SizedBox.shrink();
      content = Text(text,
          style: const TextStyle(fontSize: 13, color: _kMuted, height: 1.6));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: content,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Web header: photo panel | info panel
// ═══════════════════════════════════════════════════════════════════════════════

class _WebHeader extends StatelessWidget {
  const _WebHeader({
    required this.node,
    required this.heroUrl,
    required this.hasHero,
    required this.displayPrice,
    required this.hasAdjustment,
    required this.onClose,
  });

  final CatalogNodeModel node;
  final String? heroUrl;
  final bool hasHero;
  final double displayPrice;
  final bool hasAdjustment;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _kBorder))),
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo panel
              if (hasHero && heroUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 320,
                    height: 220,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _HeroImage(url: heroUrl!),
                        Positioned(
                          top: 12,
                          left: 12,
                          child: _CircleNavBtn(
                              icon: Icons.arrow_back_rounded,
                              onTap: onClose),
                        ),
                        Positioned(
                          bottom: 10,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1714).withAlpha(166),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: const Text('1/6',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    height: 1.4)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: const _StripedBox(width: 320, height: 220),
                ),

              const SizedBox(width: 28),

              // Info
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 44),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (node.parentName?.isNotEmpty == true) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                              color: _kInk,
                              borderRadius: BorderRadius.circular(100)),
                          child: Text(node.parentName!,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Text(node.name,
                          style: GoogleFonts.poppins(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: _kInk,
                              height: 1.2)),
                      const SizedBox(height: 8),
                      if (node.rating > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              const Text('★',
                                  style:
                                      TextStyle(color: _kGold, fontSize: 13)),
                              const SizedBox(width: 4),
                              Text(node.rating.toStringAsFixed(1),
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _kInk)),
                              if (node.reviewCount > 0) ...[
                                const SizedBox(width: 4),
                                Text('(${node.reviewCount} reviews)',
                                    style: const TextStyle(
                                        fontSize: 13, color: _kMuted2)),
                              ],
                            ],
                          ),
                        ),
                      if (node.description?.isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Text(node.description!,
                              style: const TextStyle(
                                  fontSize: 13, color: _kMuted, height: 1.6),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis),
                        ),
                      if (node.basePrice != null)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            const Text('From',
                                style: TextStyle(
                                    fontSize: 13, color: _kMuted2)),
                            const SizedBox(width: 8),
                            Text('₹${displayPrice.toInt()}',
                                style: GoogleFonts.poppins(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    color: _kInk,
                                    height: 1.0)),
                            if (hasAdjustment) ...[
                              const SizedBox(width: 8),
                              const Text('incl. add-ons',
                                  style: TextStyle(
                                      fontSize: 12, color: _kMuted2)),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Close ✕
          Positioned(
            top: 0,
            right: 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
              onTap: onClose,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                    color: const Color(0xFFF2EFE9),
                    borderRadius: BorderRadius.circular(100)),
                child: const Icon(Icons.close_rounded,
                    size: 16, color: _kInk),
              ),
            ),
            ),
          ),
        ],
      ),
    );
  }
}
