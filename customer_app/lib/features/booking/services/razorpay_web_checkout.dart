import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('Razorpay')
extension type _RazorpayCheckout._(JSObject _) implements JSObject {
  external factory _RazorpayCheckout(JSObject options);
  external void open();
}

Future<Map<String, dynamic>> launchRazorpayWeb({
  required String keyId,
  required int amount,
  required String orderId,
  required String currency,
  required String bookingId,
}) {
  final completer = Completer<Map<String, dynamic>>();

  final options = JSObject();
  options['key'] = keyId.toJS;
  options['amount'] = amount.toJS;
  options['order_id'] = orderId.toJS;
  options['currency'] = currency.toJS;
  options['name'] = 'DODO Services'.toJS;
  options['description'] = 'Booking #$bookingId'.toJS;

  void onPaymentSuccess(JSAny? response) {
    if (response == null || completer.isCompleted) return;
    final obj = response as JSObject;
    final paymentId = (obj['razorpay_payment_id'] as JSString).toDart;
    final respOrderId = (obj['razorpay_order_id'] as JSString).toDart;
    final signature = (obj['razorpay_signature'] as JSString).toDart;
    completer.complete({
      'success': true,
      'paymentId': paymentId,
      'orderId': respOrderId,
      'signature': signature,
    });
  }

  void onDismiss() {
    if (!completer.isCompleted) {
      completer.complete({
        'success': false,
        'errorDescription': 'Payment cancelled.',
      });
    }
  }

  options['handler'] = onPaymentSuccess.toJS;

  final modal = JSObject();
  modal['ondismiss'] = onDismiss.toJS;
  options['modal'] = modal;

  final prefill = JSObject();
  prefill['contact'] = ''.toJS;
  prefill['email'] = ''.toJS;
  options['prefill'] = prefill;

  _RazorpayCheckout(options).open();

  return completer.future;
}
