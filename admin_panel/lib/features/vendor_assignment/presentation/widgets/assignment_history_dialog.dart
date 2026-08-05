import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../bookings/application/providers/dispatch_providers.dart';
import '../../../bookings/domain/models/booking.dart';
import '../../../bookings/domain/models/booking_assignment_record.dart';

final _dateFmt = DateFormat('dd MMM yyyy, hh:mm a');
final _timeOnlyFmt = DateFormat('hh:mm:ss a');

class AssignmentHistoryDialog extends ConsumerWidget {
  final Booking booking;

  const AssignmentHistoryDialog({
    super.key,
    required this.booking,
  });

  String _formatResponseTime(
    BookingAssignmentRecord record,
    int configuredTimeoutSeconds,
  ) {
    if (record.status == 'timed_out') {
      int secs = configuredTimeoutSeconds;
      if (record.respondedAt != null) {
        final diff = record.respondedAt!.difference(record.assignedAt).inSeconds.abs();
        if (diff > 0 && diff <= configuredTimeoutSeconds) {
          secs = diff;
        }
      }
      return '${secs}s (Timed Out)';
    }
    if (record.respondedAt == null) {
      if (record.status == 'pending') return 'In progress';
      return '—';
    }
    final diff = record.respondedAt!.difference(record.assignedAt);
    final secs = diff.inSeconds.abs();
    if (secs < 60) return '${secs}s';
    final mins = secs ~/ 60;
    final remSecs = secs % 60;
    return '${mins}m ${remSecs}s';
  }

  (String label, Color color, Color bg) _statusBadge(String status) =>
      switch (status) {
        'accepted'  => ('Accepted', const Color(0xFF38A169), const Color(0xFFF0FFF4)),
        'rejected'  => ('Rejected', const Color(0xFFE53E3E), const Color(0xFFFFF5F5)),
        'timed_out' => ('Timed Out', const Color(0xFFDD6B20), const Color(0xFFFEEBC8)),
        'pending'   => ('Pending', const Color(0xFF3182CE), const Color(0xFFEBF8FF)),
        _           => (status, const Color(0xFF718096), const Color(0xFFEDF2F7)),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(bookingAssignmentsHistoryProvider(booking.id));
    final dispatchSettings = ref.watch(dispatchSettingsNotifierProvider).valueOrNull;
    final timeoutSeconds = dispatchSettings?.tierTimeoutSeconds ?? 46;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.history_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Dispatch & Assignment History — #${booking.bookingNumber}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // ── Body ────────────────────────────────────────────────────────
            historyAsync.when(
              loading: () => const SizedBox(
                height: 240,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => SizedBox(
                height: 240,
                child: Center(
                  child: Text('Failed to load history: $e',
                      style: const TextStyle(color: AppColors.error)),
                ),
              ),
              data: (records) {
                final acceptedRecord = records
                    .where((r) => r.status == 'accepted')
                    .firstOrNull;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Summary Banner ──────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: acceptedRecord != null
                            ? const Color(0xFFF0FFF4)
                            : (booking.dispatchStatus == 'exhausted'
                                ? const Color(0xFFFFF5F5)
                                : const Color(0xFFEBF8FF)),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: acceptedRecord != null
                              ? const Color(0xFF38A169).withValues(alpha: 0.4)
                              : (booking.dispatchStatus == 'exhausted'
                                  ? const Color(0xFFE53E3E).withValues(alpha: 0.4)
                                  : const Color(0xFF3182CE).withValues(alpha: 0.4)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            acceptedRecord != null
                                ? Icons.check_circle_rounded
                                : (booking.dispatchStatus == 'exhausted'
                                    ? Icons.cancel_rounded
                                    : Icons.hourglass_top_rounded),
                            size: 24,
                            color: acceptedRecord != null
                                ? const Color(0xFF38A169)
                                : (booking.dispatchStatus == 'exhausted'
                                    ? const Color(0xFFE53E3E)
                                    : const Color(0xFF3182CE)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  acceptedRecord != null
                                      ? 'Final Accepted Vendor: ${acceptedRecord.vendor?.businessName ?? booking.vendorName}'
                                      : (booking.dispatchStatus == 'exhausted'
                                          ? 'No Vendor Accepted (Dispatch Exhausted)'
                                          : 'Auto-Dispatching in Progress'),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: acceptedRecord != null
                                        ? const Color(0xFF276749)
                                        : (booking.dispatchStatus == 'exhausted'
                                            ? const Color(0xFF9B2C2C)
                                            : const Color(0xFF2C5282)),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  acceptedRecord != null
                                      ? 'Accepted at ${_timeOnlyFmt.format(acceptedRecord.respondedAt ?? acceptedRecord.assignedAt)} · Response time: ${_formatResponseTime(acceptedRecord, timeoutSeconds)}'
                                      : '${records.length} attempt(s) recorded from database',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (records.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            'No assignment attempts recorded in database.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 320),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Table Header
                            Container(
                              color: AppColors.background,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              child: const Row(
                                children: [
                                  _HCell('Attempt / Tier', flex: 3),
                                  _HCell('Vendor', flex: 3),
                                  _HCell('Assigned Time', flex: 3),
                                  _HCell('Result', flex: 2),
                                  _HCell('Response', flex: 2),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            Flexible(
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: records.length,
                                separatorBuilder: (context, index) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final r = records[index];
                                  final (statusLabel, statusColor, statusBg) =
                                      _statusBadge(r.status);
                                  final vendorName = r.vendor?.businessName ??
                                      'Vendor #${r.vendorId?.substring(0, 6) ?? ''}';
                                  final tierName = r.vendorTier?.name ??
                                      'Tier ${r.tierPriority ?? r.attemptNumber}';

                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    color: r.status == 'accepted'
                                        ? const Color(0xFFF0FFF4)
                                        : null,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            // Attempt & Tier
                                            Expanded(
                                              flex: 3,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Attempt #${r.attemptNumber}',
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color:
                                                          AppColors.textPrimary,
                                                    ),
                                                  ),
                                                  Text(
                                                    tierName,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: AppColors
                                                          .textSecondary,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // Vendor
                                            Expanded(
                                              flex: 3,
                                              child: Text(
                                                vendorName,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.textPrimary,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),

                                            // Assigned Time
                                            Expanded(
                                              flex: 3,
                                              child: Text(
                                                _dateFmt.format(
                                                    r.assignedAt.toLocal()),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                      AppColors.textSecondary,
                                                ),
                                              ),
                                            ),

                                            // Result status badge
                                            Expanded(
                                              flex: 2,
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: statusBg,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                  ),
                                                  child: Text(
                                                    statusLabel,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: statusColor,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),

                                            // Response Time
                                            Expanded(
                                              flex: 2,
                                              child: Text(
                                                _formatResponseTime(r, timeoutSeconds),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                  color:
                                                      AppColors.textSecondary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),

                                        if (r.rejectionReason != null &&
                                            r.rejectionReason!.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(left: 4),
                                            child: Text(
                                              'Reason: "${r.rejectionReason}"',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontStyle: FontStyle.italic,
                                                color: AppColors.error,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),

            // ── Footer ──────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HCell extends StatelessWidget {
  final String label;
  final int flex;

  const _HCell(this.label, {required this.flex});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
