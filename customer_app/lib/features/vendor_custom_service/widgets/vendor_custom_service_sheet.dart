import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/faq_model.dart';
import '../../../models/service_attribute_model.dart';
import '../../cart/providers/cart_provider.dart';
import '../../cart/utils/cart_launcher.dart';
import '../../catalog/providers/catalog_providers.dart';
import '../../category/services/category_providers.dart';
import '../../reviews/services/review_providers.dart';
import '../../catalog/widgets/warranty_badge.dart';
import '../../service/widgets/faq_section.dart';
import '../models/vendor_custom_service_model.dart';

// Same design tokens as catalog_node_screen.dart
const _kInk = Color(0xFF1A1714);
const _kMuted = Color(0xFF6E6A64);
const _kMuted2 = Color(0xFF9A948C);
const _kGold = Color(0xFFF4A81D);
const _kBorder = Color(0xFFECE7DE);
const _kBg = Color(0xFFFBF8F3);

// ── Entry point (kept for existing call sites) ────────────────────────────────

class VendorCustomServiceSheet {
  const VendorCustomServiceSheet._();

  static void show(BuildContext context, VendorCustomServiceModel service) {
    if (MediaQuery.of(context).size.width >= 768) {
      showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierLabel: '',
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (ctx, _, _) => Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                behavior: HitTestBehavior.opaque,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: const ColoredBox(color: Color(0x70000000)),
                ),
              ),
            ),
            VendorCustomServiceScreen(service: service, inModal: true),
          ],
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
    } else {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) =>
            VendorCustomServiceScreen(service: service, inSheet: true),
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// VendorCustomServiceScreen
// Mirrors CatalogNodeScreen exactly — same layout, tokens, and patterns.
// Wired to VendorCustomServiceModel instead of CatalogNodeModel.
// ═══════════════════════════════════════════════════════════════════════════════

class VendorCustomServiceScreen extends ConsumerStatefulWidget {
  const VendorCustomServiceScreen({
    super.key,
    required this.service,
    this.inModal = false,
    this.inSheet = false,
  });

  final VendorCustomServiceModel service;

  /// True when opened via showGeneralDialog on web (920px card over blurred backdrop).
  final bool inModal;

  /// True when opened via showModalBottomSheet (draggable bottom sheet body).
  final bool inSheet;

  @override
  ConsumerState<VendorCustomServiceScreen> createState() =>
      _VendorCustomServiceScreenState();
}

