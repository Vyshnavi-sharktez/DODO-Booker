import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/utils/format_utils.dart';
import '../../domain/models/booking.dart';
import '../../domain/models/booking_item.dart';
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
  bool _verifying = false;
  // Set to true after any successful action so buttons stay permanently
  // disabled while the provider refresh removes the card from its current tab.
  bool _processed = false;

  final TextEditingController _otpController = TextEditingController();
  String? _otpError;

  bool get _busy => _updating || _rejecting || _verifying || _processed;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

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

  // ── Start Service ─────────────────────────────────────────────────────────
  // Completion now requires OTP — handled by _handleInitiateCompletion and
  // _handleVerifyOtp instead of the generic _handleAction path.
  // DODO Team bookings skip the Start Service step (admin starts the service).

  bool get _isDodoBooking => widget.booking.isDodoTeam;

  String? get _actionLabel =>
      widget.booking.status == 'assigned' && !_isDodoBooking
          ? 'Start Service'
          : null;

  String? get _targetStatus =>
      widget.booking.status == 'assigned' && !_isDodoBooking
          ? 'in_progress'
          : null;

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

      // Notifications — fire-and-forget; must not block the status update.
      if (targetStatus == 'in_progress') {
        ref.read(bookingsRepositoryProvider).createAdminNotification(
          title: 'Vendor Started Service',
          message: 'Vendor $_vendorName started work on booking $_bookingRef.',
          notificationType: 'vendor_started',
          entityId: widget.booking.id,
        ).ignore();
        ref.read(bookingsRepositoryProvider).createCustomerNotification(
          customerId: widget.booking.customerId,
          title: 'Service Started',
          message: 'Your service is now in progress.',
          notificationType: 'vendor_started',
          entityId: widget.booking.id,
        ).ignore();
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

  // ── Initiate OTP completion ───────────────────────────────────────────────

  Future<void> _handleInitiateCompletion() async {
    debugPrint('[OTP] Complete Service tapped — bookingId=${widget.booking.id}');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _ConfirmDialog(
        title: 'Complete Service',
        message: 'An OTP will be generated and shown to the customer.\n\n'
            'Ask them to share it with you to confirm service completion.',
        confirmLabel: 'Generate OTP',
        confirmColor: AppColors.success,
      ),
    );
    if (confirmed != true || !mounted) {
      debugPrint('[OTP] Initiate cancelled by user');
      return;
    }

    setState(() => _updating = true);
    try {
      debugPrint('[OTP] Calling initiateCompletion…');
      await ref
          .read(initiateCompletionUseCaseProvider)
          .call(widget.booking.id);
      debugPrint('[OTP] initiateCompletion succeeded — status=awaiting_verification');

      // Do NOT set _processed=true here. This is NOT a terminal action:
      // the card stays in the In-Progress tab as awaiting_verification and the
      // vendor still needs to enter the OTP. Setting _processed would
      // permanently disable the Verify button via _busy.

      final providerLabel = _isDodoBooking ? 'DODO Team' : 'the vendor';
      ref.read(bookingsRepositoryProvider).createCustomerNotification(
        customerId: widget.booking.customerId,
        title: 'OTP for Service Completion',
        message: 'Your service is complete. Open your booking to view the OTP '
            'and share it with $providerLabel.',
        notificationType: 'otp_generated',
        entityId: widget.booking.id,
      ).ignore();

      ref.invalidate(vendorBookingsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('OTP sent to customer. Enter it below to complete.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('[OTP] initiateCompletion ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate OTP: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      // Always reset _updating — never gate on _processed here because we
      // deliberately do not set _processed after initiating completion.
      if (mounted) setState(() => _updating = false);
    }
  }

  // ── Verify customer OTP ───────────────────────────────────────────────────

  Future<void> _handleVerifyOtp() async {
    // ── Diagnostic checkpoint 1: confirm function was reached ────────────────
    debugPrint('[OTP][VERIFY] ══════════ _handleVerifyOtp() ENTERED ══════════');
    debugPrint('[OTP][VERIFY] State at entry — _busy=$_busy _processed=$_processed '
        '_updating=$_updating _verifying=$_verifying _rejecting=$_rejecting');

    // ── Diagnostic checkpoint 2: inspect the raw TextField value ─────────────
    final rawText = _otpController.text;
    final otp = rawText.trim();
    debugPrint('[OTP][VERIFY] TextField raw  : "$rawText"');
    debugPrint('[OTP][VERIFY] TextField trim : "$otp"');
    debugPrint('[OTP][VERIFY] codeUnits      : ${rawText.codeUnits}');
    debugPrint('[OTP][VERIFY] trimmed length : ${otp.length}');

    if (otp.length != 6) {
      debugPrint('[OTP][VERIFY] ✗ Validation failed: length ${otp.length} ≠ 6 — aborting');
      setState(() => _otpError = 'Enter the 6-digit OTP');
      return;
    }
    debugPrint('[OTP][VERIFY] ✓ Validation passed');

    setState(() {
      _verifying = true;
      _otpError = null;
    });
    debugPrint('[OTP][VERIFY] _verifying=true set — calling use case…');

    try {
      // ── Diagnostic checkpoint 3: confirm use case is invoked ─────────────
      debugPrint('[OTP][VERIFY] Invoking verifyCompletionOtpUseCaseProvider '
          '— bookingId=${widget.booking.id} otp="$otp"');
      final verified = await ref
          .read(verifyCompletionOtpUseCaseProvider)
          .call(widget.booking.id, otp);
      debugPrint('[OTP][VERIFY] Use case returned: verified=$verified');

      if (!mounted) {
        debugPrint('[OTP][VERIFY] Widget unmounted after await — returning');
        return;
      }

      if (!verified) {
        debugPrint('[OTP][VERIFY] ✗ OTP rejected — showing error to user');
        setState(() {
          _otpError = 'Incorrect OTP. Please try again.';
          _verifying = false;
        });
        return;
      }

      debugPrint('[OTP][VERIFY] ✓ OTP accepted — marking card as processed (terminal)');
      // Terminal action: lock the card while it moves to the Completed tab.
      setState(() => _processed = true);

      final completedBy = _isDodoBooking ? 'DODO Team ($_vendorName)' : 'Vendor $_vendorName';
      ref.read(bookingsRepositoryProvider).createAdminNotification(
        title: 'Booking Completed',
        message: '$completedBy completed booking $_bookingRef via OTP.',
        notificationType: 'booking_completed',
        entityId: widget.booking.id,
      ).ignore();
      ref.read(bookingsRepositoryProvider).createCustomerNotification(
        customerId: widget.booking.customerId,
        title: 'Service Completed',
        message: 'Your service has been completed. You can now rate the experience.',
        notificationType: 'booking_completed',
        entityId: widget.booking.id,
      ).ignore();

      ref.invalidate(vendorBookingsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Booking $_bookingRef completed successfully.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('[OTP] verifyCompletionOtp ERROR: $e');
      if (mounted) {
        setState(() {
          _otpError = 'Verification failed: $e';
        });
      }
    } finally {
      // Reset _verifying unless the card has already been locked as terminal.
      if (mounted && !_processed) setState(() => _verifying = false);
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

      // Notifications — fire-and-forget; must not block the rejection.
      ref.read(bookingsRepositoryProvider).createAdminNotification(
        title: 'Vendor Rejected Booking',
        message: 'Vendor $_vendorName rejected booking $_bookingRef.\n'
            'Reason: $reason',
        notificationType: 'vendor_rejected',
        entityId: widget.booking.id,
      ).ignore();
      ref.read(bookingsRepositoryProvider).createCustomerNotification(
        customerId: widget.booking.customerId,
        title: 'Vendor Reassignment Required',
        message: 'Your assigned vendor is unavailable. '
            'A new provider will be assigned shortly.',
        notificationType: 'vendor_rejected',
        entityId: widget.booking.id,
      ).ignore();

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
    // Vendor: assigned → Start Service → in_progress → Complete Service → awaiting_verification → OTP → completed.
    // DODO Team: admin handles assignment; team sees in_progress → Complete Service → awaiting_verification → OTP → completed.
    // isAssigned guards against showing vendor-only buttons if a DODO booking ever lands in 'assigned'.
    final isAssigned = widget.booking.status == 'assigned' && !_isDodoBooking;
    final isInProgress = widget.booking.status == 'in_progress';
    final isAwaitingVerification = widget.booking.status == 'awaiting_verification';
    final showOtpPanel = isAwaitingVerification;
    final isRejected = widget.booking.status == 'rejected';

    // Diagnostic: log button state on every rebuild for OTP panel cards.
    if (showOtpPanel) {
      debugPrint(
        '[OTP][BUILD] Card rebuilt — bookingId=${widget.booking.id} '
        '_busy=$_busy (_processed=$_processed _updating=$_updating '
        '_verifying=$_verifying _rejecting=$_rejecting) '
        '→ Verify button is ${_busy ? "DISABLED (onPressed=null)" : "ENABLED"}',
      );
    }

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
              children: [
                Flexible(
                  child: Text(
                    '#${widget.booking.bookingNumber}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                BookingStatusBadge(status: widget.booking.status),
              ],
            ),
            const SizedBox(height: 12),

            if (widget.booking.items.isNotEmpty)
              _ServicesBlock(items: widget.booking.items)
            else if (widget.booking.notes != null &&
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
                Flexible(
                  child: Text(
                    FormatUtils.currency(widget.booking.totalAmount),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isRejected
                          ? AppColors.textSecondary
                          : AppColors.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isRejected && widget.booking.rejectedAt != null)
                  Flexible(
                    child: Text(
                      'Rejected ${AppDateUtils.relativeLabel(widget.booking.rejectedAt!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.error.withValues(alpha: 0.8),
                      ),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  )
                else if (widget.booking.createdAt != null)
                  Flexible(
                    child: Text(
                      AppDateUtils.relativeLabel(widget.booking.createdAt!),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textHint,
                      ),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
              ],
            ),

            // ── Actions: Assigned (vendor only) ───────────────────────────
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

            // ── Actions: In Progress → Complete Service (vendor and DODO Team) ──
            // Triggers OTP generation/notification and moves to awaiting_verification.
            if (isInProgress) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _handleInitiateCompletion,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _updating
                      ? const _Spinner(color: Colors.white)
                      : const Text('Complete Service'),
                ),
              ),
            ],

            // ── Actions: Enter OTP (awaiting_verification — both roles) ──────
            if (showOtpPanel) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.lock_clock_rounded,
                          size: 15,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Enter OTP from customer',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 10,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '_ _ _ _ _ _',
                        hintStyle: TextStyle(
                          letterSpacing: 6,
                          color: AppColors.textHint,
                        ),
                        errorText: _otpError,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onChanged: (_) {
                        if (_otpError != null) {
                          setState(() => _otpError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : _handleVerifyOtp,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.success,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _verifying
                            ? const _Spinner(color: Colors.white)
                            : const Text('Verify & Complete'),
                      ),
                    ),
                  ],
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

// Renders all booking items as labelled rows with icon.
class _ServicesBlock extends StatelessWidget {
  const _ServicesBlock({required this.items});
  final List<BookingItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.home_repair_service_outlined,
              size: 16, color: AppColors.textHint),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (items.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${items.length} services',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ...items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.displayLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '₹${item.totalPrice.toStringAsFixed(0)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
