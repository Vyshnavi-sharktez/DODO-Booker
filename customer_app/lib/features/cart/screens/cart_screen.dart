import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../models/cart_item.dart';
import '../providers/cart_provider.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(cartProvider);
    final subtotal = ref.watch(cartSubtotalProvider);

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
      body: items.isEmpty
          ? const _EmptyCart()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                ...items.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _CartItemCard(item: item),
                    )),
                const SizedBox(height: 8),
                _CartSummaryCard(items: items, subtotal: subtotal),
                // Padding so the sticky bar doesn't overlap the last row
                const SizedBox(height: 84),
              ],
            ),
      bottomNavigationBar:
          items.isEmpty ? null : _CheckoutBar(subtotal: subtotal),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

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
              onPressed: () => context.go('/'),
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

class _CartItemCard extends ConsumerWidget {
  final CartItem item;

  const _CartItemCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final notifier = ref.read(cartProvider.notifier);

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
            // Top row: image + name/price + delete
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
                          GestureDetector(
                            onTap: () =>
                                notifier.removeFromCart(item.serviceId),
                            child: const Icon(
                              Icons.delete_outline_rounded,
                              size: 20,
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
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
            const Divider(color: AppColors.divider, height: 0, thickness: 0.8),
            const SizedBox(height: 12),

            // Bottom row: qty stepper + line total
            Row(
              children: [
                _QuantityStepper(
                  quantity: item.quantity,
                  onDecrement: () =>
                      notifier.updateQuantity(item.serviceId, item.quantity - 1),
                  onIncrement: () =>
                      notifier.updateQuantity(item.serviceId, item.quantity + 1),
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
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Icon(icon, size: 16, color: AppColors.primary),
      ),
    );
  }
}

// ── Cart summary card (in scroll) ─────────────────────────────────────────────

class _CartSummaryCard extends StatelessWidget {
  final List<CartItem> items;
  final double subtotal;

  const _CartSummaryCard({required this.items, required this.subtotal});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final totalItems = items.fold<int>(0, (sum, item) => sum + item.quantity);
    final tax = subtotal * 0.18;
    final grandTotal = subtotal + tax;

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
          const SizedBox(height: 10),
          _SummaryRow(
            label: 'Estimated tax (18%)',
            value: '₹${tax.toInt()}',
            tt: tt,
          ),
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

// ── Sticky checkout bar ───────────────────────────────────────────────────────

class _CheckoutBar extends StatelessWidget {
  final double subtotal;

  const _CheckoutBar({required this.subtotal});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final grandTotal = subtotal * 1.18;

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
              onPressed: () => context.go('/cart/checkout'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text(
                'Proceed to Checkout',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
