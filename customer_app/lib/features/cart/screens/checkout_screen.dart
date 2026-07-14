import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/clickable.dart';
import '../../../core/widgets/page_sheet.dart';
import '../../../models/address_model.dart';
import '../../../models/coupon_model.dart';
import '../../../models/time_slot_model.dart';
import '../../../features/booking/services/booking_providers.dart';
import '../../../features/booking/widgets/available_coupons_sheet.dart';
import '../../../features/booking/widgets/booking_success_dialog.dart';
import '../../../features/address/screens/address_screen.dart';
import '../../../features/bookings/utils/my_bookings_launcher.dart';
import '../../../features/address/services/address_providers.dart';
import '../models/cart_item.dart';
import '../providers/cart_provider.dart';
import '../services/checkout_service.dart';
import '../widgets/payment_selection_sheet.dart';
import '../../bookings/services/bookings_providers.dart';
import '../../loyalty/providers/loyalty_providers.dart';
import '../../loyalty/services/loyalty_service.dart';
import '../../tax/models/tax_settings_model.dart';
import '../../tax/providers/tax_provider.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  final bool inModal;
  const CheckoutScreen({super.key, this.inModal = false});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  AddressModel? _selectedAddress;
  DateTime? _selectedDate;
  TimeSlotModel? _selectedSlot;
  CouponModel? _selectedCoupon;
  bool _usePoints = false;
  bool _placing = false;
  TaxSettingsModel _taxSettings = TaxSettingsModel.defaults;

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

  double get _tax => _taxSettings.computeTax(_subtotal);

  int get _availablePoints {
    return ref
            .read(customerLoyaltyProvider)
            .whenOrNull(data: (l) => l.availablePoints) ??
        0;
  }

  int get _loyaltyRedeemPoints {
    if (!_usePoints) return 0;
    final settings = ref
        .read(loyaltySettingsProvider)
        .whenOrNull(data: (s) => s);
    if (settings == null || !settings.isEnabled || !settings.redeemEnabled) {
      return 0;
    }
    if (_availablePoints < settings.minRedeemPoints) return 0;
    final baseTotal = _subtotal + _tax - _discount;
    final maxDiscount = baseTotal * settings.maxRedeemPercentage / 100;
    return _availablePoints.clamp(0, maxDiscount.floor());
  }

  double get _loyaltyDiscount => _loyaltyRedeemPoints.toDouble();

  double get _grandTotal =>
      (_subtotal + _tax - _discount - _loyaltyDiscount)
          .clamp(0.0, double.infinity);

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

  Future<String?> _selectPaymentMethod() {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PaymentSelectionSheet(),
    );
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

    // ── Minimum order amount ─────────────────────────────────────────────────
    for (final item in items) {
      final minAmt = item.minimumOrderAmount;
      if (minAmt != null && item.totalPrice < minAmt) {
        _showError(
          '"${item.serviceName}" requires a minimum order of '
          '₹${minAmt.toInt()}. '
          'Current total for this item: ₹${item.totalPrice.toInt()}.',
        );
        return;
      }
    }

    // ── Payment method selection ─────────────────────────────────────────────
    final paymentMethod = await _selectPaymentMethod();
    if (!mounted || paymentMethod == null) return;

    final redeemPoints = _loyaltyRedeemPoints;

    debugPrint('[DODO][Checkout] _placeBooking starting — inModal=${widget.inModal}');
    setState(() => _placing = true);
    debugPrint('[DODO][Checkout] _placing=true');
    try {
      debugPrint('[DODO][Checkout] → awaiting createCartBooking...');
      final booking = await CheckoutService().createCartBooking(
        items: items,
        address: _selectedAddress!,
        date: _selectedDate!,
        slot: _selectedSlot!,
        couponId: _selectedCoupon?.id,
        discountAmount: _discount + _loyaltyDiscount,
        taxAmount: _tax,
        paymentMethod: paymentMethod,
      );
      debugPrint('[DODO][Checkout] ✓ createCartBooking returned — id=${booking.id}');
      ref.invalidate(myBookingsProvider);

      // Record loyalty redemption after booking is confirmed
      if (redeemPoints > 0) {
        debugPrint('[DODO][Checkout] → awaiting recordRedemption($redeemPoints pts)...');
        try {
          await LoyaltyService().recordRedemption(
            bookingId: booking.id,
            points: redeemPoints,
          );
          debugPrint('[DODO][Checkout] ✓ recordRedemption done');
          ref.invalidate(customerLoyaltyProvider);
          ref.invalidate(loyaltyTransactionsProvider);
        } catch (e) {
          debugPrint('[DODO][Checkout] Loyalty redemption record failed (non-fatal): $e');
        }
      }

      debugPrint('[DODO][Checkout] → clearCart()');
      ref.read(cartProvider.notifier).clearCart();
      debugPrint('[DODO][Checkout] ✓ clearCart done');

      debugPrint('[DODO][Checkout] mounted=$mounted (pre-dialog check)');
      if (!mounted) {
        debugPrint('[DODO][Checkout] ✗ unmounted before dialog — returning');
        return;
      }
      if (widget.inModal) {
        // Capture the root navigator before the dialog opens.
        // After popUntil runs inside the callbacks, this NavigatorState and
        // its .context remain valid (the Navigator itself is never popped).
        final navigator = Navigator.of(context);
        debugPrint('[DODO][Checkout] → showBookingSuccessDialog (inModal path)');
        await showBookingSuccessDialog(
          context,
          booking,
          onClose: () {
            debugPrint('[DODO][SuccessDialog] onClose → popUntil(isFirst)');
            navigator.popUntil((route) => route.isFirst);
            debugPrint('[DODO][SuccessDialog] onClose popUntil done');
          },
          onViewBookings: () {
            debugPrint('[DODO][SuccessDialog] onViewBookings → popUntil(isFirst)');
            navigator.popUntil((route) => route.isFirst);
            debugPrint('[DODO][SuccessDialog] onViewBookings popUntil done — openMyBookings');
            openMyBookings(navigator.context);
          },
        );
        debugPrint('[DODO][Checkout] ✓ showBookingSuccessDialog awaited/returned');
      } else {
        debugPrint('[DODO][Checkout] → context.go(/booking-success)');
        context.go('/booking-success', extra: booking);
        debugPrint('[DODO][Checkout] ✓ context.go called');
      }
    } catch (e) {
      debugPrint('[DODO][Checkout] ✗ exception: $e');
      if (!mounted) {
        debugPrint('[DODO][Checkout] ✗ unmounted in catch — cannot show error');
        return;
      }
      _showError('Booking failed: $e');
    } finally {
      debugPrint('[DODO][Checkout] finally — mounted=$mounted');
      if (mounted) setState(() => _placing = false);
      debugPrint('[DODO][Checkout] finally done');
    }
  }

  Future<void> _openAddressScreen() async {
    if (widget.inModal) {
      await PageSheet.show(
        context,
        title: 'My Addresses',
        child: const AddressScreen(inModal: true),
      );
    } else {
      await context.push('/address');
    }
    if (mounted) ref.invalidate(addressNotifierProvider);
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

    // Cache tax settings so _tax getter and _placeBooking() stay in sync.
    // Falls back to defaults (18% GST) until the provider resolves.
    ref.watch(taxSettingsProvider).whenData((s) => _taxSettings = s);
    final dateStr =
        _selectedDate?.toIso8601String().substring(0, 10);
    final serviceId =
        items.isNotEmpty ? items.first.serviceId : '';
    final slotsAsync = dateStr != null
        ? ref.watch(timeSlotsProvider((date: dateStr, serviceId: serviceId)))
        : null;

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

    // ── Shared list content ─────────────────────────────────────────────────
    final listChildren = <Widget>[
      // Cart Items (read-only review)
      _SectionCard(
        title: 'Order Summary',
        child: Column(
          children: [
            ...items.map((item) => _OrderItemRow(item: item)),
          ],
        ),
      ),
      const SizedBox(height: 16),

      // Address
      _SectionCard(
        title: 'Service Address',
        trailing: TextButton(
          onPressed: _openAddressScreen,
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
                      onPressed: _openAddressScreen,
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

      // Date
      _SectionCard(
        title: 'Service Date',
        child: Clickable(
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

      // Time Slot
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
                  onRetry: () => ref.invalidate(
                    timeSlotsProvider((date: dateStr!, serviceId: serviceId)),
                  ),
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

      // Coupon
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

      // Loyalty Points
      _LoyaltySection(
        usePoints: _usePoints,
        onToggle: (v) => setState(() => _usePoints = v),
        redeemPoints: _loyaltyRedeemPoints,
        availablePoints: _availablePoints,
      ),
      const SizedBox(height: 16),

      // Price Summary
      _SectionCard(
        title: 'Price Summary',
        child: _PriceSummary(
          subtotal: _subtotal,
          discount: _discount,
          loyaltyDiscount: _loyaltyDiscount,
          tax: _tax,
          grandTotal: _grandTotal,
          taxLabel: _taxSettings.displayLabel,
          showTaxLine: _taxSettings.isEnabled &&
              _taxSettings.applyOnServices &&
              _taxSettings.displaySeparately,
        ),
      ),
    ];

    final placeBar = _PlaceBookingBar(
      grandTotal: _grandTotal,
      loading: _placing,
      enabled: !_placing && items.isNotEmpty,
      onPressed: _placeBooking,
    );

    // ── Modal layout: Column with bounded Expanded + sticky footer ───────────
    // Avoids embedding Scaffold inside PageSheet, which produces zero-size
    // RenderBox errors during hit-testing (box.dart / shifted_box.dart).
    if (widget.inModal) {
      return Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: listChildren,
            ),
          ),
          placeBar,
        ],
      );
    }

    // ── Full-screen layout: standard Scaffold ────────────────────────────────
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
        children: [...listChildren, const SizedBox(height: 100)],
      ),
      bottomNavigationBar: placeBar,
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
    return Clickable(
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
                return Clickable(
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
        Clickable(
          onTap: onRemove,
          child: const Icon(Icons.close_rounded,
              size: 18, color: AppColors.textHint),
        ),
      ],
    );
  }
}

