import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/address_model.dart';
import '../../../models/coupon_model.dart';
import '../../../models/time_slot_model.dart';
import '../../../features/booking/services/booking_providers.dart';
import '../../../features/booking/widgets/available_coupons_sheet.dart';
import '../models/cart_item.dart';
import '../providers/cart_provider.dart';
import '../services/checkout_service.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  AddressModel? _selectedAddress;
  DateTime? _selectedDate;
  TimeSlotModel? _selectedSlot;
  CouponModel? _selectedCoupon;
  bool _placing = false;

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatDate(DateTime d) =>
      '${d.day} ${_monthNames[d.month - 1]} ${d.year}';

  double get _subtotal =>
      ref.read(cartSubtotalProvider);

  double get _discount =>
      _selectedCoupon?.calculateDiscount(_subtotal) ?? 0.0;

  double get _tax => _subtotal * 0.18;

  double get _grandTotal =>
      (_subtotal + _tax - _discount).clamp(0.0, double.infinity);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
                primary: AppColors.primary,
              ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _selectedSlot = null; // reset slot when date changes
      });
    }
  }

  Future<void> _pickCoupon() async {
    final result = await showModalBottomSheet<CouponModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AvailableCouponsSheet(
        subtotal: _subtotal,
        selectedCoupon: _selectedCoupon,
      ),
    );
    if (result != null) {
      setState(() => _selectedCoupon = result);
    }
  }

  Future<void> _placeBooking() async {
    final items = ref.read(cartProvider);
    if (items.isEmpty) return;

    if (_selectedAddress == null) {
      _showError('Please select a delivery address.');
      return;
    }
    if (_selectedDate == null) {
      _showError('Please select a service date.');
      return;
    }
    if (_selectedSlot == null) {
      _showError('Please select a time slot.');
      return;
    }

    setState(() => _placing = true);
    try {
      final booking = await CheckoutService().createCartBooking(
        items: items,
        address: _selectedAddress!,
        date: _selectedDate!,
        slot: _selectedSlot!,
        couponId: _selectedCoupon?.id,
        discountAmount: _discount,
      );

      ref.read(cartProvider.notifier).clearCart();

      if (!mounted) return;
      context.go('/booking-success', extra: booking);
    } catch (e) {
      if (!mounted) return;
      _showError('Booking failed: $e');
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(cartProvider);
    final addressAsync = ref.watch(addressNotifierProvider);
    final dateStr =
        _selectedDate?.toIso8601String().substring(0, 10);
    final slotsAsync =
        dateStr != null ? ref.watch(timeSlotsProvider(dateStr)) : null;

    // Pre-select the default address once loaded
    addressAsync.whenData((list) {
      if (_selectedAddress == null && list.isNotEmpty) {
        final def = list.firstWhere(
          (a) => a.isDefault,
          orElse: () => list.first,
        );
        // Use post-frame to avoid setState during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _selectedAddress == null) {
            setState(() => _selectedAddress = def);
          }
        });
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Checkout'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.8),
          child: Container(height: 0.8, color: AppColors.divider),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // ── Cart Items (read-only review) ───────────────────────────────
          _SectionCard(
            title: 'Order Summary',
            child: Column(
              children: [
                ...items.map((item) => _OrderItemRow(item: item)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Address ─────────────────────────────────────────────────────
          _SectionCard(
            title: 'Service Address',
            trailing: TextButton(
              onPressed: () async {
                await context.push('/address');
                ref.invalidate(addressNotifierProvider);
              },
              child: const Text('Manage'),
            ),
            child: addressAsync.when(
              loading: () => const Center(
                  child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(strokeWidth: 2),
              )),
              error: (e, _) => _ErrorRow(
                message: 'Could not load addresses',
                onRetry: () => ref.invalidate(addressNotifierProvider),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No saved addresses.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await context.push('/address');
                            ref.invalidate(addressNotifierProvider);
                          },
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('Add Address'),
                        ),
                      ],
                    ),
                  );
                }
                return Column(
                  children: list
                      .map((addr) => _AddressRadioTile(
                            address: addr,
                            selected: _selectedAddress?.id == addr.id,
                            onTap: () =>
                                setState(() => _selectedAddress = addr),
                          ))
                      .toList(),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // ── Date ─────────────────────────────────────────────────────────
          _SectionCard(
            title: 'Service Date',
            child: GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _selectedDate != null
                        ? AppColors.primary
                        : AppColors.border,
                    width: _selectedDate != null ? 1.5 : 1,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  color: _selectedDate != null
                      ? AppColors.primary.withAlpha(10)
                      : AppColors.surfaceVariant,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 18,
                      color: _selectedDate != null
                          ? AppColors.primary
                          : AppColors.textHint,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _selectedDate != null
                          ? _formatDate(_selectedDate!)
                          : 'Select a date',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: _selectedDate != null
                                ? AppColors.textPrimary
                                : AppColors.textHint,
                            fontWeight: _selectedDate != null
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                    ),
                    const Spacer(),
                    const Icon(Icons.chevron_right_rounded,
                        size: 18, color: AppColors.textHint),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Time Slot ─────────────────────────────────────────────────────
          _SectionCard(
            title: 'Time Slot',
            child: _selectedDate == null
                ? Text(
                    'Select a date first.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.textHint),
                  )
                : slotsAsync!.when(
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    error: (e, _) => _ErrorRow(
                      message: 'Could not load time slots',
                      onRetry: () =>
                          ref.invalidate(timeSlotsProvider(dateStr!)),
                    ),
                    data: (slots) => _SlotGrid(
                      slots: slots,
                      selected: _selectedSlot,
                      onSelect: (s) =>
                          setState(() => _selectedSlot = s),
                    ),
                  ),
          ),
          const SizedBox(height: 16),

          // ── Coupon ────────────────────────────────────────────────────────
          _SectionCard(
            title: 'Coupon',
            child: _selectedCoupon == null
                ? OutlinedButton.icon(
                    onPressed: _pickCoupon,
                    icon: const Icon(Icons.local_offer_outlined, size: 16),
                    label: const Text('Apply Coupon'),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44)),
                  )
                : _AppliedCouponRow(
                    coupon: _selectedCoupon!,
                    subtotal: _subtotal,
                    onRemove: () =>
                        setState(() => _selectedCoupon = null),
                    onChange: _pickCoupon,
                  ),
          ),
          const SizedBox(height: 16),

          // ── Price Summary ─────────────────────────────────────────────────
          _SectionCard(
            title: 'Price Summary',
            child: _PriceSummary(
              subtotal: _subtotal,
              discount: _discount,
              tax: _tax,
              grandTotal: _grandTotal,
            ),
          ),

          // Extra space for sticky button
          const SizedBox(height: 100),
        ],
      ),

      // ── Sticky Place Booking bar ──────────────────────────────────────────
      bottomNavigationBar: _PlaceBookingBar(
        grandTotal: _grandTotal,
        loading: _placing,
        enabled: !_placing && items.isNotEmpty,
        onPressed: _placeBooking,
      ),
    );
  }
}

