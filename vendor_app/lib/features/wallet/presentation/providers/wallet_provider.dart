import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../data/wallet_repository.dart';
import '../../domain/models/wallet.dart';
import '../../domain/models/transaction.dart';

final walletRepositoryProvider = Provider<WalletRepository>(
  (ref) => WalletRepository(ref.watch(supabaseClientProvider)),
);

final walletProvider = FutureProvider.family<Wallet, String>(
  (ref, vendorId) => ref.watch(walletRepositoryProvider).fetchWallet(vendorId),
);

final walletTransactionsProvider =
    FutureProvider.family<List<WalletTransaction>, String>(
  (ref, vendorId) =>
      ref.watch(walletRepositoryProvider).fetchTransactions(vendorId),
);

final walletMinimumBalanceProvider = FutureProvider<double>((ref) async {
  final supabase = ref.watch(supabaseClientProvider);
  final row = await supabase
      .from('settings')
      .select('setting_value')
      .eq('setting_key', 'wallet_minimum_balance')
      .maybeSingle();
  return double.tryParse(row?['setting_value'] as String? ?? '') ?? 0.0;
});
