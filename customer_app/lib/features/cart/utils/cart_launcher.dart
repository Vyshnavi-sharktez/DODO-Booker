import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/page_sheet.dart';
import '../screens/cart_screen.dart';

/// Opens the cart as a floating [PageSheet] dialog on desktop/web (≥768 px),
/// or navigates to the full-screen route on mobile.
///
/// Use this everywhere instead of calling [context.go('/cart')] directly
/// so that the desktop experience is always consistent.
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
