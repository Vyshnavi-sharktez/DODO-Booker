import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

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
import '../../amc/widgets/amc_section.dart';
import '../models/catalog_node_model.dart';
import '../providers/catalog_providers.dart';
import '../utils/catalog_launcher.dart';
import '../widgets/catalog_unavailability_widgets.dart';

// Design tokens — from handoff
const _kInk = Color(0xFF1A1714);
const _kMuted = Color(0xFF6E6A64);
const _kMuted2 = Color(0xFF9A948C);
const _kGold = Color(0xFFF4A81D);
const _kGoldLink = Color(0xFFD98A0A);
const _kBorder = Color(0xFFECE7DE);
const _kBg = Color(0xFFFBF8F3);

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
        ? (ref.watch(catalogNodeFaqsProvider(node.id)).valueOrNull ?? [])
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

    // ── Web layout ───────────────────────────────────────────────────────────
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

    // ── Mobile layout ────────────────────────────────────────────────────────
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
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: _kInk,
                ),
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

                // ── Category hero fallback header ──────────────────────────
                if (hasHero && !node.isLeafBookable)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                    child: Text(
                      node.name,
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: _kInk,
                      ),
                    ),
                  ),

                // ── No-hero: breadcrumb + info header ─────────────────────
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

                // ── Children list ──────────────────────────────────────────
                if (node.hasChildren)
                  (isUnavailable || isEffectivelyHidden)
                      ? CatalogUnavailabilityBanner(
                          message: isUnavailable ? avail?.message : null,
                          isHidden: isEffectivelyHidden,
                        )
                      : _ChildrenSection(node: node, children: children),

                // ── Add-ons ────────────────────────────────────────────────
                if (node.isLeafBookable && addOns.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: _SectionHeaderRow(
                      title: 'Suggested Add-ons',
                    ),
                  ),
                  ServiceAddonSection(
                    addOns: addOns,
                    selectedIds: _selectedAddonIds,
                    onToggle: _onAddonToggled,
                  ),
                ],

                // ── AMC ────────────────────────────────────────────────────
                if (node.isLeafBookable) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: _SectionHeaderRow(title: 'AMC Plans'),
                  ),
                  AmcSection(
                    serviceId: node.id,
                    selectedPlan: _selectedAmcPlan,
                    onPlanSelected: (plan) =>
                        setState(() => _selectedAmcPlan = plan),
                    regularPrice:
                        node.basePrice != null && node.basePrice! > 0
                            ? node.basePrice
                            : null,
                  ),
                ],

                // ── Accordion: About / FAQs / Reviews ─────────────────────
                if (node.isLeafBookable) ...[
                  const SizedBox(height: 24),
                  _AccordionSection(
                    label: 'About this service',
                    isFirst: true,
                    child: node.description?.isNotEmpty == true
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(0, 8, 0, 14),
                            child: Text(
                              node.description!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: _kMuted,
                                height: 1.6,
                              ),
                            ),
                          )
                        : const Padding(
                            padding: EdgeInsets.fromLTRB(0, 8, 0, 14),
                            child: Text(
                              'No description available.',
                              style: TextStyle(fontSize: 13, color: _kMuted2),
                            ),
                          ),
                  ),
                  _AccordionSection(
                    label: 'FAQs',
                    child: faqs.isNotEmpty
                        ? FaqSection(faqs: faqs)
                        : const Padding(
                            padding: EdgeInsets.fromLTRB(0, 8, 0, 14),
                            child: Text(
                              'No FAQs yet.',
                              style: TextStyle(fontSize: 13, color: _kMuted2),
                            ),
                          ),
                  ),
                  _AccordionSection(
                    label: node.reviewCount > 0
                        ? 'Reviews (${node.reviewCount})'
                        : 'Reviews',
                    isLast: true,
                    child: ServiceReviewsSection(serviceId: node.id),
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

      // ── Sticky cart bar ──────────────────────────────────────────────────
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

class CatalogNodeFetchScreen extends ConsumerWidget {
  const CatalogNodeFetchScreen({super.key, required this.nodeId});
  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(catalogNodeProvider(nodeId));
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
}

// ═══════════════════════════════════════════════════════════════════════════════
// Mobile hero photo (260px + status bar)
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
    final totalHeight = statusBarH + 260.0;

    return SizedBox(
      height: totalHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _HeroImage(url: imageUrl),

          // Back button
          Positioned(
            top: statusBarH + 16,
            left: 16,
            child: _CircleIconButton(
              icon: Icons.arrow_back_rounded,
              onTap: () => context.pop(),
            ),
          ),

          // Heart button (white circle wrapper)
          if (showHeart)
            Positioned(
              top: statusBarH + 16,
              right: 16,
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: HeartButton(serviceId: node.id, mini: true),
                ),
              ),
            ),

          // Photo counter pill
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
              child: const Text(
                '1/6',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
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
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(180),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(180),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: _kInk),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Service content block (below hero photo on mobile)
// category badge + title + rating + description + price row
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
          if (node.parentName != null && node.parentName!.isNotEmpty) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _kInk,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                node.parentName!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Title
          Text(
            node.name,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _kInk,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),

          // Rating row
          if (node.rating > 0 || node.estimatedDuration != null)
            Row(
              children: [
                if (node.rating > 0) ...[
                  const Text('★', style: TextStyle(color: _kGold, fontSize: 13)),
                  const SizedBox(width: 4),
                  Text(
                    node.rating.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _kInk,
                    ),
                  ),
                  if (node.reviewCount > 0) ...[
                    const SizedBox(width: 4),
                    Text(
                      '(${node.reviewCount} reviews)',
                      style: const TextStyle(
                        fontSize: 13,
                        color: _kMuted2,
                      ),
                    ),
                  ],
                  const SizedBox(width: 12),
                ],
                if (node.estimatedDuration != null)
                  Text(
                    '${node.estimatedDuration} min',
                    style: const TextStyle(
                      fontSize: 12,
                      color: _kMuted2,
                    ),
                  ),
              ],
            ),

          // Description
          if (node.description?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              node.description!,
              style: const TextStyle(
                fontSize: 13,
                color: _kMuted,
                height: 1.6,
              ),
            ),
          ],

          // Price row
          if (node.basePrice != null) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Text(
                  'From',
                  style: TextStyle(fontSize: 13, color: _kMuted2),
                ),
                const SizedBox(width: 8),
                Text(
                  '₹${displayPrice.toInt()}',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _kInk,
                    height: 1.0,
                  ),
                ),
                if (hasAdjustment) ...[
                  const SizedBox(width: 8),
                  const Text(
                    'incl. add-ons',
                    style: TextStyle(fontSize: 12, color: _kMuted2),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Section header row: Poppins 700 15px + optional "View all →"
// ═══════════════════════════════════════════════════════════════════════════════

class _SectionHeaderRow extends StatelessWidget {
  const _SectionHeaderRow({required this.title, this.onViewAll});
  final String title;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: _kInk,
          ),
        ),
        const Spacer(),
        if (onViewAll != null)
          GestureDetector(
            onTap: onViewAll,
            child: const Text(
              'View all →',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _kGoldLink,
              ),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Accordion section row
// ═══════════════════════════════════════════════════════════════════════════════

class _AccordionSection extends StatefulWidget {
  const _AccordionSection({
    required this.label,
    required this.child,
    this.isFirst = false,
    this.isLast = false,
    this.initiallyOpen = false,
  });

  final String label;
  final Widget child;
  final bool isFirst;
  final bool isLast;
  final bool initiallyOpen;

  @override
  State<_AccordionSection> createState() => _AccordionSectionState();
}

class _AccordionSectionState extends State<_AccordionSection> {
  late bool _open;

  @override
  void initState() {
    super.initState();
    _open = widget.initiallyOpen;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row
          GestureDetector(
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
                    child: Text(
                      widget.label,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _kInk,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    child: const Text(
                      '⌄',
                      style: TextStyle(fontSize: 18, color: _kMuted2, height: 1),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expanded content
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              decoration: widget.isLast
                  ? const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: _kBorder, width: 1),
                      ),
                    )
                  : null,
              child: widget.child,
            ),
            crossFadeState: _open
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
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
// Breadcrumb (no-hero fallback)
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
          GestureDetector(
            onTap: onParentTap,
            child: Text(
              parentName,
              style: const TextStyle(
                fontSize: 12,
                color: _kMuted2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              Icons.chevron_right_rounded,
              size: 14,
              color: _kMuted2,
            ),
          ),
          Expanded(
            child: Text(
              nodeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: _kInk,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Node info header (no-image fallback path)
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
          if (node.parentName != null && node.parentName!.isNotEmpty) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _kInk,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                node.parentName!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Text(
            node.name,
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: _kInk,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (node.rating > 0) ...[
                const Text('★', style: TextStyle(color: _kGold, fontSize: 13)),
                const SizedBox(width: 4),
                Text(
                  node.rating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _kInk,
                  ),
                ),
                if (node.reviewCount > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '(${node.reviewCount})',
                    style: const TextStyle(fontSize: 12, color: _kMuted2),
                  ),
                ],
                const SizedBox(width: 12),
              ],
              if (node.estimatedDuration != null) ...[
                const Icon(
                  Icons.schedule_rounded,
                  size: 14,
                  color: _kMuted2,
                ),
                const SizedBox(width: 4),
                Text(
                  '${node.estimatedDuration} min',
                  style: const TextStyle(fontSize: 12, color: _kMuted2),
                ),
              ],
            ],
          ),
          if (node.isLeafBookable && node.basePrice != null) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Text(
                  'From',
                  style: TextStyle(fontSize: 13, color: _kMuted2),
                ),
                const SizedBox(width: 8),
                Text(
                  '₹${displayPrice.toInt()}',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _kInk,
                    height: 1.0,
                  ),
                ),
                if (hasAdjustment) ...[
                  const SizedBox(width: 8),
                  const Text(
                    'incl. add-ons',
                    style: TextStyle(fontSize: 12, color: _kMuted2),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Children list section (category navigation)
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
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: _kInk,
            ),
          ),
        ),

        if (children.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Text(
              'Loading…',
              style: TextStyle(color: _kMuted2, fontSize: 13),
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

// ═══════════════════════════════════════════════════════════════════════════════
// Child list item
// ═══════════════════════════════════════════════════════════════════════════════

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
          border: Border.all(color: _kBorder, width: 0.8),
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
                  loadingBuilder: (_, child, p) => p == null
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
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
                          color: _kInk,
                          height: 1.3,
                        ),
                      ),
                      if (node.relAvailabilityStatus == 'unavailable') ...[
                        const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.pause_circle_outline_rounded,
                              size: 11,
                              color: Color(0xFFF59E0B),
                            ),
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
                            color: _kMuted,
                            height: 1.3,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (node.isLeafBookable &&
                              node.basePrice != null) ...[
                            Text(
                              '₹${node.basePrice!.toInt()}',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: _kInk,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'onwards',
                              style: TextStyle(
                                fontSize: 11,
                                color: _kMuted2,
                              ),
                            ),
                          ] else if (node.hasChildren)
                            Text(
                              '${node.childrenCount} ${node.childrenCount == 1 ? 'option' : 'options'}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: _kMuted,
                              ),
                            ),
                          if (node.estimatedDuration != null) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.schedule_rounded,
                              size: 12,
                              color: _kMuted2,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${node.estimatedDuration} min',
                              style: const TextStyle(
                                fontSize: 11,
                                color: _kMuted2,
                              ),
                            ),
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
                    color: _kMuted,
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

