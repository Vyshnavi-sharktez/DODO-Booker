import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/utils/service_image_registry.dart';
import '../../../models/faq_model.dart';
import '../../../models/service_attribute_model.dart';
import '../../../models/addon_model.dart';
import '../../cart/providers/cart_provider.dart';
import '../../cart/services/checkout_service.dart';
import '../../cart/utils/cart_launcher.dart';
import '../../../routes/app_router.dart';
import '../../category/services/category_providers.dart';
import '../../reviews/widgets/service_reviews_section.dart';
import '../../service/widgets/faq_section.dart';
import '../../service/widgets/service_attribute_section.dart';
import '../../address/services/address_providers.dart';
import '../../amc/providers/amc_provider.dart';
import '../../loyalty/providers/loyalty_providers.dart';
import '../../loyalty/utils/loyalty_utils.dart';
import '../../wishlist/widgets/heart_button.dart';
import '../models/catalog_node_model.dart';
import '../providers/catalog_providers.dart';
import 'catalog_unavailability_widgets.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _kInk = Color(0xFF1A1714);
const _kMuted = Color(0xFF6E6A64);
const _kMuted2 = Color(0xFF9A948C);
const _kGold = Color(0xFFF4A81D);
const _kBorder = Color(0xFFECE7DE);
const _kBg = Color(0xFFFBF8F3);
const _kAmcPopularBg = Color(0xFFFDF2D9);

// ═══════════════════════════════════════════════════════════════════════════════
// CatalogNodeModal
// ═══════════════════════════════════════════════════════════════════════════════

class CatalogNodeModal extends ConsumerStatefulWidget {
  const CatalogNodeModal({
    super.key,
    required this.node,
    this.parentNodeId,
  });

  final CatalogNodeModel node;
  final String? parentNodeId;

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
  AmcPlanModel? _selectedAmcPlan;

  CatalogNodeModel get node => widget.node;