// ── Loyalty section ───────────────────────────────────────────────────────────

class _LoyaltySection extends ConsumerWidget {
  final bool usePoints;
  final ValueChanged<bool> onToggle;
  final int redeemPoints;
  final int availablePoints;

  const _LoyaltySection({
    required this.usePoints,
    required this.onToggle,
    required this.redeemPoints,
    required this.availablePoints,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(loyaltySettingsProvider);

    return settingsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (settings) {
        if (!settings.isEnabled || !settings.redeemEnabled) {
          return const SizedBox.shrink();
        }
        if (availablePoints == 0) return const SizedBox.shrink();

        final canRedeem = availablePoints >= settings.minRedeemPoints;

        return _SectionCard(
          title: 'Loyalty Points',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.stars_rounded,
                      size: 16, color: Color(0xFFFFD700)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$availablePoints pts available',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                  Switch(
                    value: usePoints && canRedeem,
                    onChanged: canRedeem ? onToggle : null,
                    activeColor: AppColors.primary,
                  ),
                ],
              ),
              if (!canRedeem) ...[
                const SizedBox(height: 4),
                Text(
                  'Need ${settings.minRedeemPoints} pts minimum to redeem.',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textHint,
                      ),
                ),
              ] else if (usePoints && redeemPoints > 0) ...[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFFFD700).withAlpha(80),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded,
                          size: 14, color: Color(0xFFFFD700)),
                      const SizedBox(width: 6),
                      Text(
                        'Saving ₹$redeemPoints using $redeemPoints pts',
                        style:
                            Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: const Color(0xFFB8860B),
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ── Price summary ─────────────────────────────────────────────────────────────

class _PriceSummary extends StatelessWidget {
  final double subtotal;
  final double discount;
  final double loyaltyDiscount;
  final double tax;
  final double grandTotal;
  final String taxLabel;
  final bool showTaxLine;

  const _PriceSummary({
    required this.subtotal,
    required this.discount,
    required this.loyaltyDiscount,
    required this.tax,
    required this.grandTotal,
    this.taxLabel = 'GST (18%)',
    this.showTaxLine = true,
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
            label: 'Coupon Discount',
            value: '- ₹${discount.toStringAsFixed(0)}',
            tt: tt,
            valueColor: AppColors.success,
          ),
        ],
        if (loyaltyDiscount > 0) ...[
          const SizedBox(height: 8),
          _Row(
            label: 'Loyalty Points',
            value: '- ₹${loyaltyDiscount.toInt()}',
            tt: tt,
            valueColor: const Color(0xFFFFD700),
          ),
        ],
        if (showTaxLine && tax > 0) ...[
          const SizedBox(height: 8),
          _Row(label: taxLabel, value: '₹${tax.toInt()}', tt: tt),
        ],
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
