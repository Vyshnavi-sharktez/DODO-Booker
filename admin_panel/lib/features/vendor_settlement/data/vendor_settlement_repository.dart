import 'package:supabase_flutter/supabase_flutter.dart';

class VendorSettlementRepository {
  final SupabaseClient _supabase;

  const VendorSettlementRepository(this._supabase);

  Future<void> deductWalletBalance(
    String vendorId, {
    required double newBalance,
  }) async {
    await _supabase
        .from('vendors')
        .update({'wallet_balance': newBalance})
        .eq('id', vendorId);
  }
}
