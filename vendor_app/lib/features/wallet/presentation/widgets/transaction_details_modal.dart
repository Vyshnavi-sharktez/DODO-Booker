import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../bookings/domain/models/booking_item.dart';
import '../../domain/models/transaction.dart';
import '../providers/wallet_provider.dart';

void showTransactionDetailsModal(
  BuildContext context,
  WalletTransaction transaction,
) {
  final isMobile = MediaQuery.of(context).size.width < 600;

  if (isMobile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TransactionDetailsContent(
        transaction: transaction,
        isSheet: true,
      ),
    );
  } else {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: TransactionDetailsContent(
            transaction: transaction,
            isSheet: false,
          ),
        ),
      ),
    );
  }
}

class TransactionDetailsContent extends ConsumerWidget {
  const TransactionDetailsContent({
    super.key,
    required this.transaction,
    required this.isSheet,
  });

  final WalletTransaction transaction;
  final bool isSheet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = _TransactionDetailsBody(transaction: transaction);

    if (isSheet) {
      return Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              body,
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: body,
    );
  }
}

class _TransactionDetailsBody extends ConsumerWidget {
  const _TransactionDetailsBody({required this.transaction});

  final WalletTransaction transaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencyFormatter = NumberFormat.currency(
      symbol: '₹',
      decimalDigits: 2,
      locale: 'en_IN',
    );
    final dateFmt = DateFormat('dd MMM yyyy • hh:mm a');

    final isTopUp = transaction.type == TransactionType.topUp;
    final isCommission = transaction.type == TransactionType.commission;

    final Color iconColor = isTopUp ? AppColors.success : AppColors.error;
    final IconData icon = isTopUp
        ? Icons.add_circle_outline_rounded
        : Icons.pie_chart_outline_rounded;

    final String titleText = isTopUp
        ? 'Top-up Details'
        : (isCommission
            ? 'Platform Commission Details'
            : 'Transaction Details');

