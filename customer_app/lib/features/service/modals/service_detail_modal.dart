import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../models/service_model.dart';
import '../../../features/catalog/models/catalog_node_model.dart';
import '../../../models/service_attribute_model.dart';
import '../../../models/addon_model.dart';
import '../../../features/category/services/category_providers.dart';
import '../widgets/service_image_carousel.dart';
import '../widgets/service_info_section.dart';
import '../widgets/faq_section.dart';
import '../widgets/service_attribute_section.dart';
import '../widgets/service_addon_section.dart';
import '../../booking/utils/booking_gate.dart';
import '../../wishlist/widgets/heart_button.dart';
import '../../reviews/widgets/service_reviews_section.dart';
import '../../cart/providers/cart_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/utils/auth_modal_gate.dart';

/// Desktop/web floating dialog that shows service details without navigating
/// to a new page. Uses the same backdrop + animation pattern as [PageSheet].
///
/// On mobile, callers fall back to the full-screen route push.
class ServiceDetailModal extends ConsumerStatefulWidget {
  final ServiceModel service;

  const ServiceDetailModal({super.key, required this.service});

  static Future<void> show(BuildContext context, ServiceModel service) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (ctx, anim1, anim2) =>
          ServiceDetailModal(service: service),
      transitionBuilder: (ctx, anim, secAnim, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1.0).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  ConsumerState<ServiceDetailModal> createState() => _ServiceDetailModalState();
}

class _ServiceDetailModalState extends ConsumerState<ServiceDetailModal> {
  final Map<String, String> _selections = {};
  double _priceAdjustment = 0.0;
  final Set<String> _selectedAddonIds = {};

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
    final service = widget.service;
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    final modalW = (size.width * 0.9).clamp(320.0, 900.0);
    final modalH = size.height * 0.85;

    final attrs =
        ref.watch(serviceAttributesProvider(service.id)).valueOrNull ?? [];
    final addOns =
        ref.watch(allActiveAddonsProvider).valueOrNull ?? [];
    final addonsTotal = totalAddonsPrice(buildSelectedAddons(addOns, _selectedAddonIds));
    final displayPrice = service.startingPrice + _priceAdjustment + addonsTotal;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: [
          // Blurred dimmed backdrop
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: const ColoredBox(color: Color(0x70000000)),
              ),
            ),
          ),

          // Modal card
          Center(
            child: SizedBox(
              width: modalW,
              height: modalH,
              child: Material(
                color: cs.surface,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                elevation: 24,
                shadowColor: Colors.black38,
                child: Column(
                  children: [
                    // Hero image with overlaid close + heart buttons
                    _ImageHeader(service: service),

                    // Scrollable content area
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ServiceInfoSection(service: service),

                            // Attribute selection — live price recalculation
                            ServiceAttributeSection(
                              attrs: attrs,
                              selections: _selections,
                              onChanged: (attrId, optId) =>
                                  _onOptionSelected(attrId, optId, attrs),
                            ),

                            if (service.description != null)
                              _DescriptionBlock(
                                  description: service.description!),
                            ServiceAddonSection(
                              addOns: addOns,
                              selectedIds: _selectedAddonIds,
                              onToggle: _onAddonToggled,
                            ),
                            FaqSection(faqs: service.faqs),
                            ServiceReviewsSection(serviceId: service.id),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),

                    // Sticky booking footer
                    _ModalBookingBar(
                      service: service,
                      attrs: attrs,
                      selections: _selections,
                      addOns: addOns,
                      selectedAddonIds: _selectedAddonIds,
                      displayPrice: displayPrice,
                      priceAdjustment: _priceAdjustment,
                      addonsTotal: addonsTotal,
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

// ── Image header ───────────────────────────────────────────────────────────────

class _ImageHeader extends StatelessWidget {
  final ServiceModel service;
  const _ImageHeader({required this.service});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 260,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ServiceImageCarousel(service: service),

          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 90,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x99000000), Colors.transparent],
                ),
              ),
            ),
          ),

          Positioned(
            top: 10,
            right: 10,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _GlassCircle(
                    child: HeartButton(serviceId: service.id, mini: false)),
                const SizedBox(width: 6),
                _GlassCircle(
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 20, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 40, minHeight: 40),
                    splashRadius: 20,
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

class _GlassCircle extends StatelessWidget {
  final Widget child;
  const _GlassCircle({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0x80000000),
        shape: BoxShape.circle,
      ),
      child: child,
    );
  }
}

// ── Content blocks ─────────────────────────────────────────────────────────────

class _DescriptionBlock extends StatelessWidget {
  final String description;
  const _DescriptionBlock({required this.description});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About this service',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: tt.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sticky booking footer ──────────────────────────────────────────────────────

class _ModalBookingBar extends ConsumerWidget {
  final ServiceModel service;
  final List<ServiceAttributeModel> attrs;
  final Map<String, String> selections;
  final List<AddOnModel> addOns;
  final Set<String> selectedAddonIds;
  final double displayPrice;
  final double priceAdjustment;
  final double addonsTotal;

  const _ModalBookingBar({
    required this.service,
    required this.attrs,
    required this.selections,
    required this.addOns,
    required this.selectedAddonIds,
    required this.displayPrice,
    required this.priceAdjustment,
    required this.addonsTotal,
  });

  bool get _requiredFilled =>
      attrs.where((a) => a.isRequired && a.hasOptions).every(
            (a) => selections.containsKey(a.id),
          );

  bool get _hasRequiredAttrs =>
      attrs.any((a) => a.isRequired && a.hasOptions);

  Future<void> _addToCart(BuildContext context, WidgetRef ref) async {
    if (!ref.read(isAuthenticatedProvider)) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Login Required'),
          content: const Text('Please log in to add items to your cart.'),
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
        .addToCart(CatalogNodeModel.fromServiceModel(service),
            priceAdjustment: priceAdjustment + addonsTotal);

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
    await launchBookingFlow(context, ref, CatalogNodeModel.fromServiceModel(service),
        selectedAttributes: selectedAttrs,
        selectedAddons: selectedAddons);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final canBook = !_hasRequiredAttrs || _requiredFilled;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outline.withAlpha(60), width: 0.8),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(12),
            blurRadius: 8,
            offset: const Offset(0, -2),
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
                style: tt.headlineSmall?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                (priceAdjustment > 0 || addonsTotal > 0) ? 'incl. adjustments' : 'onwards',
                style:
                    tt.labelSmall?.copyWith(color: cs.onSurface.withAlpha(120)),
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
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
