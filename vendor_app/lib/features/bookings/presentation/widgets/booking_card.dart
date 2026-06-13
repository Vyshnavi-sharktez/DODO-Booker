import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/utils/format_utils.dart';
import '../../domain/models/booking.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../providers/bookings_provider.dart';
import 'booking_status_badge.dart';
import 'reject_dialog.dart';

class BookingCard extends ConsumerStatefulWidget {
  const BookingCard({super.key, required this.booking});

  final Booking booking;

  @override
  ConsumerState<BookingCard> createState() => _BookingCardState();
}

class _BookingCardState extends ConsumerState<BookingCard> {
  bool _updating = false;
  bool _rejecting = false;
  // Set to true after any successful action so buttons stay permanently
  // disabled while the provider refresh removes the card from its current tab.
  bool _processed = false;

  bool get _busy => _updating || _rejecting || _processed;

  // Returns "#<booking_number>" when available, otherwise "#<first-8-uuid-chars>".
  String get _bookingRef {
    final num = widget.booking.bookingNumber;
    if (num.isNotEmpty) return '#$num';
    final id = widget.booking.id;
    return '#${id.length > 8 ? id.substring(0, 8) : id}';
  }

  // Vendor's business name from the auth session, with phone as fallback.
  String get _vendorName {
    final v = ref.read(currentVendorUserProvider);
    return v?.name ?? v?.phone ?? 'Vendor';
  }

  // ── Start Service / Mark Complete ─────────────────────────────────────────

  String? get _actionLabel => switch (widget.booking.status) {
        'assigned' => 'Start Service',
        'in_progress' => 'Mark Complete',
        _ => null,
      };

  String? get _targetStatus => switch (widget.booking.status) {
        'assigned' => 'in_progress',
        'in_progress' => 'completed',
        _ => null,
      };

  Future<void> _handleAction() async {
    final targetStatus = _targetStatus;
    final label = _actionLabel;
    if (targetStatus == null || label == null) return;

    final (title, message, confirmColor) = switch (targetStatus) {
      'in_progress' => (
          'Start Service',
          'Start service for booking #${widget.booking.bookingNumber}?\n\n'
              'Status will change to In Progress.',
          AppColors.primary,
        ),
      'completed' => (
          'Mark Complete',
          'Mark booking #${widget.booking.bookingNumber} as complete?\n\n'
              'This action cannot be undone.',
          AppColors.success,
        ),
      _ => ('Confirm', 'Are you sure?', AppColors.primary),
    };

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: title,
        message: message,
        confirmLabel: label,
        confirmColor: confirmColor,
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _updating = true);
    try {
      await ref
          .read(updateBookingStatusUseCaseProvider)
          .call(widget.booking.id, targetStatus);
      if (mounted) setState(() => _processed = true);

      // Notify admin when the vendor starts the service — failure must not
      // block the status update.
      if (targetStatus == 'in_progress') {
        ref
            .read(bookingsRepositoryProvider)
            .createAdminNotification(
              title: 'Vendor Started Service',
              message:
                  'Vendor $_vendorName started work on booking $_bookingRef.',
              notificationType: 'vendor_started',
            )
            .ignore();
      }

      ref.invalidate(vendorBookingsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Booking #${widget.booking.bookingNumber} updated successfully.',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted && !_processed) setState(() => _updating = false);
    }
  }

  // ── Reject Service ────────────────────────────────────────────────────────

  Future<void> _handleReject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) =>
          RejectDialog(bookingNumber: widget.booking.bookingNumber),
    );
    if (reason == null || !mounted) return;

    setState(() => _rejecting = true);
    try {
      await ref.read(rejectBookingUseCaseProvider).call(
            bookingId: widget.booking.id,
            rejectionReason: reason,
          );
      if (mounted) setState(() => _processed = true);

      // Notify admin of rejection with the reason — failure must not block.
      ref
          .read(bookingsRepositoryProvider)
          .createAdminNotification(
            title: 'Vendor Rejected Booking',
            message:
                'Vendor $_vendorName rejected booking $_bookingRef.\n'
                'Reason: $reason',
            notificationType: 'vendor_rejected',
          )
          .ignore();

      ref.invalidate(vendorBookingsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Booking #${widget.booking.bookingNumber} moved to Rejected.',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reject failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted && !_processed) setState(() => _rejecting = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAssigned = widget.booking.status == 'assigned';
    final isInProgress = widget.booking.status == 'in_progress';
    final isRejected = widget.booking.status == 'rejected';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isRejected
              ? AppColors.error.withValues(alpha: 0.35)
              : AppColors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '#${widget.booking.bookingNumber}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                BookingStatusBadge(status: widget.booking.status),
              ],
            ),
            const SizedBox(height: 12),

            if (widget.booking.notes != null &&
                widget.booking.notes!.isNotEmpty)
              _InfoRow(
                icon: Icons.home_repair_service_outlined,
                label: widget.booking.notes!,
              ),
            if (widget.booking.serviceDate != null)
              _InfoRow(
                icon: Icons.calendar_today_outlined,
                label: AppDateUtils.formatDisplay(widget.booking.serviceDate!),
              ),
            if (widget.booking.address != null &&
                widget.booking.address!.isNotEmpty)
              _InfoRow(
                icon: Icons.location_on_outlined,
                label: widget.booking.address!,
                maxLines: 2,
              ),

            // ── Rejection reason banner ───────────────────────────────────
            if (isRejected &&
                (widget.booking.rejectionReason?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.block_rounded,
                        size: 15, color: AppColors.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.error),
                          children: [
                            const TextSpan(
                              text: 'Rejected  ',
                              style:
                                  TextStyle(fontWeight: FontWeight.w700),
                            ),
                            TextSpan(
                              text: widget.booking.rejectionReason ?? '',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  FormatUtils.currency(widget.booking.totalAmount),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isRejected
                        ? AppColors.textSecondary
                        : AppColors.primary,
                  ),
                ),
                if (isRejected && widget.booking.rejectedAt != null)
                  Text(
                    'Rejected ${AppDateUtils.relativeLabel(widget.booking.rejectedAt!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.error.withValues(alpha: 0.8),
                    ),
                  )
                else if (widget.booking.createdAt != null)
                  Text(
                    AppDateUtils.relativeLabel(widget.booking.createdAt!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textHint,
                    ),
                  ),
              ],
            ),

            // ── Actions: Assigned ─────────────────────────────────────────
            if (isAssigned) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _handleAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _updating
                      ? const _Spinner(color: Colors.white)
                      : const Text('Start Service'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _handleReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: _rejecting
                      ? const _Spinner(color: AppColors.error)
                      : const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('Reject Service'),
                ),
              ),
            ],

            // ── Actions: In Progress ───────────────────────────────────────
            if (isInProgress) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _handleAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _updating
                      ? const _Spinner(color: Colors.white)
                      : const Text('Mark Complete'),
                ),
              ),
            ],

            // Rejected / Completed / Cancelled: no action buttons.
          ],
        ),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _Spinner extends StatelessWidget {
  const _Spinner({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2, color: color),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    this.maxLines = 1,
  });

  final IconData icon;
  final String label;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textHint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.confirmColor,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final Color confirmColor;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(backgroundColor: confirmColor),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