  @override
  void initState() {
    super.initState();
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
    final displayPrice = _selectedAmcPlan != null
        ? _selectedAmcPlan!.finalPrice
        : (node.basePrice ?? 0.0) + _priceAdjustment + addonsTotal;
    final hasAdjustment = _priceAdjustment > 0 || addonsTotal > 0;

    final heroUrl = ServiceImageRegistry.resolve(node.imageUrl, node.name);
    final hasHero = heroUrl.isNotEmpty;

    final maxModalW = isWeb ? 860.0 : 520.0;
    final maxModalH = MediaQuery.sizeOf(context).height * (isWeb ? 0.90 : 0.94);

    return Stack(
      children: [
        // ── Blurred dimmed backdrop ──────────────────────────────────────────
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

        // ── Modal card ───────────────────────────────────────────────────────
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxModalW,
                maxHeight: maxModalH,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isWeb ? 20 : 12,
                  vertical: isWeb ? 20 : 10,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _kBg,
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
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Header block ─────────────────────────────────────
                        _ModalHeader(
                          node: node,
                          heroUrl: hasHero ? heroUrl : null,
                          displayPrice: displayPrice,
                          hasAdjustment: hasAdjustment,
                          isWeb: isWeb,
                          onClose: () => Navigator.of(context).pop(),
                        ),

                        // ── Scrollable content ────────────────────────────────
                        Flexible(
                          child: ScrollConfiguration(
                            behavior: ScrollConfiguration.of(context)
                                .copyWith(scrollbars: false),
                            child: SingleChildScrollView(
                              padding: EdgeInsets.only(
                                  bottom: node.isLeafBookable ? 6 : 24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Attribute selection
                                  if (node.isLeafBookable && attrs.isNotEmpty)
                                    Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: isWeb ? 28 : 20),
                                      child: ServiceAttributeSection(
                                        attrs: attrs,
                                        selections: _selections,
                                        onChanged: (a, o) =>
                                            _onOptionSelected(a, o, attrs),
                                      ),
                                    ),

                                  // Children list (category)
                                  if (node.hasChildren)
                                    (isUnavailable || isEffectivelyHidden)
                                        ? CatalogUnavailabilityBanner(
                                            message: isUnavailable
                                                ? avail?.message
                                                : null,
                                            isHidden: isEffectivelyHidden,
                                          )
                                        : _ModalChildrenList(
                                            node: node,
                                            children: children,
                                          ),

                                  // Add-ons
                                  if (node.isLeafBookable &&
                                      addOns.isNotEmpty) ...[
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          20, 24, 20, 12),
                                      child: const _SectionLabel(
                                          text: 'Suggested Add-ons'),
                                    ),
                                    _AddonCardScroll(
                                      addOns: addOns,
                                      selectedIds: _selectedAddonIds,
                                      onToggle: _onAddonToggled,
                                    ),
                                    const _HRule(),
                                  ],

                                  // AMC plans
                                  if (node.isLeafBookable)
                                    Consumer(
                                      builder: (ctx, aRef, _) {
                                        final plans = aRef
                                            .watch(amcPlansProvider(node.id))
                                            .valueOrNull;
                                        if (plans == null || plans.isEmpty) {
                                          return const SizedBox.shrink();
                                        }
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Padding(
                                              padding: EdgeInsets.fromLTRB(
                                                  isWeb ? 28 : 20,
                                                  18,
                                                  isWeb ? 28 : 20,
                                                  12),
                                              child: const _SectionLabel(
                                                  text: 'AMC Plans'),
                                            ),
                                            Padding(
                                              padding: EdgeInsets.symmetric(
                                                  horizontal: isWeb ? 28 : 20),
                                              child: _InlineAmcPlans(
                                                serviceId: node.id,
                                                selectedPlan: _selectedAmcPlan,
                                                onPlanSelected: (plan) =>
                                                    setState(() =>
                                                        _selectedAmcPlan = plan),
                                                regularPrice: node.basePrice,
                                              ),
                                            ),
                                            const _HRule(),
                                          ],
                                        );
                                      },
                                    ),

                                  // About — accordion
                                  if (node.isLeafBookable)
                                    _AccordionSection(
                                      label: 'About this service',
                                      isFirst: true,
                                      padH: 20,
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            0, 4, 0, 14),
                                        child: Text(
                                          node.description?.isNotEmpty == true
                                              ? node.description!
                                              : 'No description available.',
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color: _kMuted,
                                              height: 1.6),
                                        ),
                                      ),
                                    ),

                                  // FAQs — inline list (always shown for leaf bookable)
                                  if (node.isLeafBookable)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          20, 20, 20, 0),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 8),
                                            child: Text('FAQs',
                                                style: GoogleFonts.poppins(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w700,
                                                    color: _kInk)),
                                          ),
                                          if (faqs.isEmpty) ...[
                                            const Text('No FAQs yet.',
                                                style: TextStyle(
                                                    fontSize: 13,
                                                    color: _kMuted)),
                                            const SizedBox(height: 6),
                                            AskQuestionLink(
                                                serviceId: node.id,
                                                parentId: widget.parentNodeId),
                                          ] else ...[
                                            FaqSection(faqs: faqs),
                                            const SizedBox(height: 6),
                                            AskQuestionLink(
                                                serviceId: node.id,
                                                parentId: widget.parentNodeId),
                                          ],
                                          const SizedBox(height: 8),
                                        ],
                                      ),
                                    ),

                                  // Reviews — accordion
                                  if (node.isLeafBookable)
                                    _AccordionSection(
                                      label: node.reviewCount > 0
                                          ? 'Reviews (${node.reviewCount})'
                                          : 'Reviews',
                                      isLast: true,
                                      padH: 20,
                                      child: ServiceReviewsSection(
                                          serviceId: node.id),
                                    ),

                                  // Coming Soon
                                  if (!node.hasChildren && !node.isBookable)
                                    const _ModalComingSoon(),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // ── Booking bar ───────────────────────────────────────
                        if (node.isLeafBookable)
                          (isUnavailable || isEffectivelyHidden)
                              ? CatalogUnavailabilityBar(
                                  message:
                                      isUnavailable ? avail?.message : null,
                                )
                              : _ModalBookingBar(
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
                                  isWeb: isWeb,
                                ),
                      ],
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

// ═══════════════════════════════════════════════════════════════════════════════
// Modal header
// Web: [320×220 photo | info panel] side-by-side
// Mobile: full-width hero photo stacked above info
// ═══════════════════════════════════════════════════════════════════════════════

class _ModalHeader extends StatelessWidget {
  const _ModalHeader({
    required this.node,
    required this.heroUrl,
    required this.displayPrice,
    required this.hasAdjustment,
    required this.isWeb,
    required this.onClose,
  });

