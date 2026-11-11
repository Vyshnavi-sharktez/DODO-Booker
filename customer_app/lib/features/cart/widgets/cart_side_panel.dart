import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/cart_item.dart';
import '../providers/cart_provider.dart';
import '../utils/cart_launcher.dart';

const double kCartSidePanelWidth = 300.0;

const Color _kBorderColor = Color(0xFFE5E5E5);
const Color _kTextDark    = Color(0xFF111111);
const Color _kTextMid     = Color(0xFF333333);
const Color _kTextMuted   = Color(0xFF6B6B6B);

class CartSidePanel extends ConsumerWidget {
  const CartSidePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(cartProvider);
    final total = items.fold(0.0, (sum, i) => sum + i.totalPrice);

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _kBorderColor)),
            ),
            child: Text(
              'Cart (${items.length})',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _kTextDark,
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) => _CartPanelItem(item: items[i]),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _kBorderColor)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total',
                        style: GoogleFonts.inter(
                            fontSize: 13, color: _kTextMuted)),
                    Text(
                      '₹${total.toInt()}',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _kTextDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => openCheckout(context, ref),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: _kTextDark,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Center(
                        child: Text(
                          'Proceed to Checkout',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
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

class _CartPanelItem extends ConsumerStatefulWidget {
  final CartItem item;
  const _CartPanelItem({required this.item});

  @override
  ConsumerState<_CartPanelItem> createState() => _CartPanelItemState();
}

class _CartPanelItemState extends ConsumerState<_CartPanelItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final addonsTotal = item.addons.fold(0.0, (s, a) => s + a.addonPrice);
    final basePrice = item.unitPrice - addonsTotal;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F7F7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.serviceName,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _kTextDark,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.isAmc
                              ? '₹${item.unitPrice.toInt()} (AMC)'
                              : '₹${item.unitPrice.toInt()} × ${item.quantity}',
                          style: GoogleFonts.inter(
                              fontSize: 12, color: _kTextMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        size: 16, color: _kTextMuted),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => ref
                        .read(cartProvider.notifier)
                        .removeFromCart(item.bookingId),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEEEEE),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.close_rounded,
                          size: 14, color: _kTextMid),
                    ),
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 10),
                const Divider(
                    height: 0, thickness: 0.8, color: _kBorderColor),
                const SizedBox(height: 10),
                if (item.isAmc) ...[
                  _BreakdownRow(
                    label: item.amcPlanName?.isNotEmpty == true
                        ? item.amcPlanName!
                        : 'AMC Plan',
                    value:
                        '₹${(item.amcFinalPrice ?? item.unitPrice).toInt()}',
                  ),
                  if ((item.amcRecurrenceInterval?.isNotEmpty == true) ||
                      item.amcNumVisits != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        [
                          if (item.amcRecurrenceInterval?.isNotEmpty == true)
                            item.amcRecurrenceInterval!,
                          if (item.amcNumVisits != null)
                            '${item.amcNumVisits} visits',
                        ].join(' - '),
                        style: GoogleFonts.inter(
                            fontSize: 10, color: _kTextMuted),
                      ),
                    ),
                  if (item.amcIsRenewal)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text('Renewal',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: _kTextMid,
                            fontWeight: FontWeight.w600,
                          )),
                    ),
                  if (item.amcQuantity > 1) ...[
                    const SizedBox(height: 4),
                    _BreakdownRow(
                      label: '× ${item.amcQuantity} units',
                      value: '₹${item.unitPrice.toInt()}',
                      muted: true,
                    ),
                  ],
                ] else ...[
                  _BreakdownRow(
                    label: 'Base service',
                    value: '₹${basePrice.toInt()}',
                    originalValue: item.originalUnitPrice != null
                        ? '₹${item.originalUnitPrice!.toInt()}'
                        : null,
                  ),
                  ...item.addons.map((a) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: _BreakdownRow(
                          label: '+ ${a.addonName}',
                          value: '₹${a.addonPrice.toInt()}',
                          originalValue: a.originalAddonPrice != null
                              ? '₹${a.originalAddonPrice!.toInt()}'
                              : null,
                          muted: true,
                        ),
                      )),
                  if (item.quantity > 1) ...[
                    const SizedBox(height: 4),
                    _BreakdownRow(
                      label: 'Qty: ${item.quantity}',
                      value: '₹${item.totalPrice.toInt()} total',
                      muted: true,
                    ),
                  ],
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.value,
    this.originalValue,
    this.muted = false,
  });
  final String label;
  final String value;
  final String? originalValue;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = muted ? _kTextMuted : _kTextDark;
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: GoogleFonts.inter(fontSize: 11, color: color)),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: color,
            fontWeight: muted ? FontWeight.w400 : FontWeight.w600,
          ),
        ),
        if (originalValue != null) ...[
          const SizedBox(width: 5),
          Text(
            originalValue!,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: _kTextMuted,
              decoration: TextDecoration.lineThrough,
              decorationColor: _kTextMuted,
            ),
          ),
        ],
      ],
    );
  }
}
