import 'dart:async';

Future<Map<String, dynamic>> launchRazorpayWeb({
  required String keyId,
  required int amount,
  required String orderId,
  required String currency,
  required String bookingId,
}) => throw UnsupportedError('Web checkout is not supported on this platform.');