  final CatalogNodeModel node;
  final String? heroUrl;
  final double displayPrice;
  final bool hasAdjustment;
  final bool isWeb;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    if (isWeb) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: _kBorder)),
        ),
        child: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Photo
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 280,
                    height: 200,
                    child: heroUrl != null
                        ? _HeroPhoto(url: heroUrl!)
                        : const _StripedPlaceholder(),
                  ),
                ),
                const SizedBox(width: 24),

                // Info panel
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 44, top: 4),
                    child: _InfoContent(
                      node: node,
                      displayPrice: displayPrice,
                      hasAdjustment: hasAdjustment,
                    ),
                  ),
                ),
              ],
            ),

            // ← Back
            Positioned(
              top: 0,
              left: 0,
              child: _BackCircle(onTap: onClose),
            ),

            // Close ✕
            Positioned(
              top: 0,
              right: 0,
              child: _CloseCircle(onTap: onClose),
            ),
          ],
        ),
      );
    }

    // Mobile: stacked
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero photo
          if (heroUrl != null)
            SizedBox(
              width: double.infinity,
              height: 200,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _HeroPhoto(url: heroUrl!),
                  // ← Back top-left
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _BackCircle(onTap: onClose),
                  ),
                  // Close top-right
                  Positioned(
                    top: 10,
                    right: 10,
                    child: _CloseCircle(onTap: onClose),
                  ),
                  // Heart top-right adjacent
                  if (node.isLeafBookable)
                    Positioned(
                      top: 10,
                      right: 50,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                            color: Colors.white, shape: BoxShape.circle),
                        child: Center(
                            child: HeartButton(
                                serviceId: node.id, mini: true)),
                      ),
                    ),
                ],
              ),
            )
          else
            // No hero: back on left, close on right
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _BackCircle(onTap: onClose),
                  _CloseCircle(onTap: onClose),
                ],
              ),
            ),

          // Info
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: _InfoContent(
              node: node,
              displayPrice: displayPrice,
              hasAdjustment: hasAdjustment,
            ),
          ),

          const Divider(height: 1, color: _kBorder),
        ],
      ),
    );
  }
}

// ── Close button circle ───────────────────────────────────────────────────────

class _CloseCircle extends StatelessWidget {
  const _CloseCircle({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: const Color(0xFFF2EFE9),
              borderRadius: BorderRadius.circular(100)),
          child: const Icon(Icons.close_rounded, size: 16, color: _kInk),
        ),
      ),
    );
  }
}

class _BackCircle extends StatelessWidget {
  const _BackCircle({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: const Color(0xFFF2EFE9),
              borderRadius: BorderRadius.circular(100)),
          child: const Icon(Icons.arrow_back_rounded, size: 16, color: _kInk),
        ),
      ),
    );
  }
}

// ── Info content (shared by mobile + web) ─────────────────────────────────────

class _InfoContent extends StatelessWidget {
  const _InfoContent({
    required this.node,
    required this.displayPrice,
    required this.hasAdjustment,
  });
  final CatalogNodeModel node;
  final double displayPrice;
  final bool hasAdjustment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Category badge
        if (node.parentName?.isNotEmpty == true) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: _kInk, borderRadius: BorderRadius.circular(100)),
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

        // Rating
        if (node.rating > 0) ...[
          Row(
            children: [
              const Text('★', style: TextStyle(color: _kGold, fontSize: 13)),
              const SizedBox(width: 4),
              Text(node.rating.toStringAsFixed(1),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _kInk)),
              if (node.reviewCount > 0) ...[
                const SizedBox(width: 4),
                Text('(${node.reviewCount} reviews)',
                    style:
                        const TextStyle(fontSize: 12, color: _kMuted2)),
              ],
            ],
          ),
          const SizedBox(height: 8),
        ],

        // Price
        if (node.isLeafBookable && node.basePrice != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text('From',
                  style: TextStyle(fontSize: 12, color: _kMuted2)),
              const SizedBox(width: 6),
              Text('₹${displayPrice.toInt()}',
                  style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _kInk,
                      height: 1.0)),
              if (hasAdjustment) ...[
                const SizedBox(width: 8),
                const Text('incl. add-ons',
                    style: TextStyle(fontSize: 11, color: _kMuted2)),
              ],
            ],
          )
        else if (node.hasChildren)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFECE7DE),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              '${node.childrenCount} '
              '${node.childrenCount == 1 ? 'service' : 'services'} available',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: _kMuted),
            ),
          ),
      ],
    );
  }
}

// ── Hero photo ────────────────────────────────────────────────────────────────

class _HeroPhoto extends StatelessWidget {
  const _HeroPhoto({required this.url});
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
          errorBuilder: (_, _, _) => const _StripedPlaceholder(),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            height: 70,
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

class _StripedPlaceholder extends StatelessWidget {
  const _StripedPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF1ECE1), Color(0xFFEAE3D4)],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Section label
// ═══════════════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: GoogleFonts.poppins(
            fontSize: 15, fontWeight: FontWeight.w700, color: _kInk));
  }
}

