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

  /// TEMPORARY IMPLEMENTATION: Simulates payment gateway success by calling the top-up RPC.
  /// 
  /// NOTE FOR REAL PAYMENT GATEWAY INTEGRATION:
  /// When integrating Razorpay/Stripe, replace the RPC call below with the payment
  /// gateway verification webhook/callback. The dialog UX and downstream providers
  /// do not need to change.
  Future<void> topUpWallet({
    required String vendorId,
    required double amount,
    String description = 'Wallet Top-Up (Simulated Payment)',
  }) async {
    await supabase.rpc('admin_top_up_vendor_wallet', params: {
      'p_vendor_id': vendorId,
      'p_amount': amount,
      'p_description': description,
    });
  }
}