// ── Section Card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
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
              Text(title,
                  style:
                      tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              if (trailing != null) ...[
                const Spacer(),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ── Order item row (read-only) ────────────────────────────────────────────────

class _OrderItemRow extends StatelessWidget {
  final CartItem item;

  const _OrderItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.serviceName,
              style: tt.bodySmall?.copyWith(color: AppColors.textPrimary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${item.quantity} × ₹${item.unitPrice.toInt()}',
            style:
                tt.labelSmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(width: 8),
          Text(
            '₹${item.totalPrice.toInt()}',
            style: tt.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Address radio tile ────────────────────────────────────────────────────────

class _AddressRadioTile extends StatelessWidget {
  final AddressModel address;
  final bool selected;
  final VoidCallback onTap;

  const _AddressRadioTile({
    required this.address,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color:
                selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
          color: selected
              ? AppColors.primary.withAlpha(10)
              : AppColors.surface,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 20,
              color: selected
                  ? AppColors.primary
                  : AppColors.textHint,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        address.label,
                        style: tt.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700),
                      ),
                      if (address.isDefault) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withAlpha(20),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Default',
                            style: tt.labelSmall?.copyWith(
                              color: AppColors.primary,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    address.fullAddress,
                    style: tt.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Slot grid ─────────────────────────────────────────────────────────────────

class _SlotGrid extends StatelessWidget {
  final List<TimeSlotModel> slots;
  final TimeSlotModel? selected;
  final ValueChanged<TimeSlotModel> onSelect;

  const _SlotGrid({
    required this.slots,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final groups = <SlotPeriod, List<TimeSlotModel>>{};
    for (final s in slots) {
      groups.putIfAbsent(s.period, () => []).add(s);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: groups.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: Text(
                entry.key.label,
                style: tt.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: entry.value.map((slot) {
                final isSelected = selected?.id == slot.id;
                return GestureDetector(
                  onTap: slot.isAvailable ? () => onSelect(slot) : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : slot.isAvailable
                              ? AppColors.surfaceVariant
                              : AppColors.border.withAlpha(60),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.border,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      slot.label,
                      style: tt.labelSmall?.copyWith(
                        color: isSelected
                            ? Colors.white
                            : slot.isAvailable
                                ? AppColors.textPrimary
                                : AppColors.textHint,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
          ],
        );
      }).toList(),
    );
  }
}

// ── Applied coupon row ────────────────────────────────────────────────────────

class _AppliedCouponRow extends StatelessWidget {
  final CouponModel coupon;
  final double subtotal;
  final VoidCallback onRemove;
  final VoidCallback onChange;

  const _AppliedCouponRow({
    required this.coupon,
    required this.subtotal,
    required this.onRemove,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final discount = coupon.calculateDiscount(subtotal);
    return Row(
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            coupon.code,
            style: tt.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Save ₹${discount.toStringAsFixed(0)}',
            style: tt.bodySmall?.copyWith(
              color: AppColors.success,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        TextButton(
          onPressed: onChange,
          style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8)),
          child: const Text('Change'),
        ),
        GestureDetector(
          onTap: onRemove,
          child: const Icon(Icons.close_rounded,
              size: 18, color: AppColors.textHint),
        ),
      ],
    );
  }
}

// ── Price summary ─────────────────────────────────────────────────────────────

class _PriceSummary extends StatelessWidget {
  final double subtotal;
  final double discount;
  final double tax;
  final double grandTotal;

  const _PriceSummary({
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.grandTotal,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      children: [
        _Row(label: 'Subtotal', value: '₹${subtotal.toInt()}', tt: tt),
        if (discount > 0) ...[
          const SizedBox(height: 8),
          _Row(
            label: 'Discount',
            value: '- ₹${discount.toStringAsFixed(0)}',
            tt: tt,
            valueColor: AppColors.success,
          ),
        ],
        const SizedBox(height: 8),
        _Row(
            label: 'Tax (18%)', value: '₹${tax.toInt()}', tt: tt),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Divider(color: AppColors.divider, height: 0),
        ),
        _Row(
          label: 'Total',
          value: '₹${grandTotal.toInt()}',
          tt: tt,
          bold: true,
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final TextTheme tt;
  final bool bold;
  final Color? valueColor;

  const _Row({
    required this.label,
    required this.value,
    required this.tt,
    this.bold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final base = bold
        ? tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)
        : tt.bodySmall?.copyWith(color: AppColors.textSecondary);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: base),
        Text(
          value,
          style: base?.copyWith(
            color: valueColor ?? (bold ? AppColors.primary : null),
          ),
        ),
      ],
    );
  }
}

// ── Error row ─────────────────────────────────────────────────────────────────

class _ErrorRow extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorRow({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.error_outline_rounded,
            size: 16, color: AppColors.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.error)),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}

// ── Sticky place booking bar ──────────────────────────────────────────────────

class _PlaceBookingBar extends StatelessWidget {
  final double grandTotal;
  final bool loading;
  final bool enabled;
  final VoidCallback onPressed;

  const _PlaceBookingBar({
    required this.grandTotal,
    required this.loading,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
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
              onPressed: enabled ? onPressed : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Place Booking',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
