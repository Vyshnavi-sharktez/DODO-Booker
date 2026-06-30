import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/vendor_settlement_providers.dart';

class SettlementHistoryDialog extends ConsumerWidget {
  const SettlementHistoryDialog({
    super.key,
    required this.vendorId,
    required this.vendorName,
  });
  final String vendorId;
  final String vendorName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(vendorSettlementHistoryProvider(vendorId));
    final dateFmt = DateFormat('dd MMM yyyy, hh:mm a');
    final moneyFmt = NumberFormat('#,##0.00', 'en_IN');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
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
                      Icons.history_rounded,
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
                          'Settlement History',
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
              const SizedBox(height: 8),

              historyAsync.when(
                loading: () => const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Expanded(
                  child: Center(
                    child: Text(
                      'Error loading history: $e',
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ),
                ),
                data: (history) {
                  if (history.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.history_rounded,
                              size: 40,
                              color: AppColors.border,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'No settlement records found',
                              style:
                                  TextStyle(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: Table(
                          columnWidths: const {
                            0: FixedColumnWidth(110),
                            1: FlexColumnWidth(1.8),
                            2: FlexColumnWidth(1.6),
                            3: FlexColumnWidth(1.6),
                            4: FlexColumnWidth(2.2),
                            5: FlexColumnWidth(1.6),
                            6: FlexColumnWidth(2.4),
                            7: FixedColumnWidth(80),
                          },
                          children: [
                            TableRow(
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              children: const [
                                _HeaderCell('Settlement ID'),
                                _HeaderCell('Amount'),
                                _HeaderCell('Payment Method'),
                                _HeaderCell('Reference'),
                                _HeaderCell('Notes'),
                                _HeaderCell('Paid By'),
                                _HeaderCell('Paid On'),
                                _HeaderCell('Status'),
                              ],
                            ),
                            for (final entry in history)
                              TableRow(
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: AppColors.border,
                                      width: 0.5,
                                    ),
                                  ),
                                ),
                                children: [
                                  _DataCell(
                                    child: Text(
                                      '#${entry.id.length > 8 ? entry.id.substring(0, 8).toUpperCase() : entry.id.toUpperCase()}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                  _DataCell(
                                    child: Text(
                                      '₹${moneyFmt.format(entry.amount)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.success,
                                      ),
                                    ),
                                  ),
                                  _DataCell(
                                    child: Text(
                                      entry.paymentMethod ?? '—',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  _DataCell(
                                    child: Text(
                                      entry.referenceNumber ?? '—',
                                      style: const TextStyle(fontSize: 12),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  _DataCell(
                                    child: Text(
                                      entry.notes ?? '—',
                                      style: const TextStyle(fontSize: 12),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  _DataCell(
                                    child: Text(
                                      entry.settledBy,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  _DataCell(
                                    child: Text(
                                      dateFmt.format(entry.settledAt),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  _DataCell(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.success
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        'Paid',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.success,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
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
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: child,
    );
  }
}
