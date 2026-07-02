import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_modal_dialog.dart';
import '../../../core/widgets/page_sheet.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/auth/widgets/otp_login_modal.dart';
import '../../../features/auth/widgets/otp_verification_modal.dart';
import '../../../features/auth/widgets/profile_completion_modal.dart';
import '../../../models/service_model.dart';
import '../../../models/service_attribute_model.dart';
import '../modals/address_modal.dart';
import '../modals/datetime_modal.dart';
import '../modals/booking_summary_modal.dart';
import '../modals/booking_flow_modal.dart';
import '../modals/payment_modal.dart';
import '../services/booking_providers.dart';
import '../services/coupon_providers.dart';

/// Launches the full modal-based booking flow:
/// Auth → Profile → Address → DateTime → Summary → Payment → Success.
///
/// Customers can browse freely; this gate is triggered only by "Book Now".
Future<void> launchBookingFlow(
  BuildContext context,
  WidgetRef ref,
  ServiceModel service, {
  List<SelectedAttributeOption> selectedAttributes = const [],
}) async {
  // ── Step 1: Authentication ────────────────────────────────────────────────
  if (!ref.read(isAuthenticatedProvider)) {
    // Capture context synchronously before each await
    final phoneFuture = AppModalDialog.show<String>(
      context: context,
      child: const OtpLoginModal(),
    );
    final phone = await phoneFuture;
    if (!context.mounted || phone == null) return;

    final verifyFuture = AppModalDialog.show<bool>(
      context: context,
      child: OtpVerificationModal(phone: phone),
    );
    final verified = await verifyFuture;
    if (!context.mounted || verified != true) return;
  }

  // ── Step 2: Profile completion ────────────────────────────────────────────
  final profileComplete = await ref.read(authServiceProvider).isProfileComplete();
  if (!context.mounted) return;
  if (!profileComplete) {
    debugPrint('[DODO][Auth] Profile Incomplete');
    final profileFuture = AppModalDialog.show<bool>(
      context: context,
      child: const ProfileCompletionModal(),
      barrierDismissible: false,
    );
    final saved = await profileFuture;
    if (!context.mounted || saved != true) return;
  }

  // ── Desktop: booking modal — matches Profile dialog design system ────────────
  if (MediaQuery.of(context).size.width >= 768) {
    await PageSheet.show(
      context,
      title: service.name,
      child: BookingFlowModal(
        service: service,
        selectedAttributes: selectedAttributes,
      ),
    );
    return;
  }

  // ── Mobile: sequential AppModalDialog flow ────────────────────────────────────

  // ── Step 3: Address ───────────────────────────────────────────────────────
  final addressFuture = AppModalDialog.show(
    context: context,
    child: const AddressModal(),
  );
  final address = await addressFuture;
  if (!context.mounted || address == null) return;

  // ── Step 4: Date & time ───────────────────────────────────────────────────
  final dtFuture = AppModalDialog.show(
    context: context,
    child: const DateTimeModal(),
  );
  final dtResult = await dtFuture;
  if (!context.mounted || dtResult == null) return;
  final (date, slot) = dtResult as (DateTime, dynamic);

  // ── Step 5: Booking summary (coupon applied here) ─────────────────────────
  // Reset any leftover coupon from a previous booking attempt.
  ref.read(selectedCouponProvider.notifier).state = null;

  final priceAdjustment = totalPriceAdjustment(selectedAttributes);
  final summaryFuture = AppModalDialog.show<bool>(
    context: context,
    child: BookingSummaryModal(
      service: service,
      address: address,
      date: date,
      slot: slot,
      priceAdjustment: priceAdjustment,
      selectedAttributes: selectedAttributes,
    ),
  );
  final confirmed = await summaryFuture;
  if (!context.mounted || confirmed != true) return;

  // Read coupon state after the summary modal closes.
  final selectedCoupon = ref.read(selectedCouponProvider);
  final subtotal = (service.startingPrice + priceAdjustment) * 1.18;
  final discountAmount = selectedCoupon?.calculateDiscount(subtotal) ?? 0.0;
  final finalTotal = (subtotal - discountAmount).clamp(0.0, double.infinity);

  // ── Step 6: Payment ───────────────────────────────────────────────────────
  final payFuture = AppModalDialog.show<bool>(
    context: context,
    child: PaymentModal(totalAmount: finalTotal),
  );
  final paid = await payFuture;
  if (!context.mounted || paid != true) {
    ref.read(selectedCouponProvider.notifier).state = null;
    return;
  }

  // ── Step 7: Create booking & navigate to success ──────────────────────────
  try {
    debugPrint('[DODO][Booking] Calling createBooking...');
    final booking = await ref.read(bookingServiceProvider).createBooking(
          service: service,
          address: address,
          date: date,
          slot: slot,
          couponId: selectedCoupon?.id,
          discountAmount: discountAmount,
          priceAdjustment: priceAdjustment,
        );
    ref.read(selectedCouponProvider.notifier).state = null;
    if (!context.mounted) return;
    debugPrint('[DODO][Booking] Navigating to success screen');
    context.push('/booking-success', extra: booking);
  } catch (e) {
    ref.read(selectedCouponProvider.notifier).state = null;
    debugPrint('[DODO][Booking] createBooking failed: $e');
    if (!context.mounted) return;
    final message = e.toString().replaceFirst('Exception: ', '');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Booking failed: $message'),
        backgroundColor: const Color(0xFFEA4335),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