class _VendorCustomServiceScreenState
    extends ConsumerState<VendorCustomServiceScreen> {
  String? _selectedAttrId;
  final Map<String, int> _quantities = {};

  VendorCustomServiceModel get service => widget.service;

  int _qtyFor(String attrId) => _quantities[attrId] ?? 1;

  void _setQty(String attrId, int qty) {
    if (qty < 1) return;
    setState(() => _quantities[attrId] = qty);
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.sizeOf(context).width >= 768;
    final faqs =
        ref.watch(customServiceFaqsProvider(service.id)).valueOrNull ?? [];
    final attrs =
        ref.watch(serviceAttributesProvider(service.id)).valueOrNull ?? [];
    final attrEntries = attrs.where((a) => a.options.isNotEmpty).toList();
    // Auto-select the cheapest attr so "From ₹X" and the initial booking-bar
    // price always show the minimum variant price.
    final cheapestAttrId = attrEntries.isNotEmpty
        ? attrEntries
            .reduce((a, b) =>
                a.options.first.finalPrice <= b.options.first.finalPrice ? a : b)
            .id
        : null;
    final effectiveAttrId = _selectedAttrId ?? cheapestAttrId;
    final selectedAttr = effectiveAttrId != null
        ? attrEntries.where((a) => a.id == effectiveAttrId).firstOrNull
        : null;
    final effectiveUnitPrice = selectedAttr != null
        ? selectedAttr.options.first.finalPrice
        : service.activePrice;
    final effectiveQty =
        effectiveAttrId != null ? _qtyFor(effectiveAttrId) : 1;

    // Minimum price across all attrs — displayed as "From ₹X" in the header.
    final fromPrice = attrEntries.isNotEmpty
        ? attrEntries
            .map((a) => a.options.first.finalPrice)
            .fold(double.infinity, (a, b) => a < b ? a : b)
        : service.activePrice;

    void onAttrSelected(String id) => setState(() => _selectedAttrId = id);

    if (isWeb) {
      return _WebScaffold(
        service: service,
        faqs: faqs,
        inModal: widget.inModal,
        attrEntries: attrEntries,
        selectedAttrId: effectiveAttrId,
        onAttrSelected: onAttrSelected,
        quantities: _quantities,
        onQtyChanged: _setQty,
        effectiveUnitPrice: effectiveUnitPrice,
        fromPrice: fromPrice,
      );
    }

    // ── Mobile bottom-sheet mode ─────────────────────────────────────────────
    if (widget.inSheet) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        child: Material(
          color: _kBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle + close button
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 12, 8),
                  child: Row(
                    children: [
                      const Spacer(),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDDD8D0),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).maybePop(),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceVariant,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close_rounded,
                                  size: 18, color: _kInk),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Scrollable content
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (service.imageUrl?.isNotEmpty == true)
                          _SheetHero(imageUrl: service.imageUrl!),
                        _ServiceContentBlock(service: service, fromPrice: fromPrice),
                        if (attrEntries.isNotEmpty)
                          _AttributeVariantSection(
                            attrs: attrEntries,
                            selectedAttrId: effectiveAttrId,
                            onAttrSelected: onAttrSelected,
                            quantities: _quantities,
                            onQtyChanged: _setQty,
                          ),
                        if (service.includedItems.isNotEmpty)
                          _IncludedSection(items: service.includedItems),
                        if (service.excludedItems.isNotEmpty)
                          _ExcludedSection(items: service.excludedItems),
                        if (service.beforeAfterPairs.isNotEmpty)
                          _BeforeAfterSection(pairs: service.beforeAfterPairs),
                        const SizedBox(height: 24),
                        _AccordionSection(
                          label: 'About this service',
                          isFirst: true,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(0, 4, 0, 14),
                            child: Text(
                              service.description?.isNotEmpty == true
                                  ? service.description!
                                  : 'No description available.',
                              style: const TextStyle(
                                  fontSize: 13, color: _kMuted, height: 1.6),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                          child: Text(
                            'FAQs',
                            style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: _kInk),
                          ),
                        ),
                        if (faqs.isEmpty)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
                            child: Text('No FAQs yet.',
                                style: TextStyle(
                                    fontSize: 13, color: _kMuted)),
                          )
                        else
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 20),
                            child: FaqSection(faqs: faqs),
                          ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
                          child: SizedBox.shrink(),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 20, bottom: 12),
                          child: AskQuestionLink(
                            customServiceId: service.id,
                            vendorId: service.vendorId,
                            serviceName: service.serviceName,
                          ),
                        ),
                        _AccordionSection(
                          label: service.reviewCount > 0
                              ? 'Reviews (${service.reviewCount})'
                              : 'Reviews',
                          isLast: true,
                          child: _InlineReviews(customServiceId: service.id),
                        ),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
                // Sticky booking bar
                _MobileBookingBar(
                  service: service,
                  effectiveUnitPrice: effectiveUnitPrice,
                  effectiveQty: effectiveQty,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ── Mobile full-screen (fallback) ────────────────────────────────────────
    return Scaffold(
      backgroundColor: _kBg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (service.imageUrl?.isNotEmpty == true)
                  _MobileHero(imageUrl: service.imageUrl!),
                _ServiceContentBlock(service: service, fromPrice: fromPrice),
                if (attrEntries.isNotEmpty)
                  _AttributeVariantSection(
                    attrs: attrEntries,
                    selectedAttrId: effectiveAttrId,
                    onAttrSelected: onAttrSelected,
                    quantities: _quantities,
                    onQtyChanged: _setQty,
                  ),
                if (service.includedItems.isNotEmpty)
                  _IncludedSection(items: service.includedItems),
                if (service.excludedItems.isNotEmpty)
                  _ExcludedSection(items: service.excludedItems),
                if (service.beforeAfterPairs.isNotEmpty)
                  _BeforeAfterSection(pairs: service.beforeAfterPairs),
                const SizedBox(height: 24),
                _AccordionSection(
                  label: 'About this service',
                  isFirst: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 4, 0, 14),
                    child: Text(
                      service.description?.isNotEmpty == true
                          ? service.description!
                          : 'No description available.',
                      style: const TextStyle(
                          fontSize: 13, color: _kMuted, height: 1.6),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Text(
                    'FAQs',
                    style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _kInk),
                  ),
                ),
                if (faqs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: Text('No FAQs yet.',
                        style: TextStyle(fontSize: 13, color: _kMuted)),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: FaqSection(faqs: faqs),
                  ),
                Padding(
                  padding: const EdgeInsets.only(left: 20, top: 8, bottom: 12),
                  child: AskQuestionLink(
                    customServiceId: service.id,
                    vendorId: service.vendorId,
                    serviceName: service.serviceName,
                  ),
                ),
                _AccordionSection(
                  label: service.reviewCount > 0
                      ? 'Reviews (${service.reviewCount})'
                      : 'Reviews',
                  isLast: true,
                  child: _InlineReviews(customServiceId: service.id),
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _MobileBookingBar(
        service: service,
        effectiveUnitPrice: effectiveUnitPrice,
        effectiveQty: effectiveQty,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Web scaffold — mirrors CatalogNodeScreen._WebScaffold
// ═══════════════════════════════════════════════════════════════════════════════

class _WebScaffold extends ConsumerWidget {
  const _WebScaffold({
    required this.service,
    required this.faqs,
    required this.inModal,
    required this.attrEntries,
    required this.selectedAttrId,
    required this.onAttrSelected,
    required this.quantities,
    required this.onQtyChanged,
    required this.effectiveUnitPrice,
    required this.fromPrice,
  });

  final VendorCustomServiceModel service;
  final List<FaqModel> faqs;
  final bool inModal;
  final List<ServiceAttributeModel> attrEntries;
  final String? selectedAttrId;
  final ValueChanged<String> onAttrSelected;
  final Map<String, int> quantities;
  final void Function(String, int) onQtyChanged;
  final double effectiveUnitPrice;
  final double fromPrice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final cartItem =
        cart.where((i) => i.customServiceId == service.id).firstOrNull;
    final inCart = cartItem != null;
    final hasVariants = attrEntries.isNotEmpty;
    final effectiveQty =
        selectedAttrId != null ? (quantities[selectedAttrId] ?? 1) : 1;
    // When variants present, use variant-driven qty/price; otherwise fall back
    // to the cart qty so the web stepper stays in sync.
    final cartQty = cartItem?.quantity ?? 1;
    final displayQty = hasVariants ? effectiveQty : cartQty;
    final displayUnitPrice =
        hasVariants ? effectiveUnitPrice : service.activePrice;

    final screenH = MediaQuery.sizeOf(context).height;

    final cardDecoration = BoxDecoration(
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
    );

    final header = _WebHeader(
      service: service,
      fromPrice: fromPrice,
      onClose: () => Navigator.of(context).maybePop(),
    );

    final attrsSection = attrEntries.isNotEmpty
        ? _AttributeVariantSection(
            attrs: attrEntries,
            selectedAttrId: selectedAttrId,
            onAttrSelected: onAttrSelected,
            horizontalPadding: 28,
            quantities: quantities,
            onQtyChanged: onQtyChanged,
          )
        : null;

    final middle = Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('About this service',
              style: GoogleFonts.poppins(
                  fontSize: 15, fontWeight: FontWeight.w700, color: _kInk)),
          const SizedBox(height: 10),
          Text(
            service.description?.isNotEmpty == true
                ? service.description!
                : 'No description available.',
            style: const TextStyle(fontSize: 13, color: _kMuted, height: 1.6),
          ),
          if (service.includedItems.isNotEmpty) ...[
            const SizedBox(height: 4),
            _IncludedSection(items: service.includedItems),
          ],
          if (service.excludedItems.isNotEmpty)
            _ExcludedSection(items: service.excludedItems),
          if (service.beforeAfterPairs.isNotEmpty)
            _BeforeAfterSection(pairs: service.beforeAfterPairs),
          const SizedBox(height: 18),
          Text('FAQs',
              style: GoogleFonts.poppins(
                  fontSize: 15, fontWeight: FontWeight.w700, color: _kInk)),
          const SizedBox(height: 12),
          if (faqs.isEmpty)
            const Text('No FAQs yet.',
                style: TextStyle(fontSize: 13, color: _kMuted))
          else
            FaqSection(faqs: faqs),
          const SizedBox(height: 8),
          AskQuestionLink(
            customServiceId: service.id,
            vendorId: service.vendorId,
            serviceName: service.serviceName,
          ),
          const SizedBox(height: 16),
          Text(
            service.reviewCount > 0
                ? 'Reviews (${service.reviewCount})'
                : 'Reviews',
            style: GoogleFonts.poppins(
                fontSize: 15, fontWeight: FontWeight.w700, color: _kInk),
          ),
          const SizedBox(height: 12),
          _InlineReviews(customServiceId: service.id),
          const SizedBox(height: 16),
        ],
      ),
    );

    final footer = Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
      decoration:
          const BoxDecoration(border: Border(top: BorderSide(color: _kBorder))),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(inCart ? 'Total' : 'From',
                  style: const TextStyle(fontSize: 11, color: _kMuted2)),
              Text(
                '₹${(displayUnitPrice * displayQty).toInt()}',
                style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _kInk,
                    height: 1.1),
              ),
            ],
          ),
          const Spacer(),
          // When no variants: show cart qty stepper when in-cart (classic behavior).
          // When variants: chip stepper handles qty — no duplicate stepper here.
          if (inCart && !hasVariants) ...[
            _WebQtyStepper(
              quantity: cartQty,
              onDecrement: () => ref
                  .read(cartProvider.notifier)
                  .updateQuantity(cartItem.bookingId, cartQty - 1),
              onIncrement: () => ref
                  .read(cartProvider.notifier)
                  .updateQuantity(cartItem.bookingId, cartQty + 1),
            ),
            const SizedBox(width: 12),
          ],
          if (inCart && !hasVariants)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 13),
                  decoration: BoxDecoration(
                      color: _kInk,
                      borderRadius: BorderRadius.circular(100)),
                  child: Text(
                    'Done',
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                  ),
                ),
              ),
            )
          else
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => ref
                    .read(cartProvider.notifier)
                    .addCustomServiceToCart(
                      service,
                      unitPrice: hasVariants ? effectiveUnitPrice : null,
                      quantity: hasVariants ? effectiveQty : 1,
                    ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 13),
                  decoration: BoxDecoration(
                      color: _kInk,
                      borderRadius: BorderRadius.circular(100)),
                  child: Text(
                    inCart ? '🛒  Update Cart' : '🛒  Add to Cart',
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
    );

    if (inModal) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(maxWidth: 920, maxHeight: screenH - 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 20),
                child: Stack(
                  children: [
                    Container(
                      decoration: cardDecoration,
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  header,
                                  ?attrsSection,
                                  middle,
                                ],
                              ),
                            ),
                          ),
                          footer,
                        ],
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).maybePop(),
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
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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
                  decoration: cardDecoration,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header,
                      ?attrsSection,
                      middle,
                      footer,
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
// Web header: 320×220 image | vendor pill + name + rating + description + price
// Mirrors CatalogNodeScreen._WebHeader exactly
// ═══════════════════════════════════════════════════════════════════════════════

