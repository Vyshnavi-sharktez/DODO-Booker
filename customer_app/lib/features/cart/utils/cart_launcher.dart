import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/page_sheet.dart';
import '../../auth/utils/auth_modal_gate.dart';
import '../providers/cart_provider.dart';
import '../screens/cart_screen.dart';
import '../screens/checkout_screen.dart';
import '../widgets/service_unavailable_dialog.dart';

void openCart(BuildContext context) {
  if (MediaQuery.of(context).size.width >= 768) {
    PageSheet.show(
      context,
      title: 'My Cart',
      child: const CartScreen(inModal: true),
    );
  } else {
    context.push('/cart');
  }
}

Future<void> openCheckout(BuildContext context, WidgetRef ref) async {
  final authed = await requireAuth(context, ref);
  if (!authed || !context.mounted) return;

  // Block checkout if any DODO service was paused after being added to cart.
  final removed =
      await ref.read(cartProvider.notifier).pruneUnavailableNativeServices();
  if (!context.mounted) return;
  if (removed.isNotEmpty) {
    await showServiceUnavailableDialog(context, serviceNames: removed);
    return;
  }

  if (MediaQuery.of(context).size.width >= 768) {
    PageSheet.show(
      context,
      title: 'Checkout',
      child: const CheckoutScreen(inModal: true),
    );
  } else {
    context.push('/cart/checkout');
  }
}