// ═══════════════════════════════════════════════════════════════════════════════
// Loyalty earn badge
// ═══════════════════════════════════════════════════════════════════════════════

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
          const Icon(
            Icons.workspace_premium_rounded,
            size: 10,
            color: AppColors.gold,
          ),
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

// ═══════════════════════════════════════════════════════════════════════════════
// Coming Soon banner
// ═══════════════════════════════════════════════════════════════════════════════

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
        child: const Column(
          children: [
            Icon(Icons.schedule_rounded, size: 36, color: AppColors.gold),
            SizedBox(height: 12),
            Text(
              'Coming Soon',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _kInk,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'This service is not yet available for booking.\nCheck back soon.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: _kMuted,
                height: 1.55,
              ),
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
          priceAdjustment: amcPlan != null
              ? 0.0
              : priceAdjustment + addonsTotal,
          parentNodeId: parentNodeId,
          amcPlan: amcPlan,
          amcQuantity: amcQuantity,
        );
  }

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
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: _kBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Price
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'From',
                style: TextStyle(fontSize: 10, color: _kMuted2),
              ),
              Text(
                '₹${displayPrice.toInt()}',
                style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: _kInk,
                  height: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),

          // Gold pill CTA
          Expanded(
            child: GestureDetector(
              onTap: inCart ? () => openCart(context) : () => _addToCart(ref),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _kGold,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      inCart ? '🛒 View Cart' : '🛒 ${amcPlan != null ? 'Book Now' : 'Add to Cart'}',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _kInk,
                      ),
                    ),
                  ],
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
// Web scaffold — modal-style card layout
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
    final cartItems = ref.watch(cartProvider);
    final inCart = cartItems.any((item) => item.serviceId == node.id);

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
                        color:
                            const Color(0xFF1A1714).withAlpha(90),
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
                        onClose: () => context.pop(),
                      ),

                      // ── Attribute selection ────────────────────────────────
                      if (node.isLeafBookable && attrs.isNotEmpty)
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(28, 20, 28, 0),
                          child: ServiceAttributeSection(
                            attrs: attrs,
                            selections: selections,
                            onChanged: (attrId, optId) =>
                                onOptionSelected(attrId, optId, attrs),
                          ),
                        ),

                      // ── Add-ons ────────────────────────────────────────────
                      if (node.isLeafBookable && addOns.isNotEmpty) ...[
                        Container(
                          padding:
                              const EdgeInsets.fromLTRB(28, 24, 28, 24),
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
                              ServiceAddonSection(
                                addOns: addOns,
                                selectedIds: selectedAddonIds,
                                onToggle: onAddonToggled,
                              ),
                            ],
                          ),
                        ),
                      ],

                      // ── AMC + About + FAQs + Reviews ───────────────────────
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(28, 24, 28, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (node.isLeafBookable) ...[
                              _SectionHeaderRow(title: 'AMC Plans'),
                              const SizedBox(height: 14),
                              AmcSection(
                                serviceId: node.id,
                                selectedPlan: selectedAmcPlan,
                                onPlanSelected: onAmcPlanSelected,
                                regularPrice: node.basePrice != null &&
                                        node.basePrice! > 0
                                    ? node.basePrice
                                    : null,
                              ),
                              const SizedBox(height: 26),

                              // About — flat text on web
                              Text(
                                'About this service',
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: _kInk,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                node.description?.isNotEmpty == true
                                    ? node.description!
                                    : 'No description available.',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: _kMuted,
                                  height: 1.6,
                                ),
                                // maxWidth 640 handled by parent constraint
                              ),
                              const SizedBox(height: 18),

                              // FAQs accordion
                              _AccordionSection(
                                label: 'FAQs',
                                isFirst: true,
                                child: faqs.isNotEmpty
                                    ? FaqSection(faqs: faqs)
                                    : const Padding(
                                        padding: EdgeInsets.fromLTRB(
                                            0, 8, 0, 14),
                                        child: Text(
                                          'No FAQs yet.',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: _kMuted2,
                                          ),
                                        ),
                                      ),
                              ),

                              // Reviews
                              _AccordionSection(
                                label: node.reviewCount > 0
                                    ? 'Reviews (${node.reviewCount})'
                                    : 'Reviews',
                                isLast: true,
                                child: ServiceReviewsSection(
                                    serviceId: node.id),
                              ),
                              const SizedBox(height: 4),
                            ],

                            // Category navigation
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
                            border: Border(
                              top: BorderSide(color: _kBorder),
                            ),
                          ),
                          child: Row(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'From',
                                    style: TextStyle(
                                        fontSize: 11, color: _kMuted2),
                                  ),
                                  Text(
                                    '₹${displayPrice.toInt()}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: _kInk,
                                      height: 1.1,
                                    ),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: inCart
                                    ? () => openCart(context)
                                    : addToCart,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 13),
                                  decoration: BoxDecoration(
                                    color: _kGold,
                                    borderRadius:
                                        BorderRadius.circular(100),
                                  ),
                                  child: Text(
                                    inCart
                                        ? '🛒 View Cart'
                                        : '🛒 ${selectedAmcPlan != null ? 'Book Now' : 'Add to Cart'}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: _kInk,
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
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
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
                        // Back button on photo
                        Positioned(
                          top: 12,
                          left: 12,
                          child: _CircleIconButton(
                            icon: Icons.arrow_back_rounded,
                            onTap: onClose,
                          ),
                        ),
                        // Counter
                        Positioned(
                          bottom: 10,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color:
                                  const Color(0xFF1A1714).withAlpha(166),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: const Text(
                              '1/6',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(width: 28),

              // Info panel
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category badge
                      if (node.parentName?.isNotEmpty == true) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _kInk,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            node.parentName!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      // Title
                      Text(
                        node.name,
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: _kInk,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Rating
                      if (node.rating > 0 || node.estimatedDuration != null)
                        Row(
                          children: [
                            if (node.rating > 0) ...[
                              const Text('★',
                                  style: TextStyle(
                                      color: _kGold, fontSize: 13)),
                              const SizedBox(width: 4),
                              Text(
                                node.rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _kInk,
                                ),
                              ),
                              if (node.reviewCount > 0) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '(${node.reviewCount} reviews)',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: _kMuted2,
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),

                      // Description
                      if (node.description?.isNotEmpty == true) ...[
                        const SizedBox(height: 8),
                        Text(
                          node.description!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: _kMuted,
                            height: 1.6,
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],

                      // Price
                      if (node.basePrice != null) ...[
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            const Text(
                              'From',
                              style:
                                  TextStyle(fontSize: 13, color: _kMuted2),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '₹${displayPrice.toInt()}',
                              style: GoogleFonts.poppins(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: _kInk,
                                height: 1.0,
                              ),
                            ),
                            if (hasAdjustment) ...[
                              const SizedBox(width: 8),
                              const Text(
                                'incl. add-ons',
                                style: TextStyle(
                                    fontSize: 12, color: _kMuted2),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Close button (✕)
          Positioned(
            top: 0,
            right: 0,
            child: GestureDetector(
              onTap: onClose,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFF2EFE9),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: const Icon(Icons.close_rounded,
                    size: 16, color: _kInk),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
