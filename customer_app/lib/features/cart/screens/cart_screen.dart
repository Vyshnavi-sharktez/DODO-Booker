import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/service_image_registry.dart';
import '../../../core/widgets/clickable.dart';
import '../../../core/widgets/page_sheet.dart';
import '../models/cart_item.dart';
import '../providers/cart_provider.dart';
import '../providers/saved_carts_provider.dart';
import '../widgets/min_order_card.dart';
import '../widgets/service_unavailable_dialog.dart';
import '../../auth/utils/auth_modal_gate.dart';
import '../../catalog/models/catalog_node_model.dart';
import '../../catalog/providers/catalog_providers.dart';
import '../../catalog/utils/catalog_launcher.dart';
import '../../home/services/home_providers.dart';
import '../../tax/models/tax_settings_model.dart';
import '../../tax/providers/tax_provider.dart';
import 'checkout_screen.dart';
import '../../../models/addon_model.dart';
import '../../category/services/category_providers.dart';
import '../../service/widgets/service_addon_section.dart';
import '../providers/global_cart_addons_provider.dart';

// ── Cart-page recommendation provider ─────────────────────────────────────────
//
// Derives up to 8 suggestions from the same parent categories as the current
// cart items. Falls back to global popular services when no parent context is
// available or too few siblings survive the filters. Always excludes items
// already in the cart, inactive, non-leaf-bookable, and unavailable/hidden nodes.
final _cartRecommendationsProvider =
    FutureProvider.autoDispose<List<CatalogNodeModel>>((ref) async {
  final cartItems = ref.watch(cartProvider);
  if (cartItems.isEmpty) return [];

  final parentIds = cartItems
      .where((i) => i.parentNodeId != null)
      .map((i) => i.parentNodeId!)
      .toSet()
      .toList();

  final cartIds = cartItems.map((i) => i.serviceId).toSet();
  final candidates = <CatalogNodeModel>[];

  if (parentIds.isNotEmpty) {
    final batches = await Future.wait(
      parentIds.map(
        (id) => ref
            .read(catalogNodeChildrenProvider(id).future)
            .catchError((Object _) => <CatalogNodeModel>[]),
      ),
    );
    for (final batch in batches) {
      candidates.addAll(batch);
    }
  }

  // Supplement with popular services when siblings are too few
  if (candidates.length < 3) {
    try {
      final popular = await ref.read(popularServicesProvider.future);
      candidates.addAll(popular);
    } catch (_) {
      // ignore — popular services are a best-effort supplement
    }
  }

  // Deduplicate, filter, sort by sort_order then rating, limit to 8
  final seen = <String>{};
  final filtered = candidates
      .where((n) => seen.add(n.id))
      .where((n) =>
          !cartIds.contains(n.id) &&
          n.isActive &&
          n.isLeafBookable &&
          n.availabilityStatus == 'active' &&
          n.relAvailabilityStatus == 'active')
      .toList();

  filtered.sort((a, b) {
    final s = a.sortOrder.compareTo(b.sortOrder);
    return s != 0 ? s : b.rating.compareTo(a.rating);
  });

  return filtered.take(8).toList();
});

class CartScreen extends ConsumerStatefulWidget {
  /// When [true], renders without a [Scaffold] / [AppBar] so it can be hosted
  /// inside [PageSheet] on desktop. All business logic and providers are shared.
  final bool inModal;

  const CartScreen({super.key, this.inModal = false});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  @override
  Widget build(BuildContext context) {
    final items = ref.watch(cartProvider);
    final subtotal = ref.watch(cartSubtotalProvider);
    final savedCarts = ref.watch(savedCartsProvider);

    if (widget.inModal) {
      return _ModalBody(items: items, subtotal: subtotal);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Cart'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.8),
          child: Container(height: 0.8, color: AppColors.divider),
        ),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () => ref.read(cartProvider.notifier).clearCart(),
              child: const Text(
                'Clear all',
                style: TextStyle(color: AppColors.error),
              ),
            ),
        ],
      ),
      // When both active cart and saved carts are empty show the full-screen
      // empty state. Otherwise always show the saved-carts strip above the
      // content so the customer can switch to any saved cart.
      body: savedCarts.isEmpty && items.isEmpty
          ? const _EmptyCart()
          : Column(
              children: [
                const _SavedCartsStrip(),
                Expanded(
                  child: items.isEmpty
                      ? const _EmptyCart()
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          children: [
                            ...items.map((item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _CartItemCard(item: item),
                                )),
                            const SizedBox(height: 8),
                            const _GlobalAddonsSection(),
                            const SizedBox(height: 8),
                            _CartSummaryCard(items: items, subtotal: subtotal),
                            const _CartRecommendations(),
                            // Padding so the sticky bar doesn't overlap the last row
                            const SizedBox(height: 84),
                          ],
                        ),
                ),
              ],
            ),
      bottomNavigationBar:
          items.isEmpty ? null : _CheckoutBar(subtotal: subtotal),
    );
  }
}