    final double balanceBefore = isTopUp
        ? (transaction.balanceAfter - transaction.amount)
        : (transaction.balanceAfter + transaction.amount);
    final double balanceAfter = transaction.balanceAfter;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCommission &&
              transaction.referenceId != null &&
              transaction.referenceId!.isNotEmpty)
            FutureBuilder<Map<String, dynamic>?>(
              future: ref
                  .read(walletRepositoryProvider)
                  .fetchBookingDetails(transaction.referenceId!),
              builder: (context, snapshot) {
                final booking = snapshot.data;
                final bookingNumber = booking?['booking_number'] as String?;
                final bookingIdDisplay = bookingNumber != null &&
                        bookingNumber.isNotEmpty
                    ? '#$bookingNumber'
                    : (transaction.referenceId!.length > 8
                        ? '#${transaction.referenceId!.substring(0, 8)}'
                        : '#${transaction.referenceId!}');

                final subtitleText = 'Booking ID: $bookingIdDisplay';

                return _buildHeaderAndContent(
                  context: context,
                  iconColor: iconColor,
                  icon: icon,
                  titleText: titleText,
                  subtitleText: subtitleText,
                  isTopUp: isTopUp,
                  isCommission: isCommission,
                  currencyFormatter: currencyFormatter,
                  dateFmt: dateFmt,
                  balanceBefore: balanceBefore,
                  balanceAfter: balanceAfter,
                  booking: booking,
                  isLoading:
                      snapshot.connectionState == ConnectionState.waiting,
                );
              },
            )
          else
            _buildHeaderAndContent(
              context: context,
              iconColor: iconColor,
              icon: icon,
              titleText: titleText,
              subtitleText: isTopUp ? 'Manual Top-Up' : 'Wallet Transaction',
              isTopUp: isTopUp,
              isCommission: isCommission,
              currencyFormatter: currencyFormatter,
              dateFmt: dateFmt,
              balanceBefore: balanceBefore,
              balanceAfter: balanceAfter,
              booking: null,
              isLoading: false,
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderAndContent({
    required BuildContext context,
    required Color iconColor,
    required IconData icon,
    required String titleText,
    required String subtitleText,
    required bool isTopUp,
    required bool isCommission,
    required NumberFormat currencyFormatter,
    required DateFormat dateFmt,
    required double balanceBefore,
    required double balanceAfter,
    required Map<String, dynamic>? booking,
    required bool isLoading,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Header ────────────────────────────────────────────────────────
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titleText,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    subtitleText,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
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
        const SizedBox(height: 16),

        // ── Amount Banner ──────────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: iconColor.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Text(
                isTopUp ? 'Top-up Amount' : 'Platform Commission',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${isTopUp ? '+' : '-'} ${currencyFormatter.format(transaction.amount)}',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: iconColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Field Details ──────────────────────────────────────────────────
        if (isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator.adaptive()),
          )
        else if (isTopUp) ...[
          _DetailRow(
            label: 'Amount',
            value: '+ ${currencyFormatter.format(transaction.amount)}',
            valueStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.success,
            ),
          ),
          _DetailRow(
            label: 'Description',
            value: transaction.description ?? 'Admin Top-Up',
          ),
          _DetailRow(
            label: 'Date & Time',
            value: transaction.createdAt != null
                ? dateFmt.format(transaction.createdAt!.toLocal())
                : 'N/A',
          ),
          _DetailRow(
            label: 'Wallet Balance Before',
            value: currencyFormatter.format(balanceBefore),
          ),
          _DetailRow(
            label: 'Wallet Balance After',
            value: currencyFormatter.format(balanceAfter),
            valueStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ] else if (isCommission) ...[
          _buildCommissionFields(
            booking: booking,
            currencyFormatter: currencyFormatter,
            dateFmt: dateFmt,
            balanceBefore: balanceBefore,
            balanceAfter: balanceAfter,
          ),
        ] else ...[
          _DetailRow(
            label: 'Description',
            value: transaction.description ?? 'Transaction',
          ),
          _DetailRow(
            label: 'Date & Time',
            value: transaction.createdAt != null
                ? dateFmt.format(transaction.createdAt!.toLocal())
                : 'N/A',
          ),
          _DetailRow(
            label: 'Wallet Balance Before',
            value: currencyFormatter.format(balanceBefore),
          ),
          _DetailRow(
            label: 'Wallet Balance After',
            value: currencyFormatter.format(balanceAfter),
          ),
        ],
      ],
    );
  }

  Widget _buildCommissionFields({
    required Map<String, dynamic>? booking,
    required NumberFormat currencyFormatter,
    required DateFormat dateFmt,
    required double balanceBefore,
    required double balanceAfter,
  }) {
    final bookingNumber = booking?['booking_number'] as String?;
    final bookingIdDisplay = bookingNumber != null && bookingNumber.isNotEmpty
        ? '#$bookingNumber'
        : (transaction.referenceId != null &&
                transaction.referenceId!.length > 8
            ? '#${transaction.referenceId!.substring(0, 8)}'
            : (transaction.referenceId ?? 'N/A'));

    // Extract actual service names using BookingItem parser
    String serviceName = 'N/A';
    double itemTotalSum = 0.0;
    final rawItems = booking?['booking_items'] as List<dynamic>?;
    if (rawItems != null && rawItems.isNotEmpty) {
      final names = <String>[];
      for (final itemMap in rawItems) {
        final item = BookingItem.fromMap(itemMap as Map<String, dynamic>);
        if (item.serviceName.trim().isNotEmpty) {
          names.add(item.displayLabel);
        }
        itemTotalSum += item.totalPrice;
      }
      if (names.isNotEmpty) {
        serviceName = names.join(', ');
      }
    }

    // Completed Date & Time
    final completedAtStr = booking?['completed_at'] ??
        booking?['otp_verified_at'] ??
        transaction.createdAt?.toLocal().toIso8601String();
    final completedDateTime = completedAtStr != null
        ? DateTime.tryParse(completedAtStr.toString())
        : null;
    final completedDateDisplay = completedDateTime != null
        ? dateFmt.format(completedDateTime.toLocal())
        : (transaction.createdAt != null
            ? dateFmt.format(transaction.createdAt!.toLocal())
            : 'N/A');

    // Resolve Commission Rate
    final bookingSubtotal = (booking?['subtotal'] as num?)?.toDouble() ??
        (booking?['total_amount'] as num?)?.toDouble() ??
        itemTotalSum;
    String rateDisplay = 'N/A';
    if (bookingSubtotal > 0 && transaction.amount > 0) {
      final calcRate = (transaction.amount / bookingSubtotal) * 100;
      rateDisplay = calcRate % 1 == 0
          ? '${calcRate.toInt()}%'
          : '${calcRate.toStringAsFixed(1)}%';
    }

    return Column(
      children: [
        _DetailRow(label: 'Booking ID', value: bookingIdDisplay),
        _DetailRow(label: 'Service', value: serviceName),
        _DetailRow(label: 'Completed Date & Time', value: completedDateDisplay),
        _DetailRow(label: 'Commission Rate', value: rateDisplay),
        _DetailRow(
          label: 'Commission Amount',
          value: '- ${currencyFormatter.format(transaction.amount)}',
          valueStyle: const TextStyle(
            color: AppColors.error,
            fontWeight: FontWeight.bold,
          ),
        ),
        _DetailRow(
          label: 'Wallet Balance Before',
          value: currencyFormatter.format(balanceBefore),
        ),
        _DetailRow(
          label: 'Wallet Balance After',
          value: currencyFormatter.format(balanceAfter),
          valueStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.valueStyle,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: valueStyle ??
                  const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
