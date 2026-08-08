import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Callback data ─────────────────────────────────────────────────────────────
//
// Captures every field needed by the phase-2 verification Edge Function:
//   success       → paymentId + orderId + signature (HMAC inputs)
//   failure       → errorCode + errorDescription (for logging / retry)
//   external_wallet → walletName (customer redirected to wallet app)

class RazorpayCallbackData {
  final String status; // 'success' | 'failure' | 'external_wallet'

  // success
  final String? paymentId;
  final String? orderId;
  final String? signature;

  // failure
  final int? errorCode;
  final String? errorDescription;

  // external_wallet
  final String? walletName;

  const RazorpayCallbackData._({
    required this.status,
    this.paymentId,
    this.orderId,
    this.signature,
    this.errorCode,
    this.errorDescription,
    this.walletName,
  });

  factory RazorpayCallbackData.success(PaymentSuccessResponse r) =>
      RazorpayCallbackData._(
        status: 'success',
        paymentId: r.paymentId,
        orderId: r.orderId,
        signature: r.signature,
      );

  factory RazorpayCallbackData.failure(PaymentFailureResponse r) =>
      RazorpayCallbackData._(
        status: 'failure',
        errorCode: r.code,
        errorDescription: r.message,
      );

  factory RazorpayCallbackData.externalWallet(ExternalWalletResponse r) =>
      RazorpayCallbackData._(
        status: 'external_wallet',
        walletName: r.walletName,
      );
}

// ── Service ───────────────────────────────────────────────────────────────────

class RazorpayService {
  final _client = Supabase.instance.client;

  /// Calls the `verify-razorpay-payment` Edge Function to confirm the HMAC
  /// signature server-side. Throws [FunctionException] if the function returns
  /// a non-2xx status (invalid signature, record not found, etc.).
  Future<void> verifyPayment({
    required String bookingId,
    required String paymentId,
    required String orderId,
    required String signature,
  }) async {
    await _client.functions.invoke(
      'verify-razorpay-payment',
      body: {
        'booking_id': bookingId,
        'razorpay_payment_id': paymentId,
        'razorpay_order_id': orderId,
        'razorpay_signature': signature,
      },
    );
  }

  /// Calls the `create-razorpay-order` Edge Function, then opens the Razorpay
  /// Flutter checkout. Returns a [RazorpayCallbackData] for whichever path the
  /// user takes (success / failure / external wallet).
  ///
  /// Throws if the Edge Function call itself fails (network error, non-2xx).
  /// The caller should treat that as a non-fatal error: the booking is already
  /// created in the database.
  Future<RazorpayCallbackData> launchCheckout(String bookingId) async {
    // 1. Create Razorpay order via Edge Function.
    final response = await _client.functions.invoke(
      'create-razorpay-order',
      body: {'booking_id': bookingId},
    );

    final data = Map<String, dynamic>.from(response.data as Map);
    final keyId    = data['key_id']   as String;
    final orderId  = data['order_id'] as String;
    final amount   = (data['amount']  as num).toInt(); // already in paise
    final currency = data['currency'] as String;

    debugPrint('[DODO][Razorpay] Order created — orderId=$orderId  amount=$amount  currency=$currency');

    // 2. Open the Razorpay checkout.
    //    Completer bridges the SDK's event callbacks to a single Future.
    final completer = Completer<RazorpayCallbackData>();
    final razorpay  = Razorpay();

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      debugPrint('[DODO][Razorpay] Payment success — paymentId=${r.paymentId}  orderId=${r.orderId}');
      razorpay.clear();
      if (!completer.isCompleted) {
        completer.complete(RazorpayCallbackData.success(r));
      }
    });

    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      debugPrint('[DODO][Razorpay] Payment error — code=${r.code}  message=${r.message}');
      razorpay.clear();
      if (!completer.isCompleted) {
        completer.complete(RazorpayCallbackData.failure(r));
      }
    });

    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {
      debugPrint('[DODO][Razorpay] External wallet — wallet=${r.walletName}');
      razorpay.clear();
      if (!completer.isCompleted) {
        completer.complete(RazorpayCallbackData.externalWallet(r));
      }
    });

    razorpay.open({
      'key': keyId,
      'amount': amount,
      'order_id': orderId,
      'currency': currency,
      'name': 'DODO Services',
      'description': 'Booking #$bookingId',
      'prefill': {
        'contact': '',
        'email': '',
      },
      'external': {
        'wallets': ['paytm'],
      },
    });

    return completer.future;
  }
}
