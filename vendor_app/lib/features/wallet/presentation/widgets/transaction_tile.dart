import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../domain/models/transaction.dart';
import 'transaction_details_modal.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.transaction});

  final WalletTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      symbol: '₹',
      decimalDigits: 2,
      locale: 'en_IN',
    );

    final isCredit = transaction.type == TransactionType.topUp;
    final isDebit = transaction.type == TransactionType.commission ||
        transaction.type == TransactionType.penalty;

    final IconData icon;
    final Color color;
    final String defaultTitle;
    final String prefix;

    switch (transaction.type) {
      case TransactionType.topUp:
        icon = Icons.add_circle_outline_rounded;
        color = AppColors.success;
        defaultTitle = 'Wallet Top-Up';
        prefix = '+ ';
        break;
      case TransactionType.commission:
        icon = Icons.pie_chart_outline_rounded;
        color = AppColors.error;
        defaultTitle = 'Commission Deduction';
        prefix = '- ';
        break;
      case TransactionType.penalty:
        icon = Icons.warning_amber_rounded;
        color = AppColors.error;
        defaultTitle = 'Penalty';
        prefix = '- ';
        break;
      case TransactionType.adjustment:
        icon = Icons.tune_rounded;
        color = AppColors.info;
        defaultTitle = 'Balance Adjustment';
        prefix = '';
        break;
    }

    final title = (transaction.description != null &&
            transaction.description!.trim().isNotEmpty)
        ? transaction.description!
        : defaultTitle;

    final dateStr = transaction.createdAt != null
        ? DateFormat('MMM dd, yyyy • hh:mm a')
            .format(transaction.createdAt!.toLocal())
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => showTransactionDetailsModal(context, transaction),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (dateStr.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          dateStr,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 2),
                      Text(
                        'Bal: ${currencyFormatter.format(transaction.balanceAfter)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$prefix${currencyFormatter.format(transaction.amount)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isCredit
                            ? AppColors.success
                            : (isDebit ? AppColors.error : AppColors.textPrimary),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View Details',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 14,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
