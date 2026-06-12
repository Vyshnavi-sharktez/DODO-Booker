import '../../../shared/repositories/base_repository.dart';
import '../domain/models/wallet.dart';
import '../domain/models/transaction.dart';

class WalletRepository extends BaseRepository {
  const WalletRepository(super.supabase);

  Future<Wallet> fetchWallet(String vendorId) async =>
      throw UnimplementedError();

  Future<List<WalletTransaction>> fetchTransactions(
    String vendorId, {
    int limit = 20,
    int offset = 0,
  }) async =>
      throw UnimplementedError();
}