class _WebHeader extends StatelessWidget {
  const _WebHeader({
    required this.service,
    required this.fromPrice,
    required this.onClose,
  });
  final VendorCustomServiceModel service;
  final double fromPrice;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final imageUrl = service.imageUrl;
    final hasImage = imageUrl?.isNotEmpty == true;

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _kBorder))),
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo panel — 320×220 with back arrow overlay
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 320,
                  height: 220,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      hasImage
                          ? Image.network(
                              imageUrl!,
                              fit: BoxFit.cover,
                              loadingBuilder: (_, child, p) => p == null
                                  ? child
                                  : const ColoredBox(
                                      color: Color(0xFFEAE3D4)),
                              errorBuilder: (_, _, _) => const _StripedBox(),
                            )
                          : const _StripedBox(),
                      Positioned(
                        top: 12,
                        left: 12,
                        child: _CircleNavBtn(
                            icon: Icons.arrow_back_rounded, onTap: onClose),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 28),

              // Info panel
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 44),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Vendor name as category pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                            color: _kInk,
                            borderRadius: BorderRadius.circular(100)),
                        child: Text(
                          service.vendorName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Service name
                      Text(
                        service.serviceName,
                        style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: _kInk,
                            height: 1.2),
                      ),
                      const SizedBox(height: 8),

                      // Rating row
                      if (service.rating > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              const Text('★',
                                  style: TextStyle(
                                      color: _kGold, fontSize: 13)),
                              const SizedBox(width: 4),
                              Text(
                                service.rating.toStringAsFixed(1),
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _kInk),
                              ),
                              if (service.reviewCount > 0) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '(${service.reviewCount} reviews)',
                                  style: const TextStyle(
                                      fontSize: 13, color: _kMuted2),
                                ),
                              ],
                            ],
                          ),
                        ),

                      // Description
                      if (service.description?.isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Text(
                            service.description!,
                            style: const TextStyle(
                                fontSize: 13, color: _kMuted, height: 1.6),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                      // Price — always shows the lowest variant price
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          const Text('From',
                              style: TextStyle(
                                  fontSize: 13, color: _kMuted2)),
                          const SizedBox(width: 8),
                          Text(
                            '₹${fromPrice.toInt()}',
                            style: GoogleFonts.poppins(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: _kInk,
                                height: 1.0),
                          ),
                        ],
                      ),
                      if (service.warrantyEnabled && service.warrantyDays != null) ...[
                        const SizedBox(height: 10),
                        WarrantyBadge(
                          warrantyDays: service.warrantyDays!,
                          warrantyCovers: service.warrantyCovers,
                          warrantyExclusions: service.warrantyExclusions,
                        ),
                      ],
                    ],
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

