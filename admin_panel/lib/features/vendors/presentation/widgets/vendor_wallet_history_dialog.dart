import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/vendor_detail_providers.dart';
import '../../domain/models/vendor_wallet_info.dart';

class VendorWalletHistoryDialog extends ConsumerWidget {
  const VendorWalletHistoryDialog({
    super.key,
    required this.vendorId,
    required this.vendorName,
  });

  final String vendorId;
  final String vendorName;

  static final _dateFmt = DateFormat('dd MMM yyyy, hh:mm a');
  static final _currencyFmt =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync =
        ref.watch(vendorWalletTransactionsProvider(vendorId));

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Wallet Transaction History',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          vendorName,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: AppColors.border),
              const SizedBox(height: 12),

              // Content Body
              Expanded(
                child: transactionsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Text(
                      'Error loading transactions: $e',
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ),
                  data: (transactions) {
                    if (transactions.isEmpty) {
                      return const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.history_rounded,
                                size: 40, color: AppColors.border),
                            SizedBox(height: 12),
                            Text(
                              'No wallet transactions recorded yet.',
                              style:
                                  TextStyle(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      );
                    }

                    return SingleChildScrollView(
                      child: Table(
                        columnWidths: const {
                          0: FixedColumnWidth(160), // Date
                          1: FixedColumnWidth(100), // Type
                          2: FlexColumnWidth(2),   // Description
                          3: FixedColumnWidth(110), // Amount
                          4: FixedColumnWidth(120), // Balance After
                        },
                        children: [
                          TableRow(
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            children: const [
                              _HeaderCell('Date & Time'),
                              _HeaderCell('Type'),
                              _HeaderCell('Description'),
                              _HeaderCell('Amount'),
                              _HeaderCell('Balance After'),
                            ],
                          ),
                          for (final tx in transactions) _buildRow(tx),
                        ],
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static TableRow _buildRow(VendorWalletTransaction tx) {
    final isPositive = tx.type == 'top_up' || tx.type == 'refund';
    final isNegative = tx.type == 'penalty' || tx.type == 'commission';

    final typeColor = isPositive
        ? AppColors.success
        : (isNegative ? AppColors.error : AppColors.textPrimary);

    return TableRow(
      decoration: const BoxDecoration(
        border:
            Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      children: [
        _DataCell(
          child: Text(
            _dateFmt.format(tx.createdAt),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        _DataCell(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              tx.type.replaceAll('_', ' ').toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: typeColor,
              ),
            ),
          ),
        ),
        _DataCell(
          child: Text(
            tx.description ?? '—',
            style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _DataCell(
          child: Text(
            '${isPositive ? '+' : (isNegative ? '-' : '')}${_currencyFmt.format(tx.amount)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: typeColor,
            ),
          ),
        ),
        _DataCell(
          child: Text(
            _currencyFmt.format(tx.balanceAfter),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  const _DataCell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: child,
    );
  }
}
