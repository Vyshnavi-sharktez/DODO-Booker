/// Payment gateway abstraction.
///
/// To plug in Razorpay (or any other gateway):
///   1. Create `RazorpayGateway implements PaymentGateway`.
///   2. Register it via `paymentGatewayProvider`.
///   3. Call `gateway.initiatePayment(request)` in PaymentPage
///      instead of showing the simulate buttons.
///
/// The rest of the purchase flow (createSubscription, activateSubscription,
/// recordPaymentFailure) in SubscriptionRepository is gateway-agnostic and
/// does not change during integration.

class PaymentRequest {
  final String orderId;
  final String paymentRecordId;
  final double amount;
  final String currency;
  final String description;
  final Map<String, String> metadata;

  const PaymentRequest({
    required this.orderId,
    required this.paymentRecordId,
    required this.amount,
    this.currency = 'INR',
    required this.description,
    this.metadata = const {},
  });
}

class PaymentResult {
  final bool success;
  final String? gatewayTransactionId;
  final String? errorMessage;

  const PaymentResult({
    required this.success,
    this.gatewayTransactionId,
    this.errorMessage,
  });
}

abstract class PaymentGateway {
  /// Opens the gateway's payment UI or SDK.
  /// Returns a [PaymentResult] when the flow completes (success or failure).
  Future<PaymentResult> initiatePayment(PaymentRequest request);
}
