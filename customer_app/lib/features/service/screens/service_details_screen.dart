import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
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
import '../../cart/providers/cart_provider.dart';
import '../../cart/utils/cart_launcher.dart';
import '../../wishlist/widgets/heart_button.dart';
import '../../reviews/widgets/service_reviews_section.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/utils/auth_modal_gate.dart';
import '../../amc/widgets/amc_section.dart';

class ServiceDetailsScreen extends ConsumerStatefulWidget {
  final ServiceModel service;

  const ServiceDetailsScreen({super.key, required this.service});

  @override
  ConsumerState<ServiceDetailsScreen> createState() =>
      _ServiceDetailsScreenState();
}

class _ServiceDetailsScreenState extends ConsumerState<ServiceDetailsScreen> {
  final Map<String, String> _selections = {};
  double _priceAdjustment = 0.0;
  final Set<String> _selectedAddonIds = {};
  AmcPlanModel? _selectedAmcPlan;

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
    final service = widget.service;
    final tt = Theme.of(context).textTheme;
    final attrs =
        ref.watch(serviceAttributesProvider(service.id)).valueOrNull ?? [];
    final addOns = ref.watch(allActiveAddonsProvider).valueOrNull ?? [];
    final addonsTotal = totalAddonsPrice(
      buildSelectedAddons(addOns, _selectedAddonIds),
    );
    final displayPrice = _selectedAmcPlan != null
        ? _selectedAmcPlan!.finalPrice
        : service.startingPrice + _priceAdjustment + addonsTotal;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            actions: [
              HeartButton(serviceId: service.id, mini: false),
              const SizedBox(width: 4),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: ServiceImageCarousel(service: service),
            ),
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ServiceInfoSection(service: service),

                // Attribute selection — fires live price recalculation
                ServiceAttributeSection(
                  attrs: attrs,
                  selections: _selections,
                  onChanged: (attrId, optId) =>
                      _onOptionSelected(attrId, optId, attrs),
                ),

                if (service.description != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'About this service',
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          service.description!,
                          style: tt.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                ServiceAddonSection(
                  addOns: addOns,
                  selectedIds: _selectedAddonIds,
                  onToggle: _onAddonToggled,
                ),
                AmcSection(
                  serviceId: service.id,
                  selectedPlan: _selectedAmcPlan,
                  onPlanSelected: (plan) => setState(() {
                    _selectedAmcPlan = plan;
                  }),
                  regularPrice: service.startingPrice > 0
                      ? service.startingPrice
                      : null,
                ),

                FaqSection(faqs: service.faqs),
                ServiceReviewsSection(serviceId: service.id),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),

      bottomNavigationBar: _BookingBar(
        service: service,
        attrs: attrs,
        selections: _selections,
        addOns: addOns,
        selectedAddonIds: _selectedAddonIds,
        displayPrice: displayPrice,
        priceAdjustment: _priceAdjustment,
        addonsTotal: addonsTotal,
        amcPlan: _selectedAmcPlan,
      ),
    );
  }
}

// ── Gold pill CTA button ──────────────────────────────────────────────────────

class _GoldPillButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;

  const _GoldPillButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Material(
      color: enabled ? AppColors.gold : AppColors.border,
      borderRadius: BorderRadius.circular(100),
      elevation: 0,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(100),
        splashColor: Colors.white.withAlpha(60),
        highlightColor: Colors.transparent,
        child: Container(
          height: 50,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: enabled ? AppColors.primary : AppColors.textHint,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: enabled ? AppColors.primary : AppColors.textHint,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sticky booking bar ────────────────────────────────────────────────────────

class _BookingBar extends ConsumerWidget {
  final ServiceModel service;
  final List<ServiceAttributeModel> attrs;
  final Map<String, String> selections;
  final List<AddOnModel> addOns;
  final Set<String> selectedAddonIds;
  final double displayPrice;
  final double priceAdjustment;
  final double addonsTotal;
  final AmcPlanModel? amcPlan;

  const _BookingBar({
    required this.service,
    required this.attrs,
    required this.selections,
    required this.addOns,
    required this.selectedAddonIds,
    required this.displayPrice,
    required this.priceAdjustment,
    required this.addonsTotal,
    this.amcPlan,
  });

  bool get _requiredFilled => attrs
      .where((a) => a.isRequired && a.hasOptions)
      .every((a) => selections.containsKey(a.id));

  bool get _hasRequiredAttrs => attrs.any((a) => a.isRequired && a.hasOptions);

  Future<void> _addToCart(BuildContext context, WidgetRef ref) async {
    if (!ref.read(isAuthenticatedProvider)) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
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

    ref.read(cartProvider.notifier).addToCart(
          CatalogNodeModel.fromServiceModel(service),
          priceAdjustment: amcPlan != null ? 0.0 : priceAdjustment + addonsTotal,
          amcPlan: amcPlan,
          amcQuantity: 1,
        );

    if (!context.mounted) return;
    final currentPath = GoRouterState.of(context).uri.path;
    if (currentPath == '/cart') return;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('Added to cart'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canBook = !_hasRequiredAttrs || _requiredFilled;
    final inCart = ref.watch(cartProvider).any((item) => item.serviceId == service.id);

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
                'From',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppColors.textHint,
                  fontWeight: FontWeight.w400,
                ),
              ),
              Text(
                '₹${displayPrice.toInt()}',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  height: 1.1,
                ),
              ),
              Text(
                amcPlan != null
                    ? '${amcPlan!.numVisits} visits'
                    : (priceAdjustment > 0 || addonsTotal > 0)
                        ? 'incl. adjustments'
                        : 'onwards',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: inCart
                ? _GoldPillButton(
                    onPressed: () => openCart(context),
                    icon: Icons.shopping_cart_rounded,
                    label: 'View Cart',
                  )
                : _GoldPillButton(
                    onPressed: canBook ? () => _addToCart(context, ref) : null,
                    icon: Icons.shopping_cart_checkout_rounded,
                    label: canBook ? 'Add to Cart' : 'Select options',
                  ),
          ),
        ],
      ),
    );
  }
}