// ── Modal-mode body (hosted inside PageSheet) ─────────────────────────────────

class _ModalBody extends ConsumerWidget {
  final List<CartItem> items;
  final double subtotal;

  const _ModalBody({required this.items, required this.subtotal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        // Compact "Clear all" row — replaces the AppBar action
        if (items.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 6, 12, 0),
            child: Row(
              children: [
                Text(
                  '${items.fold<int>(0, (s, i) => s + i.quantity)} item(s)',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => ref.read(cartProvider.notifier).clearCart(),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                  ),
                  child: const Text('Clear all'),
                ),
              ],
            ),
          ),

        // Saved carts strip — visible whenever other carts are saved
        const _SavedCartsStrip(),

        Expanded(
          child: items.isEmpty
              ? const _EmptyCart(inModal: true)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  children: [
                    ...items.map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _CartItemCard(item: item),
                        )),
                    const SizedBox(height: 8),
                    const _GlobalAddonsSection(),
                    const SizedBox(height: 8),
                    _CartSummaryCard(items: items, subtotal: subtotal),
                    const _CartRecommendations(),
                  ],
                ),
        ),

        if (items.isNotEmpty) _ModalCheckoutBar(subtotal: subtotal),
      ],
    );
  }
}

// ── Saved carts strip ─────────────────────────────────────────────────────────
//
// Shown at the top of the cart when the customer has carts from other root
// categories. Tapping a chip switches that cart to active.

class _SavedCartsStrip extends ConsumerWidget {
  const _SavedCartsStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedCarts = ref.watch(savedCartsProvider);
    if (savedCarts.isEmpty) return const SizedBox.shrink();

