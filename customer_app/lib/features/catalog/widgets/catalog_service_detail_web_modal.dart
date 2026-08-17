import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/faq_model.dart';
import '../../../models/service_attribute_model.dart';
import '../../../models/addon_model.dart';
import '../../address/services/address_providers.dart';
import '../../amc/providers/amc_provider.dart';
import '../../cart/providers/cart_provider.dart';
import '../../cart/services/checkout_service.dart';
import '../../cart/utils/cart_launcher.dart';
import '../../category/services/category_providers.dart';
import '../../reviews/widgets/service_reviews_section.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/utils/auth_modal_gate.dart';
import '../../service/models/customer_question_model.dart';
import '../../service/services/customer_question_providers.dart';
import '../../service/widgets/ask_question_dialog.dart';
import '../../service/widgets/service_attribute_section.dart';
import '../../wishlist/widgets/heart_button.dart';
import '../../../routes/app_router.dart';
import '../models/catalog_node_model.dart';
import '../providers/catalog_providers.dart';
import 'catalog_unavailability_widgets.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CatalogServiceDetailWebModal — 920px two-column service detail dialog.
//
// Layout per design handoff:
//   Header: [320×220 image left (←arrow, heart, 1/1 counter)] | [info right]
//           Absolutely positioned ✕ close at top-right 20px
//   Body (scrollable): attrs → add-ons grid → AMC → about → FAQs → reviews
//   Footer (sticky): price label + gold pill CTA button
// ═══════════════════════════════════════════════════════════════════════════════

class CatalogServiceDetailWebModal extends ConsumerStatefulWidget {
  const CatalogServiceDetailWebModal({
    super.key,
    required this.node,
    this.parentNodeId,
    this.initialCustomerQuestionId,
  });

  final CatalogNodeModel node;
  final String? parentNodeId;
  final String? initialCustomerQuestionId;

  static Future<void> show(
    BuildContext context,
    CatalogNodeModel node, {
    String? parentId,
    String? initialCustomerQuestionId,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: '',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (ctx, _, _) => CatalogServiceDetailWebModal(
        node: node,
        parentNodeId: parentId,
        initialCustomerQuestionId: initialCustomerQuestionId,
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

  @override
  ConsumerState<CatalogServiceDetailWebModal> createState() =>
      _CatalogServiceDetailWebModalState();
}

class _CatalogServiceDetailWebModalState
    extends ConsumerState<CatalogServiceDetailWebModal> {
  final Map<String, String> _selections = {};
  double _priceAdjustment = 0.0;
  final Set<String> _selectedAddonIds = {};
  AmcPlanModel? _selectedAmcPlan;
  final GlobalKey _faqKey = GlobalKey();

  CatalogNodeModel get node => widget.node;

  @override
  void initState() {
    super.initState();
    if (widget.initialCustomerQuestionId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToFaq();
      });
    }
  }

  void _scrollToFaq() {
    final ctx = _faqKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
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
    final attrs =
        ref.watch(serviceAttributesProvider(node.id)).valueOrNull ??
            <ServiceAttributeModel>[];
    final addOns =
        ref.watch(serviceAddonsProvider(node.id)).valueOrNull ?? <AddOnModel>[];
    final faqs =
        ref.watch(catalogNodeFaqsProvider(node.id)).valueOrNull ??
            <FaqModel>[];
    final answeredQuestions =
        ref.watch(answeredCustomerQuestionsProvider(node.id)).valueOrNull ??
            <CustomerQuestionModel>[];
    final showcaseImages =
        ref.watch(serviceShowcaseImagesProvider(node.id)).valueOrNull ?? [];
    final isAuthenticated = ref.watch(isAuthenticatedProvider);

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

    return Stack(
      children: [
        // ── Blurred dimmed backdrop ────────────────────────────────────────
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: const ColoredBox(color: Color(0x70000000)),
            ),
          ),
        ),

        // ── Modal card ─────────────────────────────────────────────────────
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 920,
                maxHeight: MediaQuery.of(context).size.height * 0.90,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 20),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(80),
                          blurRadius: 60,
                          offset: const Offset(0, 20),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          // ── Two-column header ────────────────────────────
                          _WebDetailHeader(
                            node: node,
                            displayPrice: displayPrice,
                            hasAdjustment: hasAdjustment,
                            onClose: () => Navigator.of(context).pop(),
                          ),

