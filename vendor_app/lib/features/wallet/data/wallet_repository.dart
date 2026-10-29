import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/repositories/base_repository.dart';
import '../domain/models/wallet.dart';
import '../domain/models/transaction.dart';

class WalletRepository extends BaseRepository {
  const WalletRepository(super.supabase);

  /// Fetches the wallet summary for the given vendor from `vendor_wallets`.
  /// Returns a fallback empty [Wallet] if no wallet record exists yet.
  Future<Wallet> fetchWallet(String vendorId) async {
    final response = await supabase
        .from('vendor_wallets')
        .select()
        .eq('vendor_id', vendorId)
        .maybeSingle();

    if (response == null) {
      return Wallet(id: '', vendorId: vendorId);
    }

    return Wallet.fromMap(response);
  }

  /// Fetches paginated wallet transactions for the given vendor from `wallet_transactions`.
  Future<List<WalletTransaction>> fetchTransactions(
    String vendorId, {
    int limit = 20,
    int offset = 0,
  }) async {
    final response = await supabase
        .from('wallet_transactions')
        .select()
        .eq('vendor_id', vendorId)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    final list = response as List<dynamic>;
    return list
        .map((json) => WalletTransaction.fromMap(json as Map<String, dynamic>))
        .toList();
  }

  /// Fetches booking details for a commission transaction reference.
  Future<Map<String, dynamic>?> fetchBookingDetails(String bookingId) async {
    try {
      final response = await supabase
          .from('bookings')
          .select('''
            id, booking_number, status, created_at, completed_at, otp_verified_at,
            subtotal, total_amount,
            booking_items(
              service_id,
              quantity,
              unit_price,
              total_price,
              catalog_nodes!booking_items_service_id_catalog_fkey(id, name)
            )
          ''')
          .eq('id', bookingId)
          .maybeSingle();

      return response;
    } catch (_) {
      try {
        final response = await supabase
            .from('bookings')
            .select('''
              id, booking_number, status, created_at, completed_at, otp_verified_at,
              subtotal, total_amount,
              booking_items(
                service_id,
                quantity,
                unit_price,
                total_price
              )
            ''')
            .eq('id', bookingId)
            .maybeSingle();
        return response;
      } catch (e) {
        return null;
      }
    }
  }

  /// Fetches dynamic penalty rule configuration for an event (e.g., 'rejection', 'cancellation', 'noshow').
  Future<({bool isEnabled, double amount})> fetchPenaltyRule(String eventType) async {
    try {
      final enabledKey = 'penalty_vendor_${eventType}_enabled';
      final amountKey = 'penalty_vendor_${eventType}_amount';

      final response = await supabase
          .from('settings')
          .select('setting_key, setting_value')
          .inFilter('setting_key', [enabledKey, amountKey]);

      final rows = response as List<dynamic>;
      bool enabled = false;
      double amount = 0.0;

      for (final row in rows) {
        final key = row['setting_key'] as String?;
        final val = row['setting_value'] as String?;
        if (key == enabledKey) {
          enabled = (val?.trim().toLowerCase() == 'true');
        } else if (key == amountKey) {
          amount = double.tryParse(val?.trim() ?? '0') ?? 0.0;
        }
      }

      return (isEnabled: enabled, amount: amount);
    } catch (_) {
      return (isEnabled: false, amount: 0.0);
    }
  }

  /// Creates a Razorpay order for a wallet top-up via the
  /// `create-vendor-wallet-topup-order` Edge Function.
  ///
  /// Returns the fields needed to open the Razorpay checkout:
  ///   attemptId, keyId, orderId, amountPaise, currency.
  Future<Map<String, dynamic>> createTopUpOrder({
    required String vendorId,
    required double amountRupees,
  }) async {
    try {
      final response = await supabase.functions.invoke(
        'create-vendor-wallet-topup-order',
        body: {'vendor_id': vendorId, 'amount': amountRupees},
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on FunctionException catch (e) {
      String message = 'Could not create payment order.';
      final details = e.details;
      if (details is Map) message = details['error'] as String? ?? message;
      throw Exception(message);
    }
  }

  Future<void> verifyTopUp({
    required String topupAttemptId,
    required String vendorId,
    required String razorpayPaymentId,
    required String razorpayOrderId,
    required String razorpaySignature,
  }) async {
    try {
      await supabase.functions.invoke(
        'verify-vendor-wallet-topup',
        body: {
          'topup_attempt_id': topupAttemptId,
          'vendor_id': vendorId,
          'razorpay_payment_id': razorpayPaymentId,
          'razorpay_order_id': razorpayOrderId,
          'razorpay_signature': razorpaySignature,
        },
      );
    } on FunctionException catch (e) {
      String message = 'Payment verification failed.';
      final details = e.details;
      if (details is Map) message = details['error'] as String? ?? message;
      throw Exception(message);
    }
  }
}
