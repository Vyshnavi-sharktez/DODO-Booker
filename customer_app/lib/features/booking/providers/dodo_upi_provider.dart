import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DodoUpiConfig {
  final String upiId;
  final String? qrImageUrl;
  final bool isEnabled;
  const DodoUpiConfig({
    required this.upiId,
    this.qrImageUrl,
    this.isEnabled = false,
  });
}

/// Full config including is_enabled — used by payment modal at checkout.
final dodoUpiConfigProvider =
    FutureProvider.autoDispose<DodoUpiConfig?>((ref) async {
  final row = await Supabase.instance.client
      .from('payment_gateway_configs')
      .select('is_enabled, extra_config')
      .eq('gateway', 'upi_dodo')
      .maybeSingle();
  if (row == null) return null;
  final extra = row['extra_config'] as Map<String, dynamic>? ?? {};
  final upiId = extra['upi_id'] as String? ?? '';
  if (upiId.isEmpty) return null;
  return DodoUpiConfig(
    upiId: upiId,
    qrImageUrl: extra['qr_image_url'] as String?,
    isEnabled: row['is_enabled'] as bool? ?? false,
  );
});

/// UPI ID + QR regardless of is_enabled — used in OTP display card.
final dodoUpiPaymentInfoProvider =
    FutureProvider.autoDispose<DodoUpiConfig?>((ref) async {
  final row = await Supabase.instance.client
      .from('payment_gateway_configs')
      .select('extra_config')
      .eq('gateway', 'upi_dodo')
      .maybeSingle();
  if (row == null) return null;
  final extra = row['extra_config'] as Map<String, dynamic>? ?? {};
  final upiId = extra['upi_id'] as String? ?? '';
  if (upiId.isEmpty) return null;
  return DodoUpiConfig(
    upiId: upiId,
    qrImageUrl: extra['qr_image_url'] as String?,
    isEnabled: true,
  );
});
