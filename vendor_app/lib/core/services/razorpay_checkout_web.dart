import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('Razorpay')
extension type _RazorpayCheckout._(JSObject _) implements JSObject {
  external factory _RazorpayCheckout(JSObject options);
  external void open();
}

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
  final completer = Completer<RazorpayWebResult>();

  void onSuccess(JSAny? response) {
    if (response == null || completer.isCompleted) return;
    final obj = response as JSObject;
    final pid = (obj['razorpay_payment_id'] as JSString).toDart;
    final oid = (obj['razorpay_order_id'] as JSString).toDart;
    final sig = (obj['razorpay_signature'] as JSString).toDart;
    completer.complete(
      RazorpayWebResult.success(paymentId: pid, orderId: oid, signature: sig),
    );
  }

  void onDismiss() {
    if (!completer.isCompleted) {
      completer.complete(RazorpayWebResult.failure('Payment was cancelled.'));
    }
  }

  final options = JSObject();
  options['key'] = keyId.toJS;
  options['amount'] = amountPaise.toJS;
  options['order_id'] = orderId.toJS;
  options['currency'] = 'INR'.toJS;
  options['name'] = name.toJS;
  options['description'] = description.toJS;
  options['handler'] = onSuccess.toJS;

  final modal = JSObject();
  modal['ondismiss'] = onDismiss.toJS;
  options['modal'] = modal;

  _RazorpayCheckout(options).open();

  return completer.future;
}
