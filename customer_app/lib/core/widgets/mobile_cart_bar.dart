import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../features/cart/providers/cart_provider.dart';
import '../../features/cart/utils/cart_launcher.dart';

/// Compact floating cart summary bar shown on mobile when the cart has items.
///
/// [bottomPadding]: extra space below the bar content — pass
/// [MediaQuery.of(context).padding.bottom] when rendering as a free-floating
/// overlay so the bar clears the device home-indicator; leave at 0 when the
/// widget is already inside a Scaffold column that handles safe-area insets.
class MobileCartBar extends ConsumerWidget {
  final double bottomPadding;

  const MobileCartBar({
    super.key,
    this.bottomPadding = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartCount = ref.watch(cartItemCountProvider);
    final items = ref.watch(cartProvider);
    final categoryCount = items.length;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFECE7DE), width: 0.8),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 10,
            offset: Offset(0, -3),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottomPadding),
      child: Row(
        children: [
          // Cart icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF0EDE8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.shopping_cart_outlined,
              size: 22,
              color: Color(0xFF1A1714),
            ),
          ),
          const SizedBox(width: 12),
          // Item + category count
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$cartCount ${cartCount == 1 ? 'item' : 'items'} in cart',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1714),
                  ),
                ),
                Text(
                  'From $categoryCount ${categoryCount == 1 ? 'category' : 'categories'}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFF6E6A64),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // View button — black
          GestureDetector(
            onTap: () => openCart(context),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1714),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'View',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
