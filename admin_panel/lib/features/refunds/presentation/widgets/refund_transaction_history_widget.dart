import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../domain/models/refund_transaction.dart';

class RefundTransactionHistoryWidget extends StatelessWidget {
  final List<RefundTransaction> transactions;
  final void Function(RefundTransaction txn)? onMarkComplete;
  final void Function(RefundTransaction txn)? onMarkFailed;
  final void Function(RefundTransaction txn)? onProcessViaRazorpay;

  const RefundTransactionHistoryWidget({
    super.key,
    required this.transactions,
    this.onMarkComplete,
    this.onMarkFailed,
    this.onProcessViaRazorpay,
  });

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: Color(0xFF718096)),
            SizedBox(width: 8),
            Text(
              'No refund transactions yet. Initiate one after approving.',
              style: TextStyle(fontSize: 13, color: Color(0xFF718096)),
            ),
          ],
        ),
      );
    }

    return Column(
      children: transactions
          .map((t) => _TransactionCard(
                transaction: t,
                onMarkComplete: onMarkComplete != null
                    ? () => onMarkComplete!(t)
                    : null,
                onMarkFailed: onMarkFailed != null
                    ? () => onMarkFailed!(t)
                    : null,
                onProcessViaRazorpay: onProcessViaRazorpay != null
                    ? () => onProcessViaRazorpay!(t)
                    : null,
              ))
          .toList(),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final RefundTransaction transaction;
  final VoidCallback? onMarkComplete;
  final VoidCallback? onMarkFailed;
  final VoidCallback? onProcessViaRazorpay;

  const _TransactionCard({
    required this.transaction,
    this.onMarkComplete,
    this.onMarkFailed,
    this.onProcessViaRazorpay,
  });

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final fmt = NumberFormat('#,##0.00', 'en_IN');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: t.statusColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.statusColor.withAlpha(80)),
                ),
                child: Text(
                  t.statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: t.statusColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '₹${fmt.format(t.amount)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D3748),
                ),
              ),
              const Spacer(),
              Text(
                t.gatewayLabel,
                style: const TextStyle(fontSize: 12, color: Color(0xFF718096)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            t.refundMethodLabel,
            style: const TextStyle(fontSize: 12, color: Color(0xFF4A5568)),
          ),
          if (t.gatewayRefundId != null) ...[
            const SizedBox(height: 4),
            Text(
              'Ref: ${t.gatewayRefundId}',
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: Color(0xFF718096),
              ),
            ),
          ],
          if (t.failureReason != null) ...[
            const SizedBox(height: 4),
            Text(
              'Failure: ${t.failureReason}',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFE53E3E),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            DateFormat('d MMM yyyy, h:mm a').format(t.initiatedAt.toLocal()),
            style: const TextStyle(fontSize: 11, color: Color(0xFF718096)),
          ),
          // ── Action buttons for pending/processing transactions ──────────
          if (t.status == RefundTransactionStatus.pending ||
              t.status == RefundTransactionStatus.processing) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            // "Process via Razorpay" — shown only for pending Razorpay
            // transactions. Calls the Edge Function which handles the API
            // call atomically and marks the transaction complete/failed.
            if (t.canProcessViaRazorpay && onProcessViaRazorpay != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onProcessViaRazorpay,
                    icon: const Icon(Icons.send_rounded, size: 14),
                    label: const Text('Process via Razorpay'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF3182CE),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
            // Manual complete/failed buttons — always available for
            // pending/processing so admin can reconcile manually.
            Row(
              children: [
                if (onMarkComplete != null)
                  OutlinedButton.icon(
                    onPressed: onMarkComplete,
                    icon: const Icon(Icons.check_circle_outline, size: 14),
                    label: const Text('Mark Complete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF38A169),
                      side: const BorderSide(color: Color(0xFF38A169)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                const SizedBox(width: 8),
                if (onMarkFailed != null)
                  OutlinedButton.icon(
                    onPressed: onMarkFailed,
                    icon: const Icon(Icons.cancel_outlined, size: 14),
                    label: const Text('Mark Failed'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE53E3E),
                      side: const BorderSide(color: Color(0xFFE53E3E)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
