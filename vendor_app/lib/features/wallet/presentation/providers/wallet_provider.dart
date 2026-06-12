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