// ── Thin horizontal rule ──────────────────────────────────────────────────────

class _HRule extends StatelessWidget {
  const _HRule();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 20),
      child: Divider(height: 1, color: _kBorder),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Add-on card scroll — horizontal row of vertical cards (image top, text below)
// Used on both mobile and web
// ═══════════════════════════════════════════════════════════════════════════════

class _AddonCardScroll extends StatelessWidget {
  const _AddonCardScroll({
    required this.addOns,
    required this.selectedIds,
    required this.onToggle,
  });
  final List<AddOnModel> addOns;
  final Set<String> selectedIds;
  final void Function(String, bool) onToggle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: addOns.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _AddonCard(
          addOn: addOns[i],
          isSelected: selectedIds.contains(addOns[i].id),
          onToggle: (sel) => onToggle(addOns[i].id, sel),
        ),
      ),
    );
  }
}

// 110px-wide card: image area on top (70px), name below, price + "+" circle
class _AddonCard extends StatelessWidget {
  const _AddonCard({
    required this.addOn,
    required this.isSelected,
    required this.onToggle,
  });
  final AddOnModel addOn;
  final bool isSelected;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onToggle(!isSelected),
        child: SizedBox(
        width: 160,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Image area ──────────────────────────────────────────────────
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? _kGold : _kBorder,
                  width: isSelected ? 1.5 : 0.8,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Background gradient (always visible behind image)
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFF1ECE1), Color(0xFFE6DED1)],
                        ),
                      ),
                    ),
                    // Service icon (representative visual)
                    const Center(
                      child: Icon(
                        Icons.home_repair_service_rounded,
                        size: 28,
                        color: Color(0xFFB3ADA3),
                      ),
                    ),
                    // Selected overlay
                    if (isSelected)
                      Container(
                        color: _kGold.withAlpha(40),
                        child: const Center(
                          child: Icon(Icons.check_rounded,
                              color: _kGold, size: 28),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 7),

            // ── Name ────────────────────────────────────────────────────────
            Text(
              addOn.name,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _kInk,
                  height: 1.3),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 5),

            // ── Price + "+" toggle ──────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '₹${addOn.price.toInt()}',
                  style: const TextStyle(fontSize: 11, color: _kMuted),
                ),
                const Spacer(),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => onToggle(!isSelected),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: isSelected ? _kInk : const Color(0xFFECE7DE),
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
          ],
        ),
      ),
    ),
  );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Inline AMC plan cards
// ═══════════════════════════════════════════════════════════════════════════════

class _InlineAmcPlans extends ConsumerWidget {
  const _InlineAmcPlans({
    required this.serviceId,
    required this.selectedPlan,
    required this.onPlanSelected,
    this.regularPrice,
  });
  final String serviceId;
  final AmcPlanModel? selectedPlan;
  final void Function(AmcPlanModel?) onPlanSelected;
  final double? regularPrice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amcAsync = ref.watch(amcPlansProvider(serviceId));
    return amcAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (plans) {
        if (plans.isEmpty) return const SizedBox.shrink();
        final visible = plans.take(2).toList();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: visible.asMap().entries.expand((e) {
            final plan = e.value;
            final isSelected = selectedPlan?.id == plan.id;
            final isFirst = e.key == 0;
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
              if (e.key < visible.length - 1) const SizedBox(width: 12),
            ];
          }).toList(),
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
      f.add(plan.discountType == 'percentage'
          ? '✓ ${plan.discountValue.toInt()}% off on repairs'
          : '✓ ₹${plan.discountValue.toInt()} discount');
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
                if (isPopular) const SizedBox(height: 4),
                // Title + indicator
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
                              border: Border.all(
                                  color: _kBorder, width: 1.5),
                            ),
                          ),
                  ],
                ),
                // Feature bullets
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
                  text: TextSpan(children: [
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
                  ]),
                ),
              ],
            ),
          ),
          if (isPopular)
            Positioned(
              top: -9,
              left: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
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
    required this.padH,
    this.isFirst = false,
    this.isLast = false,
  });
  final String label;
  final Widget child;
  final double padH;
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
      padding: EdgeInsets.symmetric(horizontal: widget.padH),
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
// Children list (category nodes)
// ═══════════════════════════════════════════════════════════════════════════════

