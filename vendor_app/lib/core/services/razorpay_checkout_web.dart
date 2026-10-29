// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;
import 'package:flutter/foundation.dart' show debugPrint;

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

/// Ensures checkout.js is available on window.Razorpay.
/// Returns immediately if already loaded; otherwise injects the script tag
/// and awaits its load event. Throws on network failure.
Future<void> _ensureCheckoutJsLoaded() async {
  if (js.context['Razorpay'] != null) return;

  debugPrint('[Razorpay] window.Razorpay not found — injecting checkout.js dynamically');
  final completer = Completer<void>();
  final script = html.ScriptElement()
    ..src = 'https://checkout.razorpay.com/v1/checkout.js';

  late final StreamSubscription<html.Event> onLoad;
  late final StreamSubscription<html.Event> onError;

  onLoad = script.onLoad.listen((_) {
    onLoad.cancel();
    onError.cancel();
    if (!completer.isCompleted) completer.complete();
  });
  onError = script.onError.listen((_) {
    onLoad.cancel();
    onError.cancel();
    if (!completer.isCompleted) {
      completer.completeError(
        Exception(
          'Failed to load Razorpay checkout.js. Check your network connection.',
        ),
      );
    }
  });

  (html.document.head ?? html.document.body!).append(script);
  await completer.future;

  if (js.context['Razorpay'] == null) {
    throw Exception(
      'Razorpay checkout.js loaded but window.Razorpay is not defined.',
    );
  }
}

/// Opens the Razorpay checkout modal on Flutter Web.
/// Lazily loads checkout.js if it was not (or failed to be) pre-loaded in
/// index.html, then opens the payment popup and awaits its result.
Future<RazorpayWebResult> openRazorpayCheckout({
  required String keyId,
  required String orderId,
  required int amountPaise,
  required String name,
  required String description,
}) async {
  await _ensureCheckoutJsLoaded();

  final completer = Completer<RazorpayWebResult>();

  final options = js.JsObject.jsify(<String, dynamic>{
    'key': keyId,
    'amount': amountPaise,
    'order_id': orderId,
    'currency': 'INR',
    'name': name,
    'description': description,
    'handler': js.allowInterop((js.JsObject response) {
      if (completer.isCompleted) return;
      final pid = response['razorpay_payment_id'] as String? ?? '';
      final oid = response['razorpay_order_id'] as String? ?? orderId;
      final sig = response['razorpay_signature'] as String? ?? '';
      completer.complete(
        RazorpayWebResult.success(
          paymentId: pid,
          orderId: oid,
          signature: sig,
        ),
      );
    }),
    'modal': <String, dynamic>{
      'ondismiss': js.allowInterop(() {
        if (!completer.isCompleted) {
          completer.complete(
            RazorpayWebResult.failure('Payment was cancelled.'),
          );
        }
      }),
    },
  });

  final checkout = js.JsObject(
    js.context['Razorpay'] as js.JsFunction,
    [options],
  );
  checkout.callMethod('open');

  return completer.future;
}
