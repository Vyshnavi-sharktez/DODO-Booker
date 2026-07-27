import 'payment_gateway.dart';

/// Placeholder implementation — no real payment is processed.
///
/// The PaymentPage renders "Simulate Success" and "Simulate Fail" buttons
/// instead of calling this gateway. This class exists so the provider and
/// type signature are wired correctly before Razorpay is integrated.
///
/// When integrating Razorpay:
///   - Replace this with `RazorpayGateway`.
///   - Have PaymentPage call `gateway.initiatePayment(request)` and handle
///     the returned [PaymentResult] instead of showing simulate buttons.
class PlaceholderPaymentGateway implements PaymentGateway {
  const PlaceholderPaymentGateway();

  @override
  Future<PaymentResult> initiatePayment(PaymentRequest request) async {
    // Placeholder only — result is driven by the UI's simulate buttons.
    return const PaymentResult(
      success: false,
      errorMessage: 'Placeholder gateway: use simulate buttons in UI.',
    );
  }
}