    final tt = Theme.of(context).textTheme;
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Saved carts',
            style: tt.labelSmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in savedCarts.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _SavedCartChip(
                      rootCategoryId: entry.key,
                      items: entry.value,
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

class _SavedCartChip extends ConsumerWidget {
  final String rootCategoryId;
  final List<CartItem> items;

  const _SavedCartChip({
    required this.rootCategoryId,
    required this.items,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodeAsync = ref.watch(catalogNodeProvider(rootCategoryId));
    final name = nodeAsync.valueOrNull?.name;
    final totalQty = items.fold<int>(0, (s, i) => s + i.quantity);
    final label = name != null
        ? '$name ($totalQty ${totalQty == 1 ? 'item' : 'items'})'
        : '${items.first.serviceName.split(' ').first} ($totalQty)';

    return ActionChip(
      avatar: const Icon(Icons.shopping_cart_outlined, size: 14),
      label: Text(label),
      onPressed: () =>
          ref.read(cartProvider.notifier).switchToCart(rootCategoryId),
      backgroundColor: AppColors.primaryLight,
      side: const BorderSide(color: AppColors.primary, width: 0.8),
      labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
      visualDensity: VisualDensity.compact,
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyCart extends StatelessWidget {
  final bool inModal;
  const _EmptyCart({this.inModal = false});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_cart_outlined,
                size: 52,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Your cart is empty',
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Browse services and add them here to book multiple services at once.',
              style: tt.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () {
                if (inModal) {
                  // Close the dialog before navigating so GoRouter
                  // doesn't fight the showGeneralDialog route.
                  final router = GoRouter.of(context);
                  Navigator.of(context).pop();
                  router.go('/');
                } else {
                  context.go('/');
                }
              },
              icon: const Icon(Icons.explore_outlined, size: 18),
              label: const Text(
                'Explore Services',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size(200, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Cart item card ─────────────────────────────────────────────────────────────

class _CartItemCard extends ConsumerStatefulWidget {
  final CartItem item;

  const _CartItemCard({required this.item});

  @override
  ConsumerState<_CartItemCard> createState() => _CartItemCardState();
}

class _CartItemCardState extends ConsumerState<_CartItemCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final notifier = ref.read(cartProvider.notifier);
    final item = widget.item;

    if (!kIsWeb) {
      return _mobileCard(context, tt, notifier, item);
    }

    return _webCard(context, tt, notifier, item);
  }

  // ── Web: collapsible card ─────────────────────────────────────────────────

  Widget _webCard(
    BuildContext context,
    TextTheme tt,
    CartNotifier notifier,
    CartItem item,
  ) {
    final addonsTotal = item.addons.fold(0.0, (s, a) => s + a.addonPrice);
    final basePrice = item.unitPrice - addonsTotal;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Clickable collapsed header ──────────────────────────────
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _ServiceThumbnail(imageUrl: item.imageUrl),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.serviceName,
                            style: tt.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          if (item.isAmc)
                            Row(
                              children: [
                                _AmcBadge(tt: tt),
                                if (item.amcRecurrenceInterval != null &&
                                    item.amcRecurrenceInterval!.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    item.amcRecurrenceInterval!,
                                    style: tt.labelSmall?.copyWith(
                                        color: AppColors.textHint),
                                  ),
                                ],
                              ],
                            )
                          else
                            Text(
                              '₹${item.unitPrice.toInt()} per unit',
                              style: tt.labelSmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₹${item.totalPrice.toInt()}',
                          style: tt.titleSmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (item.quantity > 1)
                          Text(
                            '× ${item.quantity}',
                            style: tt.labelSmall
                                ?.copyWith(color: AppColors.textHint),
                          ),
                      ],
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: AppColors.textHint,
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => notifier.removeFromCart(item.bookingId),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: AppColors.textHint,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _CartAddonInline(item: item),
          ),

          // ── Expanded breakdown ──────────────────────────────────────
          if (_expanded) ...[
            const Divider(color: AppColors.divider, height: 0, thickness: 0.8),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(
                children: [
                  // Price line items
                  if (item.isAmc) ...[
                    _BreakdownRow(
                      label: item.amcPlanName?.isNotEmpty == true
                          ? item.amcPlanName!
                          : 'AMC Plan',
                      value: '₹${(item.amcFinalPrice ?? item.unitPrice).toInt()}',
                      tt: tt,
                    ),
                    if ((item.amcRecurrenceInterval?.isNotEmpty == true) ||
                        item.amcNumVisits != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            [
                              if (item.amcRecurrenceInterval?.isNotEmpty == true)
                                item.amcRecurrenceInterval!,
                              if (item.amcNumVisits != null)
                                '${item.amcNumVisits} visits',
                            ].join(' - '),
                            style: tt.labelSmall
                                ?.copyWith(color: AppColors.textHint),
                          ),
                        ),
                      ),
                    if (item.amcIsRenewal)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Renewal',
                            style: tt.labelSmall?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    if (item.amcQuantity > 1) ...[
                      const SizedBox(height: 6),
                      _BreakdownRow(
                        label: '× ${item.amcQuantity} units',
                        value: '₹${item.unitPrice.toInt()}',
                        tt: tt,
                        isSubtotal: true,
                      ),
                    ],
                  ] else ...[
                    _BreakdownRow(
                      label: 'Base service',
                      value: '₹${basePrice.toInt()}',
                      tt: tt,
                    ),
                    ...item.addons.map(
                      (a) => Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: _BreakdownRow(
                          label: '+ ${a.addonName}',
                          value: '₹${a.addonPrice.toInt()}',
                          tt: tt,
                          isAddon: true,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),
                  const Divider(
                      color: AppColors.divider, height: 0, thickness: 0.8),
                  const SizedBox(height: 12),

                  // Qty stepper + line total
                  Row(
                    children: [
                      _QuantityStepper(
                        quantity: item.quantity,
                        onDecrement: () => notifier.updateQuantity(
                            item.bookingId, item.quantity - 1),
                        onIncrement: () => notifier.updateQuantity(
                            item.bookingId, item.quantity + 1),
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '₹${item.totalPrice.toInt()}',
                            style: tt.titleSmall?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (item.quantity > 1)
                            Text(
                              '${item.quantity} × ₹${item.unitPrice.toInt()}',
                              style: tt.labelSmall
                                  ?.copyWith(color: AppColors.textHint),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Mobile: original layout unchanged ────────────────────────────────────

  Widget _mobileCard(
    BuildContext context,
    TextTheme tt,
    CartNotifier notifier,
    CartItem item,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ServiceThumbnail(imageUrl: item.imageUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.serviceName,
                              style: tt.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Clickable(
                            onTap: () =>
                                notifier.removeFromCart(item.bookingId),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 20,
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (item.isAmc) ...[
                        _AmcBadge(tt: tt),
                        const SizedBox(height: 4),
                        if (item.amcPlanName != null &&
                            item.amcPlanName!.isNotEmpty)
                          Text(
                            item.amcPlanName!,
                            style: tt.labelSmall
                                ?.copyWith(color: AppColors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (item.amcRecurrenceInterval != null &&
                            item.amcRecurrenceInterval!.isNotEmpty)
                          Text(
                            '${item.amcRecurrenceInterval!} - ${item.amcNumVisits ?? 12} visits',
                            style: tt.labelSmall
                                ?.copyWith(color: AppColors.textHint),
                          ),
                        if (item.amcQuantity > 1)
                          Text(
                            '₹${(item.amcFinalPrice ?? 0).toInt()} × ${item.amcQuantity} units',
                            style: tt.labelSmall
                                ?.copyWith(color: AppColors.textSecondary),
                          )
                        else if (item.amcIsRenewal)
                          Text(
                            'Renewal',
                            style: tt.labelSmall?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        const SizedBox(height: 2),
                      ],
                      if (!item.isAmc)
                        Text(
                          '₹${item.unitPrice.toInt()} per unit',
                          style: tt.labelSmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _CartAddonInline(item: item),
            const Divider(color: AppColors.divider, height: 0, thickness: 0.8),
            const SizedBox(height: 12),
            Row(
              children: [
                _QuantityStepper(
                  quantity: item.quantity,
                  onDecrement: () =>
                      notifier.updateQuantity(item.bookingId, item.quantity - 1),
                  onIncrement: () =>
                      notifier.updateQuantity(item.bookingId, item.quantity + 1),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${item.totalPrice.toInt()}',
                      style: tt.titleSmall?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (item.quantity > 1)
                      Text(
                        '${item.quantity} × ₹${item.unitPrice.toInt()}',
                        style: tt.labelSmall?.copyWith(color: AppColors.textHint),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Cart item add-ons (inline summary + edit sheet) ───────────────────────────

class _CartAddonInline extends ConsumerWidget {
  final CartItem item;

  const _CartAddonInline({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (item.isAmc || item.isCustomService) return const SizedBox.shrink();

    final addonsAsync = ref.watch(nodeAddonsProvider(item.serviceId));

    return addonsAsync.when(
      data: (addOns) {
        // Only show per-item section for non-global addons.
        final nonGlobal = addOns.where((a) => !a.isGlobal).toList();
        if (nonGlobal.isEmpty) return const SizedBox.shrink();
        return _CartAddonSummary(item: item, addOns: nonGlobal);
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _CartAddonSummary extends ConsumerWidget {
  final CartItem item;
  final List<AddOnModel> addOns;

  const _CartAddonSummary({required this.item, required this.addOns});

  Map<String, SelectedAddon> get _selectedMap =>
      {for (final a in item.addons) a.addonId: a};

  void _toggle(WidgetRef ref, AddOnModel addon, bool isCurrentlySelected) {
    final map = Map<String, SelectedAddon>.from(_selectedMap);
    if (isCurrentlySelected) {
      map.remove(addon.id);
    } else {
      map[addon.id] = SelectedAddon(
        addonId: addon.id,
        addonName: addon.name,
        addonPrice: addon.finalPrice,
        originalAddonPrice: addon.hasDiscount ? addon.price : null,
        quantity: 1,
      );
    }
    _update(ref, map.values.toList());
  }

  void _setQty(WidgetRef ref, String addonId, int newQty) {
    final map = Map<String, SelectedAddon>.from(_selectedMap);
    if (newQty <= 0) {
      map.remove(addonId);
    } else {
      final existing = map[addonId];
      if (existing != null) map[addonId] = existing.copyWith(quantity: newQty);
    }
    _update(ref, map.values.toList());
  }

  void _update(WidgetRef ref, List<SelectedAddon> newAddons) {
    final basePrice = item.unitPrice - totalAddonsPrice(item.addons);
    ref.read(cartProvider.notifier).updateAddons(
          item.bookingId,
          newAddons,
          basePrice + totalAddonsPrice(newAddons),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final selectedMap = _selectedMap;
    final selectedCount = selectedMap.length;

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: AppColors.divider, height: 16, thickness: 0.8),
          Row(
            children: [
              Text(
                'Add-ons',
                style: tt.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              if (selectedCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$selectedCount selected',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: addOns.map((addon) {
              final selectedAddon = selectedMap[addon.id];
              final isSelected = selectedAddon != null;
              final qty = selectedAddon?.quantity ?? 1;

              if (isSelected) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => _toggle(ref, addon, true),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: Colors.black, width: 1.2),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_rounded,
                                size: 13, color: Colors.white),
                            const SizedBox(width: 5),
                            Text(
                              addon.name,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '+₹${(addon.finalPrice * qty).toInt()}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withAlpha(180),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _AddonQtyStepper(
                      qty: qty,
                      onDecrement: () =>
                          _setQty(ref, addon.id, qty - 1),
                      onIncrement: () =>
                          _setQty(ref, addon.id, qty + 1),
                    ),
                  ],
                );
              }

              return GestureDetector(
                onTap: () => _toggle(ref, addon, false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.border, width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        addon.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '+₹${addon.finalPrice.toInt()}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _CartAddonSheet extends ConsumerStatefulWidget {
  final CartItem item;
  final List<AddOnModel> addOns;

  const _CartAddonSheet({required this.item, required this.addOns});

  @override
  ConsumerState<_CartAddonSheet> createState() => _CartAddonSheetState();
}

class _CartAddonSheetState extends ConsumerState<_CartAddonSheet> {
  late Set<String> _selectedIds;
  late double _basePrice;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.item.addons.map((a) => a.addonId).toSet();
    _basePrice = widget.item.unitPrice - totalAddonsPrice(widget.item.addons);
  }

  void _onToggle(String addonId, bool selected) {
    setState(() {
      if (selected) {
        _selectedIds.add(addonId);
      } else {
        _selectedIds.remove(addonId);
      }
    });
    final newAddons = buildSelectedAddons(widget.addOns, _selectedIds);
    ref.read(cartProvider.notifier).updateAddons(
          widget.item.bookingId,
          newAddons,
          _basePrice + totalAddonsPrice(newAddons),
        );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.serviceName,
                        style: tt.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap to add or remove',
                        style:
                            tt.bodySmall?.copyWith(color: AppColors.textHint),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: Icon(
                      Icons.close_rounded,
                      size: 22,
                      color: AppColors.textHint,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ServiceAddonSection(
            addOns: widget.addOns,
            selectedIds: _selectedIds,
            onToggle: _onToggle,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Global add-ons section (shown once per cart) ──────────────────────────────

class _GlobalAddonsSection extends ConsumerWidget {
  const _GlobalAddonsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final globalState = ref.watch(globalCartAddonsProvider);
    final items = ref.watch(cartProvider);

    // Find the first non-AMC, non-custom service to load available global addons.
    final firstServiceId = items
        .where((i) => !i.isAmc && !i.isCustomService)
        .map((i) => i.serviceId)
        .firstOrNull;
    if (firstServiceId == null) return const SizedBox.shrink();

    final addonsAsync = ref.watch(nodeAddonsProvider(firstServiceId));
    return addonsAsync.when(
      data: (allAddOns) {
        final globalAddOns = allAddOns.where((a) => a.isGlobal).toList();
        if (globalAddOns.isEmpty) return const SizedBox.shrink();
        return _GlobalAddonsSectionContent(
          globalAddOns: globalAddOns,
          globalState: globalState,
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _GlobalAddonsSectionContent extends ConsumerWidget {
  final List<AddOnModel> globalAddOns;
  final Map<String, SelectedAddon> globalState;

  const _GlobalAddonsSectionContent({
    required this.globalAddOns,
    required this.globalState,
  });

  void _setQty(WidgetRef ref, String addonId, int newQty) {
    ref.read(globalCartAddonsProvider.notifier).setQuantity(addonId, newQty);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final notifier = ref.read(globalCartAddonsProvider.notifier);
    final selectedCount = globalState.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Global Add-ons',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (selectedCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$selectedCount selected',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Applied once to your entire cart',
            style: tt.labelSmall?.copyWith(color: AppColors.textHint),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: globalAddOns.map((addon) {
              final selectedAddon = globalState[addon.id];
              final isSelected = selectedAddon != null;
              final qty = selectedAddon?.quantity ?? 1;

              if (isSelected) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => notifier.toggle(addon),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: Colors.black, width: 1.2),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_rounded,
                                size: 13, color: Colors.white),
                            const SizedBox(width: 5),
                            Text(
                              addon.name,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '+₹${(addon.finalPrice * qty).toInt()}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withAlpha(180),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _AddonQtyStepper(
                      qty: qty,
                      onDecrement: () => _setQty(ref, addon.id, qty - 1),
                      onIncrement: () => _setQty(ref, addon.id, qty + 1),
                    ),
                  ],
                );
              }

              return GestureDetector(
                onTap: () => notifier.toggle(addon),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.border, width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        addon.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '+₹${addon.finalPrice.toInt()}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Compact qty stepper for add-ons ──────────────────────────────────────────

class _AddonQtyStepper extends StatelessWidget {
  final int qty;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _AddonQtyStepper({
    required this.qty,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Clickable(
            onTap: onDecrement,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Icon(Icons.remove_rounded, size: 13, color: AppColors.primary),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '$qty',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          Clickable(
            onTap: onIncrement,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Icon(Icons.add_rounded, size: 13, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

// ── AMC badge (shared between web header and mobile card) ─────────────────────

class _AmcBadge extends StatelessWidget {
  final TextTheme tt;
  const _AmcBadge({required this.tt});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFEBF8FF),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: const Color(0xFF3182CE).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.autorenew_rounded,
              size: 11, color: Color(0xFF3182CE)),
          const SizedBox(width: 3),
          Text(
            'AMC',
            style: tt.labelSmall?.copyWith(
              color: const Color(0xFF3182CE),
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Breakdown row (price line item in expanded section) ───────────────────────

class _BreakdownRow extends StatelessWidget {
  final String label;
  final String value;
  final TextTheme tt;
  final bool isAddon;
  final bool isSubtotal;

  const _BreakdownRow({
    required this.label,
    required this.value,
    required this.tt,
    this.isAddon = false,
    this.isSubtotal = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isAddon ? AppColors.textSecondary : AppColors.textPrimary;
    final labelStyle = tt.labelSmall?.copyWith(color: color);
    final valueStyle = tt.labelSmall?.copyWith(
      color: isSubtotal ? AppColors.primary : color,
      fontWeight: (isAddon || isSubtotal) ? null : FontWeight.w600,
    );

    return Row(
      children: [
        Expanded(child: Text(label, style: labelStyle)),
        Text(value, style: valueStyle),
      ],
    );
  }
}

class _ServiceThumbnail extends StatelessWidget {
  final String? imageUrl;

  const _ServiceThumbnail({this.imageUrl});

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          imageUrl!,
          width: 68,
          height: 68,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              const _ThumbnailPlaceholder(),
        ),
      );
    }
    return const _ThumbnailPlaceholder();
  }
}

class _ThumbnailPlaceholder extends StatelessWidget {
  const _ThumbnailPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(
        Icons.home_repair_service_rounded,
        size: 30,
        color: AppColors.primary,
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  final int quantity;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _QuantityStepper({
    required this.quantity,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
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
              style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          _StepBtn(icon: Icons.add_rounded, onTap: onIncrement),
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _StepBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Clickable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Icon(icon, size: 16, color: AppColors.primary),
      ),
    );
  }
}

// ── Cart summary card (in scroll) ─────────────────────────────────────────────

class _CartSummaryCard extends ConsumerWidget {
  final List<CartItem> items;
  final double subtotal;

  const _CartSummaryCard({required this.items, required this.subtotal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final totalItems = items.fold<int>(0, (sum, item) => sum + item.quantity);

    // Resolve tax per item so ancestor-scoped configs (e.g. AC Services → 12%)
    // are applied. Amounts are summed; display label uses the first item's model.
    var totalTax = 0.0;
    TaxSettingsModel? displayTax;
    for (final item in items) {
      final taxSettings = ref.watch(resolvedTaxProvider((
        serviceId: item.serviceId,
        parentNodeId: item.parentNodeId,
      ))).valueOrNull ?? TaxSettingsModel.defaults;
      totalTax += taxSettings.computeTax(item.totalPrice);
      displayTax ??= taxSettings;
    }
    displayTax ??= ref.watch(taxSettingsProvider).valueOrNull ?? TaxSettingsModel.defaults;
    final grandTotal = subtotal + totalTax;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Price Summary',
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          _SummaryRow(label: 'Total items', value: '$totalItems', tt: tt),
          const SizedBox(height: 10),
          _SummaryRow(
              label: 'Subtotal', value: '₹${subtotal.toInt()}', tt: tt),
          if (totalTax > 0) ...[
            const SizedBox(height: 10),
            _SummaryRow(
              label: 'Est. ${displayTax.displayLabel}',
              value: '₹${totalTax.toInt()}',
              tt: tt,
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(color: AppColors.divider, height: 0),
          ),
          _SummaryRow(
            label: 'Grand Total',
            value: '₹${grandTotal.toInt()}',
            tt: tt,
            bold: true,
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final TextTheme tt;
  final bool bold;

  const _SummaryRow({
    required this.label,
    required this.value,
    required this.tt,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)
        : tt.bodySmall?.copyWith(color: AppColors.textSecondary);
    final valueStyle =
        bold ? style?.copyWith(color: AppColors.primary) : style;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: valueStyle),
      ],
    );
  }
}

// ── Sticky checkout bar — full-screen (mobile) ────────────────────────────────

class _CheckoutBar extends ConsumerWidget {
  const _CheckoutBar({required this.subtotal});
  final double subtotal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final items = ref.watch(cartProvider);
    var totalTax = 0.0;
    for (final item in items) {
      final taxSettings = ref.watch(resolvedTaxProvider((
        serviceId: item.serviceId,
        parentNodeId: item.parentNodeId,
      ))).valueOrNull ?? TaxSettingsModel.defaults;
      totalTax += taxSettings.computeTax(item.totalPrice);
    }
    final grandTotal = subtotal + totalTax;

    final globalMin = ref.watch(globalMinOrderAmountProvider).valueOrNull ?? 100.0;
    final checkItems = items.where((i) => !i.isAmc && !i.isCustomService).toList();
    CartItem? failingItem;
    double? effectiveFailingMin;
    for (final item in checkItems) {
      final effectiveMin = item.minimumOrderAmount ?? globalMin;
      if (effectiveMin > 0 && subtotal < effectiveMin) {
        failingItem = item;
        effectiveFailingMin = effectiveMin;
        break;
      }
    }
    final hasMinimum = failingItem != null ||
        checkItems.any((i) => (i.minimumOrderAmount ?? 0) > 0);
    final canCheckout = failingItem == null;

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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasMinimum) ...[
            MinOrderCard(effectiveMinimum: effectiveFailingMin, currentTotal: subtotal),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '₹${grandTotal.toInt()}',
                    style: tt.headlineSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'incl. taxes',
                    style: tt.labelSmall?.copyWith(color: AppColors.textHint),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  onPressed: canCheckout
                      ? () async {
                          final ok = await requireAuth(context, ref);
                          if (!ok || !context.mounted) return;
                          final removed = await ref
                              .read(cartProvider.notifier)
                              .pruneUnavailableNativeServices();
                          if (!context.mounted) return;
                          if (removed.isNotEmpty) {
                            await showServiceUnavailableDialog(context,
                                serviceNames: removed);
                            return;
                          }
                          context.push('/cart/checkout');
                        }
                      : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(
                    canCheckout ? 'Proceed to Checkout' : 'Minimum Order Not Met',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
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

// ── Sticky checkout bar — modal variant (desktop) ─────────────────────────────

class _ModalCheckoutBar extends ConsumerWidget {
  const _ModalCheckoutBar({required this.subtotal});
  final double subtotal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final items = ref.watch(cartProvider);
    var totalTax = 0.0;
    for (final item in items) {
      final taxSettings = ref.watch(resolvedTaxProvider((
        serviceId: item.serviceId,
        parentNodeId: item.parentNodeId,
      ))).valueOrNull ?? TaxSettingsModel.defaults;
      totalTax += taxSettings.computeTax(item.totalPrice);
    }
    final grandTotal = subtotal + totalTax;

    final globalMin = ref.watch(globalMinOrderAmountProvider).valueOrNull ?? 100.0;
    final checkItems = items.where((i) => !i.isAmc && !i.isCustomService).toList();
    CartItem? failingItem;
    double? effectiveFailingMin;
    for (final item in checkItems) {
      final effectiveMin = item.minimumOrderAmount ?? globalMin;
      if (effectiveMin > 0 && subtotal < effectiveMin) {
        failingItem = item;
        effectiveFailingMin = effectiveMin;
        break;
      }
    }
    final hasMinimum = failingItem != null ||
        checkItems.any((i) => (i.minimumOrderAmount ?? 0) > 0);
    final canCheckout = failingItem == null;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider, width: 0.8)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasMinimum) ...[
            MinOrderCard(effectiveMinimum: effectiveFailingMin, currentTotal: subtotal),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '₹${grandTotal.toInt()}',
                    style: tt.headlineSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'incl. taxes',
                    style: tt.labelSmall?.copyWith(color: AppColors.textHint),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  onPressed: canCheckout
                      ? () async {
                          final ok = await requireAuth(context, ref);
                          if (!ok || !context.mounted) return;
                          final removed = await ref
                              .read(cartProvider.notifier)
                              .pruneUnavailableNativeServices();
                          if (!context.mounted) return;
                          if (removed.isNotEmpty) {
                            await showServiceUnavailableDialog(context,
                                serviceNames: removed);
                            return;
                          }
                          PageSheet.show(
                            context,
                            title: 'Checkout',
                            child: const CheckoutScreen(inModal: true),
                          );
                        }
                      : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(
                    canCheckout ? 'Proceed to Checkout' : 'Minimum Order Not Met',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
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

// ══════════════════════════════════════════════════════════════════════════════
// "You might also want" — recommendation strip
// ══════════════════════════════════════════════════════════════════════════════

class _CartRecommendations extends ConsumerWidget {
  const _CartRecommendations();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodes = ref.watch(_cartRecommendationsProvider).valueOrNull;
    if (nodes == null || nodes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          'You might also want',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 248,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: 4),
            itemCount: nodes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (ctx, i) => _RecommendationCard(node: nodes[i]),
          ),
        ),
      ],
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.node});
  final CatalogNodeModel node;

  @override
  Widget build(BuildContext context) {
    final imageUrl = ServiceImageRegistry.resolveMobile(
      node.mobileImageUrl,
      node.imageUrl,
      node.name,
    );
    final price = node.finalPrice ?? node.basePrice;

    return SizedBox(
      width: 162,
      child: GestureDetector(
        onTap: () => openCatalogNode(context, node, parentId: node.parentId),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(10),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Hero image ───────────────────────────────────────────
                SizedBox(
                  height: 96,
                  width: double.infinity,
                  child: imageUrl != null
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: AppColors.primaryLight,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.home_repair_service_rounded,
                            size: 34,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : Container(
                        color: AppColors.primaryLight,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.home_repair_service_rounded,
                          size: 34,
                          color: AppColors.primary,
                        ),
                      ),
                ),

                // ── Content ──────────────────────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name
                        Text(
                          node.name,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),

                        const SizedBox(height: 4),

                        // Price
                        if (price != null)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '₹${price.toInt()}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              if (node.hasDiscount && node.basePrice != null) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '₹${node.basePrice!.toInt()}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textHint,
                                    decoration: TextDecoration.lineThrough,
                                    decorationColor: AppColors.textHint,
                                  ),
                                ),
                              ],
                            ],
                          ),

                        // Rating
                        if (node.rating > 0 && node.reviewCount > 0) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 12,
                                color: AppColors.gold,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                node.rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '(${node.reviewCount})',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textHint,
                                ),
                              ),
                            ],
                          ),
                        ],

                        const Spacer(),

                        // Action buttons
                        Row(
                          children: [
                            Expanded(
                              child: _RecButton(
                                label: 'View',
                                filled: false,
                                onTap: () => openCatalogNode(
                                  context,
                                  node,
                                  parentId: node.parentId,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _RecButton(
                                label: 'Add',
                                filled: true,
                                onTap: () => openCatalogNode(
                                  context,
                                  node,
                                  parentId: node.parentId,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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

class _RecButton extends StatelessWidget {
  const _RecButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });
  final String label;
  final bool filled;
  final VoidCallback onTap;

  static const _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(8)),
  );
  static const _textStyle =
      TextStyle(fontSize: 11, fontWeight: FontWeight.w600);

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return SizedBox(
        height: 28,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 28),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: _textStyle,
            shape: _shape,
          ),
          child: Text(label),
        ),
      );
    }
    return SizedBox(
      height: 28,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border, width: 0.8),
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: _textStyle,
          shape: _shape,
        ),
        child: Text(label),
      ),
    );
  }
}