class _ModalChildrenList extends StatelessWidget {
  const _ModalChildrenList({required this.node, required this.children});
  final CatalogNodeModel node;
  final List<CatalogNodeModel> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Text('Browse ${node.name}',
              style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _kInk)),
        ),
        if (children.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text('Loading…',
                style: TextStyle(color: _kMuted2, fontSize: 13)),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            itemCount: children.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) => _ModalChildItem(
              node: children[i],
              parentNodeId: node.id,
              onTap: () => CatalogNodeModal.open(ctx, children[i],
                  parentId: node.id),
            ),
          ),
      ],
    );
  }
}

class _ModalChildItem extends StatefulWidget {
  const _ModalChildItem({
    required this.node,
    required this.onTap,
    this.parentNodeId,
  });
  final CatalogNodeModel node;
  final VoidCallback onTap;
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
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorder, width: 0.8),
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
            children: [
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
                    color: const Color(0xFFF4A81D).withAlpha(30),
                    alignment: Alignment.center,
                    child: const Icon(Icons.home_repair_service_rounded,
                        size: 26, color: _kGold),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          if (node.isLeafBookable &&
                              node.basePrice != null) ...[
                            Text('₹${node.basePrice!.toInt()}',
                                style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: _kInk)),
                            const SizedBox(width: 3),
                            const Text('onwards',
                                style: TextStyle(
                                    fontSize: 10, color: _kMuted2)),
                          ] else if (node.hasChildren)
                            Text(
                              '${node.childrenCount} '
                              '${node.childrenCount == 1 ? 'option' : 'options'}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: _kMuted),
                            ),
                          if (node.estimatedDuration != null) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.schedule_rounded,
                                size: 11, color: _kMuted2),
                            const SizedBox(width: 2),
                            Text('${node.estimatedDuration} min',
                                style: const TextStyle(
                                    fontSize: 10, color: _kMuted2)),
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
                              padding: const EdgeInsets.only(top: 4),
                              child: _LoyaltyEarnBadge(points: pts),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: const Color(0xFFECE7DE),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.chevron_right_rounded,
                      size: 18, color: _kMuted),
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

class _LoyaltyEarnBadge extends StatelessWidget {
  final int points;
  const _LoyaltyEarnBadge({required this.points});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _kGold.withAlpha(22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kGold.withAlpha(60), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.workspace_premium_rounded,
              size: 10, color: _kGold),
          const SizedBox(width: 3),
          Text('Earn $points Loyalty Points',
              style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: _kGold,
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

class _ModalComingSoon extends StatelessWidget {
  const _ModalComingSoon();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        decoration: BoxDecoration(
          color: _kGold.withAlpha(28),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kGold.withAlpha(60)),
        ),
        child: const Column(
          children: [
            Icon(Icons.schedule_rounded, size: 34, color: _kGold),
            SizedBox(height: 10),
            Text('Coming Soon',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _kInk)),
            SizedBox(height: 6),
            Text(
              'This service is not yet available for booking.\nCheck back soon.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 13, color: _kMuted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Sticky booking bar — gold pill CTA + full AMC duplicate-check logic
// ═══════════════════════════════════════════════════════════════════════════════

class _ModalBookingBar extends ConsumerWidget {
  const _ModalBookingBar({
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
    required this.isWeb,
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
  final bool isWeb;

  Future<void> _addToCart(BuildContext context, WidgetRef ref) async {
    if (amcPlan != null) {
      final activeContract = await CheckoutService().findActiveAmcContract(
        serviceId: node.id,
        planId: amcPlan!.id,
      );
      if (!context.mounted) return;
      if (activeContract != null) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Text('Active AMC Found'),
            content: const Text(
                'You already have an active AMC subscription for this service.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop();
                  context.push(AppRoutes.amcPlans);
                },
                child: const Text('View AMC Plans'),
              ),
            ],
          ),
        );
        return;
      }
    }
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
          isWeb ? 28 : 20, 14, isWeb ? 28 : 20, 16),
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
                      fontSize: isWeb ? 20 : 17,
                      fontWeight: FontWeight.w800,
                      color: _kInk,
                      height: 1.1)),
            ],
          ),
          const SizedBox(width: 14),

          // Gold pill CTA
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
              onTap: inCart
                  ? () => openCart(context)
                  : () => _addToCart(context, ref),
              child: Container(
                padding: EdgeInsets.symmetric(
                    vertical: isWeb ? 13 : 12),
                decoration: BoxDecoration(
                    color: _kInk,
                    borderRadius: BorderRadius.circular(100)),
                child: Center(
                  child: Text(
                    inCart
                        ? '🛒  View Cart'
                        : '🛒  ${amcPlan != null ? 'Book Now' : 'Add to Cart'}',
                    style: GoogleFonts.poppins(
                        fontSize: isWeb ? 14 : 13,
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
