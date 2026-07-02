import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/clickable.dart';
import '../../../models/service_model.dart';
import '../../../models/service_attribute_model.dart';
import '../../../features/category/services/category_providers.dart';
import '../widgets/service_image_carousel.dart';
import '../widgets/service_info_section.dart';
import '../widgets/faq_section.dart';
import '../widgets/service_attribute_section.dart';
import '../../booking/utils/booking_gate.dart';
import '../../wishlist/widgets/heart_button.dart';
import '../../reviews/widgets/service_reviews_section.dart';
import '../../cart/providers/cart_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/utils/auth_modal_gate.dart';

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

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final tt = Theme.of(context).textTheme;
    final attrs =
        ref.watch(serviceAttributesProvider(service.id)).valueOrNull ?? [];
    final displayPrice = service.startingPrice + _priceAdjustment;

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
                          style: tt.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
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

                if (service.addOns.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: Text(
                      'Add-ons',
                      style: tt.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 100,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      scrollDirection: Axis.horizontal,
                      itemCount: service.addOns.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (_, i) =>
                          _AddOnCard(addOn: service.addOns[i]),
                    ),
                  ),
                ],

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
        displayPrice: displayPrice,
        priceAdjustment: _priceAdjustment,
      ),
    );
  }
}

// ── Add-on card ───────────────────────────────────────────────────────────────

class _AddOnCard extends StatefulWidget {
  final dynamic addOn;
  const _AddOnCard({required this.addOn});

  @override
  State<_AddOnCard> createState() => _AddOnCardState();
}

class _AddOnCardState extends State<_AddOnCard> {
  bool _added = false;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final addOn = widget.addOn;

    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _added ? AppColors.primary : AppColors.border,
          width: _added ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  addOn.name,
                  style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Clickable(
                onTap: () => setState(() => _added = !_added),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: _added ? AppColors.primary : Colors.transparent,
                    border: Border.all(
                      color: _added ? AppColors.primary : AppColors.border,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: _added
                      ? const Icon(Icons.check_rounded,
                          size: 16, color: Colors.white)
                      : const Icon(Icons.add_rounded,
                          size: 16, color: AppColors.textHint),
                ),
              ),
            ],
          ),
          if (addOn.description != null) ...[
            const SizedBox(height: 4),
            Text(
              addOn.description!,
              style: tt.labelSmall?.copyWith(color: AppColors.textHint),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const Spacer(),
          Text(
            '+ ₹${(addOn.price as double).toInt()}',
            style: tt.labelMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sticky booking bar ────────────────────────────────────────────────────────

class _BookingBar extends ConsumerWidget {
  final ServiceModel service;
  final List<ServiceAttributeModel> attrs;
  final Map<String, String> selections;
  final double displayPrice;
  final double priceAdjustment;

  const _BookingBar({
    required this.service,
    required this.attrs,
    required this.selections,
    required this.displayPrice,
    required this.priceAdjustment,
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
        .addToCart(service, priceAdjustment: priceAdjustment);

    if (!context.mounted) return;
    final currentPath = GoRouterState.of(context).uri.path;
    if (currentPath == '/cart') return;

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
    await launchBookingFlow(context, ref, service,
        selectedAttributes: selectedAttrs);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
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
                style: tt.headlineSmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                priceAdjustment > 0 ? 'incl. adjustments' : 'onwards',
                style: tt.labelSmall?.copyWith(color: AppColors.textHint),
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
                canBook
                    ? 'Book Now'
                    : 'Select options',
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
