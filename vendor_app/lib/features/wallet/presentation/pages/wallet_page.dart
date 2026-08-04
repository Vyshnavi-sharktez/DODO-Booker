import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/empty_state_view.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/loading_indicator.dart';
import '../../../profile/presentation/providers/profile_provider.dart';
import '../providers/wallet_provider.dart';
import '../widgets/balance_card.dart';
import '../widgets/transaction_tile.dart';

class WalletPage extends ConsumerWidget {
  const WalletPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProfile = ref.watch(vendorProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Wallet & Earnings',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: false,
      ),
      body: asyncProfile.when(
        data: (profile) {
          if (profile == null || profile.id.isEmpty) {
            return EmptyStateView(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No Vendor Profile Found',
              subtitle:
                  'Please log in with a valid vendor account to access your wallet.',
              actionLabel: 'Refresh',
              action: () => ref.refresh(vendorProfileProvider),
            );
          }

          final vendorId = profile.id;
          final asyncWallet = ref.watch(walletProvider(vendorId));
          final asyncTxns = ref.watch(walletTransactionsProvider(vendorId));

          return asyncWallet.when(
            data: (wallet) {
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(walletProvider(vendorId));
                  ref.invalidate(walletTransactionsProvider(vendorId));
                  await Future.wait([
                    ref.read(walletProvider(vendorId).future),
                    ref.read(walletTransactionsProvider(vendorId).future),
                  ]);
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Balance Card Widget
                      BalanceCard(wallet: wallet),

                      const SizedBox(height: 24),

                      // Section Header
                      const Text(
                        'Recent Transactions',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Transaction List State
                      asyncTxns.when(
                        data: (transactions) {
                          if (transactions.isEmpty) {
                            return const EmptyStateView(
                              icon: Icons.receipt_long_outlined,
                              title: 'No Transactions Yet',
                              subtitle:
                                  'Your top-ups, commission deductions, and settlements will be listed here.',
                            );
                          }
                          return ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: transactions.length,
                            itemBuilder: (context, index) {
                              return TransactionTile(
                                transaction: transactions[index],
                              );
                            },
                          );
                        },
                        loading: () => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: LoadingIndicator(size: 28),
                        ),
                        error: (error, stack) => ErrorView(
                          message: 'Failed to load transactions: $error',
                          onRetry: () =>
                              ref.refresh(walletTransactionsProvider(vendorId)),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            loading: () => const LoadingIndicator(),
            error: (error, stack) => ErrorView(
              message: 'Failed to load wallet details: $error',
              onRetry: () => ref.refresh(walletProvider(vendorId)),
            ),
          );
        },
        loading: () => const LoadingIndicator(),
        error: (error, stack) => ErrorView(
          message: 'Failed to load profile: $error',
          onRetry: () => ref.refresh(vendorProfileProvider),
        ),
      ),
    );
  }
}