                          const Divider(height: 1, color: AppColors.divider),

                          // ── Scrollable body ──────────────────────────────
                          Flexible(
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(context)
                                  .copyWith(scrollbars: false),
                              child: SingleChildScrollView(
                                padding:
                                    const EdgeInsets.only(bottom: 8),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    // Attribute selection
                                    if (attrs.isNotEmpty)
                                      ServiceAttributeSection(
                                        attrs: attrs,
                                        selections: _selections,
                                        onChanged: (id, opt) =>
                                            _onOptionSelected(
                                                id, opt, attrs),
                                      ),

                                    // Add-ons — 4-col grid section
                                    if (addOns.isNotEmpty)
                                      _WebAddonsSection(
                                        addOns: addOns,
                                        selectedIds: _selectedAddonIds,
                                        onToggle: _onAddonToggled,
                                      ),

                                    // AMC / unavailability
                                    if (isUnavailable || isEffectivelyHidden)
                                      CatalogUnavailabilityBanner(
                                        message: isUnavailable
                                            ? avail?.message
                                            : null,
                                        isHidden: isEffectivelyHidden,
                                      )
                                    else
                                      _WebAmcInlineSection(
                                        serviceId: node.id,
                                        selectedPlan: _selectedAmcPlan,
                                        onPlanSelected: (plan) =>
                                            setState(() {
                                          _selectedAmcPlan = plan;
                                        }),
                                      ),

                                    // About this service
                                    if (node.description?.isNotEmpty ==
                                        true)
                                      _WebAccordionSection(
                                        title: 'About this service',
                                        child: _WebAboutSection(node: node),
                                      ),

                                    // FAQs (direct Q&A pairs + Ask us inside)
                                    if (faqs.isNotEmpty ||
                                        answeredQuestions.isNotEmpty)
                                      _WebAccordionSection(
                                        key: _faqKey,
                                        title: 'FAQs',
                                        initiallyExpanded:
                                            widget.initialCustomerQuestionId !=
                                                null,
                                        child: _WebFaqContentSection(
                                          faqs: faqs,
                                          answeredQuestions: answeredQuestions,
                                          serviceId: node.id,
                                          serviceName: node.name,
                                          isAuthenticated: isAuthenticated,
                                          highlightQuestionId:
                                              widget.initialCustomerQuestionId,
                                        ),
                                      ),

                                    // Before & After showcase (Admin-published only)
                                    if (showcaseImages.isNotEmpty)
                                      _WebAccordionSection(
                                        title: 'Before & After',
                                        child: _WebBeforeAfterContent(
                                          images: showcaseImages,
                                        ),
                                      ),

                                    // Reviews
                                    _WebAccordionSection(
                                      title: node.reviewCount > 0
                                          ? 'Reviews (${node.reviewCount})'
                                          : 'Reviews',
                                      child: ServiceReviewsSection(
                                        serviceId: node.id,
                                        padding: const EdgeInsets.fromLTRB(
                                            28, 8, 28, 16),
                                      ),
                                    ),

                                    const SizedBox(height: 8),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // ── Sticky booking bar ───────────────────────────
                          if (isUnavailable || isEffectivelyHidden)
                            CatalogUnavailabilityBar(
                              message:
                                  isUnavailable ? avail?.message : null,
                            )
                          else
                            _WebDetailBookingBar(
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

// ── Two-column header (image left · info right · absolute close) ──────────────

class _WebDetailHeader extends StatelessWidget {
  const _WebDetailHeader({
    required this.node,
    required this.displayPrice,
    required this.hasAdjustment,
    required this.onClose,
  });

  final CatalogNodeModel node;
  final double displayPrice;
  final bool hasAdjustment;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final imageUrl = node.imageUrl;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ── Row: image + info ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(28),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Left: service image ──────────────────────────────────────
              SizedBox(
                width: 320,
                height: 220,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      hasImage
                          ? Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              loadingBuilder: (_, child, p) => p == null
                                  ? child
                                  : const ColoredBox(
                                      color: Color(0xFFEEEEEE)),
                              errorBuilder: (_, _, _) =>
                                  const _ServiceImagePlaceholder(),
                            )
                          : const _ServiceImagePlaceholder(),

                      // Heart button (top-right of image)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: HeartButton(serviceId: node.id, mini: true),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 28),

              // ── Right: info (padding-right leaves room for close button) ─
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category pill
                      if (node.parentName != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            node.parentName!,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),

                      const SizedBox(height: 10),

                      // Service title
                      Text(
                        node.name,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          height: 1.2,
                        ),
                      ),

                      // Rating + review count
                      if (node.rating > 0) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
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
                                '(${node.reviewCount} reviews)',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ],
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
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textHint,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '₹${displayPrice.toInt()}',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                                height: 1.0,
                              ),
                            ),
                            if (hasAdjustment) ...[
                              const SizedBox(width: 6),
                              const Text(
                                'incl. adjustments',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textHint,
                                ),
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
        ),

