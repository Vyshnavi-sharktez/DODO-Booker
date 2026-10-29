import 'dart:async';

class RazorpayWebResult {
  final bool succeeded;
  final String? paymentId;
  final String? orderId;
  final String? signature;
  final String? errorMessage;

  const RazorpayWebResult._({
    required this.succeeded,
    this.paymentId,
    this.orderId,
    this.signature,
    this.errorMessage,
  });

  factory RazorpayWebResult.success({
    required String paymentId,
    required String orderId,
    required String signature,
  }) =>
      RazorpayWebResult._(
        succeeded: true,
        paymentId: paymentId,
        orderId: orderId,
        signature: signature,
      );

  factory RazorpayWebResult.failure(String message) =>
      RazorpayWebResult._(succeeded: false, errorMessage: message);
}

Future<RazorpayWebResult> openRazorpayCheckout({
  required String keyId,
  required String orderId,
  required int amountPaise,
  required String name,
  required String description,
}) {
  throw UnsupportedError('Razorpay web checkout is only available on web.');
}
