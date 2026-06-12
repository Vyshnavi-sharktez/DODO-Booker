import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_modal_dialog.dart';
import '../../../models/service_model.dart';
import '../../../models/address_model.dart';
import '../../../models/time_slot_model.dart';
import '../../../models/coupon_model.dart';
import '../services/coupon_providers.dart';
import '../widgets/booking_summary_card.dart';
import '../widgets/available_coupons_sheet.dart';

/// Booking summary modal. Pops with `true` when the user confirms booking.
class BookingSummaryModal extends ConsumerStatefulWidget {
  final ServiceModel service;
  final AddressModel address;
  final DateTime date;
  final TimeSlotModel slot;

  const BookingSummaryModal({
    super.key,
    required this.service,
    required this.address,
    required this.date,
    required this.slot,
  });

  @override
  ConsumerState<BookingSummaryModal> createState() => _BookingSummaryModalState();
}

class _BookingSummaryModalState extends ConsumerState<BookingSummaryModal> {
  final _couponController = TextEditingController();
  bool _applying = false;
  String? _errorText;

  @override
  void dispose() {
    _couponController.dispose();
    super.dispose();
  }

  // Subtotal = base price + 18% GST
  double get _subtotal => widget.service.startingPrice * 1.18;

  Future<void> _applyCoupon() async {
    final code = _couponController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _errorText = 'Enter a coupon code.');
      return;
    }

    setState(() {
      _applying = true;
      _errorText = null;
    });

    try {
      debugPrint('[DODO][Coupon] Applying code: $code');
      final coupons = await ref.read(activeCouponsProvider.future);

      final found = coupons.where((c) => c.code.toUpperCase() == code).firstOrNull;

      if (found == null) {
        setState(() => _errorText = 'Coupon code not found.');
        debugPrint('[DODO][Coupon] Code not found: $code');
        return;
      }

      final error = found.validate(_subtotal);
      if (error != null) {
        setState(() => _errorText = error);
        debugPrint('[DODO][Coupon] Validation failed for $code: $error');
        return;
      }

      final discount = found.calculateDiscount(_subtotal);
      ref.read(selectedCouponProvider.notifier).state = found;
      debugPrint('[DODO][Coupon] Coupon applied: ${found.code} — discount ₹${discount.toStringAsFixed(2)}');
      setState(() => _errorText = null);
    } catch (e) {
      setState(() => _errorText = 'Could not verify coupon. Try again.');
      debugPrint('[DODO][Coupon] Error applying coupon: $e');
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  void _removeCoupon() {
    ref.read(selectedCouponProvider.notifier).state = null;
    _couponController.clear();
    setState(() => _errorText = null);
    debugPrint('[DODO][Coupon] Coupon removed');
  }

  Future<void> _showCouponsSheet() async {
    setState(() => _errorText = null);
    final coupon = await showModalBottomSheet<CouponModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AvailableCouponsSheet(
        subtotal: _subtotal,
        selectedCoupon: ref.read(selectedCouponProvider),
      ),
    );
    if (coupon == null || !mounted) return;
    _couponController.text = coupon.code;
    ref.read(selectedCouponProvider.notifier).state = coupon;
    debugPrint(
      '[DODO][Coupon] Coupon applied: ${coupon.code}'
      ' — discount ₹${coupon.calculateDiscount(_subtotal).toStringAsFixed(2)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final selectedCoupon = ref.watch(selectedCouponProvider);
    final discount = selectedCoupon?.calculateDiscount(_subtotal) ?? 0.0;

    return AppModalDialog(
      title: 'Review Booking',
      contentPadding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BookingSummaryCard(
            service: widget.service,
            address: widget.address,
            date: widget.date,
            slot: widget.slot,
            discountAmount: discount,
            couponCode: selectedCoupon?.code,
          ),

          // ── Coupon input / applied state ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: selectedCoupon == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _couponController,
                              textCapitalization: TextCapitalization.characters,
                              decoration: InputDecoration(
                                hintText: 'Enter coupon code',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                errorText: _errorText,
                              ),
                              onSubmitted: (_) => _applyCoupon(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            height: 44,
                            child: FilledButton(
                              onPressed: _applying ? null : _applyCoupon,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                              ),
                              child: _applying
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Apply'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: _showCouponsSheet,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.local_offer_outlined,
                              size: 12,
                              color: AppColors.primary,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'View Available Coupons',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.success.withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.success.withAlpha(80)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selectedCoupon.code,
                                style: tt.labelMedium?.copyWith(
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${selectedCoupon.discountLabel} applied',
                                style: tt.labelSmall?.copyWith(color: AppColors.success),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _removeCoupon,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            foregroundColor: AppColors.error,
                          ),
                          child: const Text('Remove', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
          ),

          // ── Secure checkout ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.lock_rounded, size: 14, color: AppColors.success),
                const SizedBox(width: 6),
                Text(
                  'Secure checkout',
                  style: tt.labelSmall?.copyWith(color: AppColors.success),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: const Text(
                'Proceed to Payment',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