        // ── Absolutely positioned ✕ close button (top-right of header) ───
        Positioned(
          top: 20,
          right: 20,
          child: GestureDetector(
            onTap: onClose,
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 16,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Image placeholder ─────────────────────────────────────────────────────────

class _ServiceImagePlaceholder extends StatelessWidget {
  const _ServiceImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.goldLight,
      alignment: Alignment.center,
      child: const Icon(
        Icons.home_repair_service_rounded,
        size: 60,
        color: AppColors.gold,
      ),
    );
  }
}

// ── Add-ons section — 4-col grid with border-bottom separator ─────────────────

class _WebAddonsSection extends StatelessWidget {
  const _WebAddonsSection({
    super.key,
    required this.addOns,
    required this.selectedIds,
    required this.onToggle,
  });

  final List<AddOnModel> addOns;
  final Set<String> selectedIds;
  final void Function(String, bool) onToggle;

  @override
  Widget build(BuildContext context) {
    if (addOns.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section heading + View all
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text(
                'Suggested Add-ons',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                'View all →',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.goldDeep,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Responsive grid
          LayoutBuilder(
            builder: (context, constraints) {
              final cols =
                  (constraints.maxWidth / 200).floor().clamp(2, 4);
              final itemWidth =
                  (constraints.maxWidth - (cols - 1) * 16) / cols;
              return Wrap(
                spacing: 16,
                runSpacing: 12,
                children: addOns
                    .map((a) => SizedBox(
                          width: itemWidth,
                          height: 44,
                          child: _WebAddonItem(
                            addOn: a,
                            isSelected: selectedIds.contains(a.id),
                            onToggle: (sel) => onToggle(a.id, sel),
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _WebAddonItem extends StatelessWidget {
  const _WebAddonItem({
    required this.addOn,
    required this.isSelected,
    required this.onToggle,
  });

  final AddOnModel addOn;
  final bool isSelected;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onToggle(!isSelected),
      child: Row(
        children: [
          // 44×44 icon box
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.goldLight
                  : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? AppColors.gold : AppColors.border,
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Icon(
              Icons.home_repair_service_rounded,
              size: 22,
              color: isSelected ? AppColors.gold : AppColors.textHint,
            ),
          ),
          const SizedBox(width: 10),
          // Name + price
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  addOn.name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '₹${addOn.price.toInt()}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Toggle circle (+ / ✓)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color:
                  isSelected ? AppColors.gold : AppColors.surfaceVariant,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSelected ? Icons.check_rounded : Icons.add_rounded,
              size: 13,
              color: isSelected ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── AMC inline section — plan cards directly in the modal body ────────────────

class _WebAmcInlineSection extends ConsumerWidget {
  const _WebAmcInlineSection({
    super.key,
    required this.serviceId,
    required this.selectedPlan,
    required this.onPlanSelected,
  });

  final String serviceId;
  final AmcPlanModel? selectedPlan;
  final void Function(AmcPlanModel?) onPlanSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans =
        ref.watch(amcPlansProvider(serviceId)).valueOrNull ?? [];
    if (plans.isEmpty) return const SizedBox.shrink();

    final first2 = plans.take(2).toList();

    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text(
                'AMC Plans',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
              if (plans.length > 2)
                Text(
                  'View all →',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.goldDeep,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (first2.length == 1)
            _AmcPlanCard(
              plan: first2.first,
              isPopular: true,
              isSelected: selectedPlan?.id == first2.first.id,
              onTap: () => onPlanSelected(
                selectedPlan?.id == first2.first.id ? null : first2.first,
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _AmcPlanCard(
                    plan: first2[0],
                    isPopular: true,
                    isSelected: selectedPlan?.id == first2[0].id,
                    onTap: () => onPlanSelected(
                      selectedPlan?.id == first2[0].id ? null : first2[0],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _AmcPlanCard(
                    plan: first2[1],
                    isPopular: false,
                    isSelected: selectedPlan?.id == first2[1].id,
                    onTap: () => onPlanSelected(
                      selectedPlan?.id == first2[1].id ? null : first2[1],
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ── AMC plan card ─────────────────────────────────────────────────────────────

class _AmcPlanCard extends StatelessWidget {
  const _AmcPlanCard({
    required this.plan,
    required this.isPopular,
    required this.isSelected,
    required this.onTap,
  });

  final AmcPlanModel plan;
  final bool isPopular;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.fromLTRB(14, isPopular ? 20 : 14, 14, 14),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.goldLight : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppColors.gold : AppColors.border,
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        plan.name,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.border,
                          width: 1.5,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check_rounded,
                              size: 11, color: Colors.white)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _PlanFeatureLine(
                    '${plan.numVisits} visits / ${plan.packageDurationLabel}'),
                const SizedBox(height: 4),
                const _PlanFeatureLine('Priority scheduling'),
                if (plan.discountValue > 0) ...[
                  const SizedBox(height: 4),
                  _PlanFeatureLine(
                    plan.discountType == 'percentage'
                        ? '${plan.discountValue.toInt()}% off per visit'
                        : '₹${plan.discountValue.toInt()} off per visit',
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '₹${plan.finalPrice.toInt()}',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '/ ${plan.packageDurationLabel}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (isPopular)
          Positioned(
            top: -9,
            left: 14,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.gold,
                borderRadius: BorderRadius.circular(100),
              ),
              child: const Text(
                'Popular',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Plan feature bullet ───────────────────────────────────────────────────────

class _PlanFeatureLine extends StatelessWidget {
  const _PlanFeatureLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '✓ ',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.gold,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Web accordion section (FAQs, Reviews) ─────────────────────────────────────

class _WebAccordionSection extends StatelessWidget {
  const _WebAccordionSection({
    super.key,
    required this.title,
    required this.child,
    this.initiallyExpanded = false,
  });

  final String title;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
          childrenPadding: EdgeInsets.zero,
          title: Text(
            title,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
          ),
          children: [child],
        ),
      ),
    );
  }
}

// ── Web customer Q&A section ──────────────────────────────────────────────────

class _WebFaqContentSection extends StatelessWidget {
  const _WebFaqContentSection({
    required this.faqs,
    required this.answeredQuestions,
    required this.serviceId,
    required this.serviceName,
    required this.isAuthenticated,
    this.highlightQuestionId,
  });

  final List<FaqModel> faqs;
  final List<CustomerQuestionModel> answeredQuestions;
  final String serviceId;
  final String serviceName;
  final bool isAuthenticated;
  final String? highlightQuestionId;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Predefined FAQs
          ...faqs.map((f) => Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 12),
                  title: Text(
                    f.question,
                    textAlign: TextAlign.left,
                    style: tt.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: AppColors.textHint,
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        f.answer,
                        textAlign: TextAlign.left,
                        style: tt.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              )),

          // Customer answered questions — tap to expand and reveal Admin's answer.
          // The target question from a notification starts expanded.
          ...answeredQuestions.map((q) {
            final isTarget =
                highlightQuestionId != null && q.id == highlightQuestionId;
            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              decoration: isTarget
                  ? BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    )
                  : null,
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: isTarget,
                  tilePadding: isTarget
                      ? const EdgeInsets.symmetric(horizontal: 12)
                      : EdgeInsets.zero,
                  childrenPadding: isTarget
                      ? const EdgeInsets.fromLTRB(12, 0, 12, 12)
                      : const EdgeInsets.only(bottom: 12),
                  title: Text(
                    q.question,
                    textAlign: TextAlign.left,
                    style: tt.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: AppColors.textHint,
                  ),
                  children: [
                    if (q.answer?.isNotEmpty == true)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          q.answer!,
                          textAlign: TextAlign.left,
                          style: tt.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 8),

          // "Have a question? Ask us" row inside FAQs
          _WebAskQuestionRow(
            serviceId: serviceId,
            serviceName: serviceName,
            isAuthenticated: isAuthenticated,
          ),
        ],
      ),
    );
  }
}

// ── Web ask a question row ────────────────────────────────────────────────────

class _WebAskQuestionRow extends ConsumerWidget {
  const _WebAskQuestionRow({
    required this.serviceId,
    required this.serviceName,
    required this.isAuthenticated,
  });

  final String serviceId;
  final String serviceName;
  final bool isAuthenticated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          if (!isAuthenticated) {
            final authed = await requireAuth(context, ref);
            if (!authed || !context.mounted) return;
          }
          if (context.mounted) {
            AskQuestionDialog.show(
              context,
              serviceId: serviceId,
              serviceName: serviceName,
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.help_outline_rounded,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isAuthenticated
                      ? 'Have a question? Ask us'
                      : 'Sign in to ask a question',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}

// ── About this service section ────────────────────────────────────────────────

class _WebAboutSection extends StatelessWidget {
  const _WebAboutSection({required this.node});
  final CatalogNodeModel node;

  @override
  Widget build(BuildContext context) {
    if (node.description?.isNotEmpty != true) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          node.description!,
          textAlign: TextAlign.left,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            height: 1.6,
          ),
        ),
      ),
    );
  }
}

// ── Sticky booking bar ─────────────────────────────────────────────────────────

class _WebDetailBookingBar extends ConsumerWidget {
  const _WebDetailBookingBar({
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
          amcQuantity: 1,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inCart =
        ref.watch(cartProvider).any((item) => item.serviceId == node.id);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(
            top: BorderSide(color: AppColors.border, width: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(12),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 18, 28, 18),
        child: Row(
          children: [
            // Price display
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'From',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textHint),
                ),
                Text(
                  '₹${displayPrice.toInt()}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    height: 1.1,
                  ),
                ),
                Text(
                  amcPlan != null
                      ? 'AMC · ${amcPlan!.numVisits} visits'
                      : (priceAdjustment > 0 || addonsTotal > 0)
                          ? 'incl. adjustments'
                          : 'onwards',
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textHint),
                ),
              ],
            ),

            const Spacer(),

            // CTA button — fixed-size pill.
            // minimumSize: Size.zero + shrinkWrap prevent the button from
            // claiming infinite width when measured in the first pass of a
            // Row that contains a Spacer (Flexible child).
            inCart
                ? FilledButton.icon(
                    onPressed: () => openCart(context),
                    icon: const Icon(Icons.shopping_cart_rounded, size: 16),
                    label: const Text(
                      'View Cart',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 13),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                  )
                : FilledButton.icon(
                    onPressed: () => _addToCart(context, ref),
                    icon: const Icon(Icons.add_shopping_cart_rounded,
                        size: 16),
                    label: Text(
                      amcPlan != null ? 'Book Now' : 'Add to Cart',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 13),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

// ── Web Before & After showcase ───────────────────────────────────────────────

class _WebBeforeAfterContent extends StatelessWidget {
  final List<Map<String, dynamic>> images;
  const _WebBeforeAfterContent({required this.images});

  @override
  Widget build(BuildContext context) {
    final before = images.where((i) => i['image_type'] == 'before').toList();
    final after = images.where((i) => i['image_type'] == 'after').toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (before.isNotEmpty)
            SizedBox(width: 140, child: _WebShowcasePhotoRow(label: 'Before', photos: before)),
          if (before.isNotEmpty && after.isNotEmpty) const SizedBox(width: 16),
          if (after.isNotEmpty)
            SizedBox(width: 140, child: _WebShowcasePhotoRow(label: 'After', photos: after)),
        ],
      ),
    );
  }
}

class _WebShowcasePhotoRow extends StatelessWidget {
  final String label;
  final List<Map<String, dynamic>> photos;
  const _WebShowcasePhotoRow({required this.label, required this.photos});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: tt.labelSmall?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 140,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final url = photos[i]['image_url'] as String;
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  url,
                  width: 140,
                  height: 140,
                  fit: BoxFit.cover,
                  loadingBuilder: (ctx, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      width: 140,
                      height: 140,
                      color: AppColors.background,
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  },
                  errorBuilder: (_, _, _) => Container(
                    width: 140,
                    height: 140,
                    color: AppColors.background,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.textHint,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