// ═══════════════════════════════════════════════════════════════════════════════
// Service content block — below hero on mobile/sheet
// vendor pill → name → rating → description → price
// Mirrors CatalogNodeScreen._ServiceContentBlock
// ═══════════════════════════════════════════════════════════════════════════════

class _ServiceContentBlock extends StatelessWidget {
  const _ServiceContentBlock({required this.service, required this.fromPrice});
  final VendorCustomServiceModel service;
  final double fromPrice;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: _kInk, borderRadius: BorderRadius.circular(100)),
            child: Text(
              service.vendorName,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.3),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            service.serviceName,
            style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _kInk,
                height: 1.2),
          ),
          const SizedBox(height: 6),
          if (service.rating > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Text('★',
                      style: TextStyle(color: _kGold, fontSize: 13)),
                  const SizedBox(width: 4),
                  Text(
                    service.rating.toStringAsFixed(1),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _kInk),
                  ),
                  if (service.reviewCount > 0) ...[
                    const SizedBox(width: 4),
                    Text('(${service.reviewCount} reviews)',
                        style: const TextStyle(
                            fontSize: 13, color: _kMuted2)),
                  ],
                ],
              ),
            ),
          if (service.description?.isNotEmpty == true) ...[
            Text(service.description!,
                style:
                    const TextStyle(fontSize: 13, color: _kMuted, height: 1.6)),
            const SizedBox(height: 14),
          ] else
            const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text('From',
                  style: TextStyle(fontSize: 13, color: _kMuted2)),
              const SizedBox(width: 8),
              Text(
                '₹${fromPrice.toInt()}',
                style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _kInk,
                    height: 1.0),
              ),
            ],
          ),
          if (service.warrantyEnabled && service.warrantyDays != null) ...[
            const SizedBox(height: 10),
            WarrantyBadge(
              warrantyDays: service.warrantyDays!,
              warrantyCovers: service.warrantyCovers,
              warrantyExclusions: service.warrantyExclusions,
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Sheet hero — 220px image (used in inSheet mode)
// Mirrors CatalogNodeScreen._SheetHero
// ═══════════════════════════════════════════════════════════════════════════════

class _SheetHero extends StatelessWidget {
  const _SheetHero({required this.imageUrl});
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            imageUrl,
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
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Mobile hero — 260px image (full-screen non-sheet mode)
// Mirrors CatalogNodeScreen._MobileHero (simplified: no heart button)
// ═══════════════════════════════════════════════════════════════════════════════

class _MobileHero extends StatelessWidget {
  const _MobileHero({required this.imageUrl});
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final statusBarH = MediaQuery.of(context).padding.top;
    return SizedBox(
      height: statusBarH + 260.0,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            imageUrl,
            fit: BoxFit.cover,
            loadingBuilder: (_, child, p) =>
                p == null ? child : const ColoredBox(color: Color(0xFFEAE3D4)),
            errorBuilder: (_, _, _) => const _StripedBox(),
          ),
          Positioned(
            top: statusBarH + 16,
            left: 16,
            child: _CircleNavBtn(
                icon: Icons.arrow_back_rounded,
                onTap: () => Navigator.of(context).maybePop()),
          ),
          Positioned(
            top: statusBarH + 16,
            right: 16,
            child: _CircleNavBtn(
                icon: Icons.close_rounded,
                onTap: () => Navigator.of(context).maybePop()),
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
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Accordion section — identical to CatalogNodeScreen._AccordionSection
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
                      child: Text(
                        widget.label,
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _kInk),
                      ),
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
// Inline reviews — uses reviewsForCustomServiceProvider
// Flat style matching the flat review tiles in CatalogNodeScreen
// ═══════════════════════════════════════════════════════════════════════════════

class _InlineReviews extends ConsumerWidget {
  const _InlineReviews({required this.customServiceId});
  final String customServiceId;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews =
        ref.watch(reviewsForCustomServiceProvider(customServiceId)).valueOrNull ??
            [];

    if (reviews.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(0, 4, 0, 14),
        child: Text('No reviews yet.',
            style: TextStyle(fontSize: 13, color: _kMuted)),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: reviews.map((r) {
          final d = r.createdAt;
          final date = '${d.day} ${_months[d.month - 1]} ${d.year}';
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ...List.generate(
                      5,
                      (i) => Icon(
                        i < r.rating
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        size: 15,
                        color: _kGold,
                      ),
                    ),
                    const Spacer(),
                    Text(date,
                        style:
                            const TextStyle(fontSize: 11, color: _kMuted2)),
                  ],
                ),
                if (r.customerName?.isNotEmpty == true) ...[
                  const SizedBox(height: 2),
                  Text(
                    r.customerName!,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _kInk),
                  ),
                ],
                if (r.reviewText.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    r.reviewText,
                    style: const TextStyle(
                        fontSize: 13, color: _kMuted, height: 1.45),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Mobile booking bar — mirrors CatalogNodeScreen._NodeBookingBar
// ═══════════════════════════════════════════════════════════════════════════════

class _MobileBookingBar extends ConsumerWidget {
  const _MobileBookingBar({
    required this.service,
    required this.effectiveUnitPrice,
    required this.effectiveQty,
  });
  final VendorCustomServiceModel service;
  final double effectiveUnitPrice;
  final int effectiveQty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final cartItem =
        cart.where((i) => i.customServiceId == service.id).firstOrNull;
    final inCart = cartItem != null;

    final displayTotal = effectiveUnitPrice * effectiveQty;

    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, 14 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _kBorder, width: 1)),
      ),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(inCart ? 'Total' : 'From',
                  style: const TextStyle(fontSize: 10, color: _kMuted2)),
              Text(
                '₹${displayTotal.toInt()}',
                style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _kInk,
                    height: 1.1),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: inCart
                    ? () => openCheckout(context, ref)
                    : () => ref
                        .read(cartProvider.notifier)
                        .addCustomServiceToCart(
                          service,
                          unitPrice: effectiveUnitPrice,
                          quantity: effectiveQty,
                        ),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                      color: _kInk,
                      borderRadius: BorderRadius.circular(100)),
                  child: Center(
                    child: Text(
                      inCart ? '🛒  Proceed to Checkout' : '🛒  Add to Cart',
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
// Web quantity stepper — mirrors CatalogNodeScreen._WebQtyStepper
// ═══════════════════════════════════════════════════════════════════════════════

class _WebQtyStepper extends StatelessWidget {
  const _WebQtyStepper({
    required this.quantity,
    required this.onDecrement,
    required this.onIncrement,
  });

  final int quantity;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: _kBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepBtn(icon: Icons.remove_rounded, onTap: onDecrement),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              '$quantity',
              style: GoogleFonts.poppins(
                  fontSize: 14, fontWeight: FontWeight.w700, color: _kInk),
            ),
          ),
          _StepBtn(icon: Icons.add_rounded, onTap: onIncrement),
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Icon(icon, size: 16, color: _kInk),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Shared primitives — mirrors CatalogNodeScreen private helpers
// ═══════════════════════════════════════════════════════════════════════════════

class _StripedBox extends StatelessWidget {
  const _StripedBox();

  @override
  Widget build(BuildContext context) {
    return Container(
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
          decoration:
              const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: _kInk),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Content sections — mirrors CatalogNodeScreen private widgets exactly
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
            if (beforeUrl.isEmpty && afterUrl.isEmpty) {
              return const SizedBox.shrink();
            }
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

// ═══════════════════════════════════════════════════════════════════════════════
// Attribute / variant selector — same design as catalog_node_screen.dart
// ═══════════════════════════════════════════════════════════════════════════════

class _AttributeVariantSection extends StatelessWidget {
  const _AttributeVariantSection({
    required this.attrs,
    required this.selectedAttrId,
    required this.onAttrSelected,
    this.horizontalPadding = 20.0,
    this.quantities = const {},
    required this.onQtyChanged,
  });

  final List<ServiceAttributeModel> attrs;
  final String? selectedAttrId;
  final void Function(String attrId) onAttrSelected;
  final double horizontalPadding;
  final Map<String, int> quantities;
  final void Function(String attrId, int qty) onQtyChanged;

  @override
  Widget build(BuildContext context) {
    if (attrs.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(horizontalPadding, 20, horizontalPadding, 4),
      child: Row(
        children: attrs.asMap().entries.map((e) {
          final idx = e.key;
          final attr = e.value;
          final opt = attr.options.first;
          final isSelected = selectedAttrId == attr.id;
          final qty = quantities[attr.id] ?? 1;
          return Padding(
            padding: EdgeInsets.only(right: idx < attrs.length - 1 ? 8 : 0),
            child: _VariantChip(
              optionName: attr.name,
              price: opt.finalPrice,
              originalPrice: opt.hasDiscount ? opt.priceAdjustment : null,
              isSelected: isSelected,
              quantity: qty,
              onTap: () => onAttrSelected(attr.id),
              onDecrement: () => onQtyChanged(attr.id, qty - 1),
              onIncrement: () => onQtyChanged(attr.id, qty + 1),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _VariantChip extends StatelessWidget {
  const _VariantChip({
    required this.optionName,
    required this.price,
    this.originalPrice,
    required this.isSelected,
    required this.quantity,
    required this.onTap,
    required this.onDecrement,
    required this.onIncrement,
  });

  final String optionName;
  final double price;
  final double? originalPrice;
  final bool isSelected;
  final int quantity;
  final VoidCallback onTap;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    final bg = isSelected ? _kInk : Colors.white;
    final fg = isSelected ? Colors.white : _kInk;
    final border = isSelected ? _kInk : const Color(0xFFE8E8E8);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 155,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                optionName,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: fg,
                    height: 1.3),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              if (price > 0 || originalPrice != null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    if (price > 0)
                      Text(
                        '₹${price.toInt()}',
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: fg,
                            height: 1.2),
                      ),
                    if (originalPrice != null) ...[
                      const SizedBox(width: 5),
                      Text(
                        '₹${originalPrice!.toInt()}',
                        style: TextStyle(
                          fontSize: 11,
                          color: fg.withAlpha(140),
                          decoration: TextDecoration.lineThrough,
                          decorationColor: fg.withAlpha(140),
                        ),
                      ),
                    ],
                  ],
                ),
              // Quantity stepper — only shown when this chip is selected
              if (isSelected) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _ChipStepBtn(
                      icon: Icons.remove_rounded,
                      onTap: onDecrement,
                      fg: fg,
                    ),
                    Text(
                      '$quantity',
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: fg,
                          height: 1.2),
                    ),
                    _ChipStepBtn(
                      icon: Icons.add_rounded,
                      onTap: onIncrement,
                      fg: fg,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipStepBtn extends StatelessWidget {
  const _ChipStepBtn({
    required this.icon,
    required this.onTap,
    required this.fg,
  });
  final IconData icon;
  final VoidCallback onTap;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: fg.withAlpha(30),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: fg),
        ),
      ),
    );
  }
}
