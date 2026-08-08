import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_modal_dialog.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/auth/widgets/otp_login_modal.dart';
import '../../../features/auth/widgets/otp_verification_modal.dart';
import '../../../features/auth/widgets/profile_completion_modal.dart';
import '../../../features/catalog/models/catalog_node_model.dart';
import '../../../models/service_attribute_model.dart';
import '../../../models/addon_model.dart';
import '../modals/address_modal.dart';
import '../modals/datetime_modal.dart';
import '../../service_availability/services/serviceability_service.dart';
import '../../service_availability/widgets/service_area_unavailable_dialog.dart';
import '../modals/booking_summary_modal.dart';
import '../modals/payment_modal.dart';
import '../services/booking_providers.dart';
import '../services/razorpay_service.dart';
import '../services/coupon_providers.dart';
import '../../../features/tax/providers/tax_provider.dart';
import '../../../features/tax/models/tax_settings_model.dart';
import '../../../features/amc/models/amc_plan_model.dart';

/// Launches the full modal-based booking flow:
/// Auth → Profile → Address → DateTime → Summary → Payment → Success.
///
/// Customers can browse freely; this gate is triggered only by "Book Now".
Future<void> launchBookingFlow(
  BuildContext context,
  WidgetRef ref,
  CatalogNodeModel service, {
  List<SelectedAttributeOption> selectedAttributes = const [],
  List<SelectedAddon> selectedAddons = const [],
  String? parentNodeId,
  AmcPlanModel? amcPlan,
}) async {
  // ── Step 0: Minimum order amount (safety net — UI disables Book Now first) ─
  // AMC plan bypasses minimum order check (the plan price is the committed price).
  if (amcPlan == null) {
    final minAmt = service.minimumOrderAmount;
    if (minAmt != null && minAmt > 0) {
      final serviceTotal = (service.basePrice ?? 0.0) +
          totalPriceAdjustment(selectedAttributes) +
          totalAddonsPrice(selectedAddons);
      if (serviceTotal < minAmt) return;
    }
  }

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

  // ── Sequential AppModalDialog flow (all platforms) ───────────────────────────

  // ── Step 3: Address ───────────────────────────────────────────────────────
  final addressFuture = AppModalDialog.show(
    context: context,
    child: const AddressModal(),
  );
  final address = await addressFuture;
  if (!context.mounted || address == null) return;

  // ── Step 3b: Serviceability check ────────────────────────────────────────
  final serviceability = await ServiceabilityService()
      .check(address.latitude, address.longitude);
  if (!context.mounted) return;
  if (serviceability != ServiceabilityResult.serviceable) {
    await showServiceAreaUnavailableDialog(context);
    if (!context.mounted) return;
    return;
  }

  // ── Step 4: Date & time ───────────────────────────────────────────────────
  final dtFuture = AppModalDialog.show(
    context: context,
    child: DateTimeModal(serviceId: service.id, parentNodeId: parentNodeId),
  );
  final dtResult = await dtFuture;
  if (!context.mounted || dtResult == null) return;
  final (date, slot) = dtResult as (DateTime, dynamic);

  // ── Step 5: Booking summary (coupon + preferred vendor applied here) ─────────
  // Seed vendor selection from the service detail page (or clear leftover state).
  ref.read(selectedCouponProvider.notifier).state = null;
  ref.read(selectedPreferredVendorProvider.notifier).state =
      (id: null, name: null, fee: 0.0);

  final priceAdjustment = amcPlan != null ? 0.0 : totalPriceAdjustment(selectedAttributes);
  final addonsTotal = amcPlan != null ? 0.0 : totalAddonsPrice(selectedAddons);
  final summaryFuture = AppModalDialog.show<bool>(
    context: context,
    child: BookingSummaryModal(
      service: service,
      address: address,
      date: date,
      slot: slot,
      priceAdjustment: priceAdjustment,
      selectedAttributes: amcPlan != null ? const [] : selectedAttributes,
      selectedAddons: amcPlan != null ? const [] : selectedAddons,
      parentNodeId: parentNodeId,
      amcPlan: amcPlan,
    ),
  );
  final confirmed = await summaryFuture;
  if (!context.mounted || confirmed != true) return;

  // Read coupon and preferred vendor state after the summary modal closes.
  final selectedCoupon = ref.read(selectedCouponProvider);
  final pvSelection = ref.read(selectedPreferredVendorProvider);
  final taxSettings = ref
      .read(resolvedTaxProvider((
        serviceId: service.id,
        parentNodeId: parentNodeId,
      )))
      .valueOrNull ?? TaxSettingsModel.defaults;
  final baseSubtotal = amcPlan != null
      ? amcPlan.pricePerVisit
      : (service.basePrice ?? 0.0) + priceAdjustment + addonsTotal;
  final subtotal = baseSubtotal + taxSettings.computeTax(baseSubtotal);
  final discountAmount = amcPlan != null ? 0.0 : (selectedCoupon?.calculateDiscount(subtotal) ?? 0.0);
  final finalTotal = (subtotal + pvSelection.fee - discountAmount).clamp(0.0, double.infinity);

  // ── Step 6: Payment ───────────────────────────────────────────────────────
  final payFuture = AppModalDialog.show<String>(
    context: context,
    child: PaymentModal(totalAmount: finalTotal),
  );
  final paymentMethod = await payFuture;
  if (!context.mounted || paymentMethod == null) {
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
          couponId: amcPlan != null ? null : selectedCoupon?.id,
          discountAmount: discountAmount,
          priceAdjustment: priceAdjustment,
          selectedAddons: selectedAddons,
          parentNodeId: parentNodeId,
          preferredVendorId: amcPlan != null ? null : pvSelection.id,
          preferredVendorFeeAmount: amcPlan != null ? null : (pvSelection.fee > 0 ? pvSelection.fee : null),
          amcPlan: amcPlan,
          paymentMethod: paymentMethod,
        );
    ref.read(selectedCouponProvider.notifier).state = null;
    if (!context.mounted) return;

    // ── Step 8 (Razorpay): Open payment checkout + server-side verification ──
    // Runs only when the booking was created with payment_method = 'razorpay'.
    // The booking row already exists; success screen is only shown after both
    // the SDK callback AND the HMAC verification edge function confirm success.
    if (paymentMethod == 'razorpay') {
      try {
        final result = await RazorpayService().launchCheckout(booking.id);
        debugPrint(
          '[DODO][Razorpay] checkout result: status=${result.status}'
          '  paymentId=${result.paymentId}'
          '  orderId=${result.orderId}'
          '  errorCode=${result.errorCode}'
          '  wallet=${result.walletName}',
        );
        if (result.status != 'success') {
          if (!context.mounted) return;
          final msg = result.status == 'external_wallet'
              ? 'Please complete payment via ${result.walletName ?? 'external wallet'}. Your booking is saved.'
              : (result.errorDescription?.isNotEmpty == true
                  ? result.errorDescription!
                  : 'Payment was not completed. Your booking is saved — check My Bookings.');
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(msg),
            backgroundColor: const Color(0xFFEA4335),
            behavior: SnackBarBehavior.floating,
          ));
          return;
        }
        debugPrint('[DODO][Razorpay] → verifyPayment(${booking.id})');
        await RazorpayService().verifyPayment(
          bookingId: booking.id,
          paymentId: result.paymentId!,
          orderId: result.orderId!,
          signature: result.signature!,
        );
        debugPrint('[DODO][Razorpay] ✓ verifyPayment succeeded');
      } catch (e) {
        debugPrint('[DODO][Razorpay] checkout/verification error: $e');
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Payment verification failed. Your booking is saved — check My Bookings.'),
          backgroundColor: const Color(0xFFEA4335),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      if (!context.mounted) return;
    }

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
