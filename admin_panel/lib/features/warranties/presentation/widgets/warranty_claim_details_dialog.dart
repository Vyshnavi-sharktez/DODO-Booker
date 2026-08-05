import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/service_warranty.dart';
import '../../application/warranties_providers.dart';
import 'warranty_claim_reject_dialog.dart';
import '../../../bookings/presentation/widgets/booking_assignment_dialog.dart';
import '../../../bookings/presentation/widgets/booking_details_dialog.dart';
import '../../../bookings/application/providers/bookings_providers.dart';

class WarrantyClaimDetailsDialog extends ConsumerStatefulWidget {
  final ServiceWarranty warranty;

  const WarrantyClaimDetailsDialog({
    super.key,
    required this.warranty,
  });

  @override
  ConsumerState<WarrantyClaimDetailsDialog> createState() =>
      _WarrantyClaimDetailsDialogState();
}

class _WarrantyClaimDetailsDialogState
    extends ConsumerState<WarrantyClaimDetailsDialog> {
  bool _approving = false;
  bool _resolving = false;
  String? _errorMessage;

  Future<void> _approveClaim() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Warranty Claim?'),
        content: Text(
          'This will approve the claim for Booking #${widget.warranty.bookingNumber ?? widget.warranty.bookingId} '
          'and move the rework booking into the assignment workflow.',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF38A169)),
            child: const Text('Approve Claim'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _approving = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(warrantiesRepositoryProvider);
      final bookingNum = widget.warranty.bookingNumber ?? widget.warranty.bookingId;

      await repo.approveWarrantyClaim(
        warrantyId: widget.warranty.id,
        reworkBookingId: widget.warranty.reworkBookingId,
        customerId: widget.warranty.customerId,
        bookingNumber: bookingNum,
      );

      ref.invalidate(adminWarrantiesProvider);

      if (!mounted) return;

      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Warranty Claim for Booking #$bookingNum approved successfully.'),
          backgroundColor: const Color(0xFF38A169),
        ),
      );

      if (widget.warranty.reworkBookingId != null) {
        final assignNow = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Assign Vendor for Rework?'),
            content: const Text('Would you like to assign a vendor for this approved rework booking now?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Later')),
              FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Assign Vendor')),
            ],
          ),
        );

        if (assignNow == true && mounted) {
          final repo = ref.read(bookingsRepositoryProvider);
          final booking = await repo.fetchBookingById(widget.warranty.reworkBookingId!);
          if (booking != null && mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => BookingAssignmentDialog(
                booking: booking,
                onSave: ({
                  required assignmentType,
                  vendorId,
                  dodoTeamId,
                  required serviceDate,
                  notes,
                }) async {
                  await ref
                      .read(bookingsNotifierProvider.notifier)
                      .updateBookingAssignment(
                        booking.id,
                        assignmentType: assignmentType,
                        vendorId: vendorId,
                        dodoTeamId: dodoTeamId,
                        serviceDate: serviceDate,
                        notes: notes,
                      );
                },
              ),
            );
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _approving = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _rejectClaim() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => WarrantyClaimRejectDialog(warranty: widget.warranty),
    );

    if (result == true && mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Warranty claim rejected.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _markResolved() async {
    setState(() => _resolving = true);
    try {
      final repo = ref.read(warrantiesRepositoryProvider);
      await repo.markWarrantyResolved(widget.warranty.id);
      ref.invalidate(adminWarrantiesProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Warranty claim marked as Resolved.'),
          backgroundColor: Color(0xFF38A169),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _resolving = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _openBookingDetails(String bookingId) async {
    if (bookingId.isEmpty) return;
    try {
      final repo = ref.read(bookingsRepositoryProvider);
      final booking = await repo.fetchBookingById(bookingId);
      if (booking != null && mounted) {
        showDialog(
          context: context,
          builder: (_) => BookingDetailsDialog(booking: booking),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load booking details.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading booking: $e')),
        );
      }
    }
  }

  void _showImageLightboxGallery(List<String> urls, int initialIndex, String title) {
    if (urls.isEmpty) return;
    showDialog(
      context: context,
      builder: (_) => _ImageGalleryLightboxDialog(
        urls: urls,
        initialIndex: initialIndex,
        title: title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd MMM yyyy, hh:mm a');
    final bookingNum = widget.warranty.bookingNumber ??
        (widget.warranty.bookingId.length > 8
            ? widget.warranty.bookingId.substring(0, 8).toUpperCase()
            : widget.warranty.bookingId.toUpperCase());
    final reworkBookingId = widget.warranty.reworkBookingId ?? '';
    final photosAsync = ref.watch(reworkImagesGroupedProvider(reworkBookingId));

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 860),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.shield_rounded, color: AppColors.primary, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Warranty Claim Operations',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          Text(
                            'Certificate #${widget.warranty.certificateNumber}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Refresh Status',
                        icon: const Icon(Icons.refresh_rounded),
                        onPressed: () {
                          ref.invalidate(adminWarrantiesProvider);
                          ref.invalidate(reworkImagesGroupedProvider(reworkBookingId));
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),

              const Divider(height: 24),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: AppColors.error, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Status Badge Banner
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: _getStatusBgColor(widget.warranty.status),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _getStatusBorderColor(widget.warranty.status)),
                        ),
                        child: Row(
                          children: [
                            Icon(_getStatusIcon(widget.warranty.status),
                                size: 20, color: _getStatusFgColor(widget.warranty.status)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Claim Status: ${_getDisplayStatusLabel(widget.warranty)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: _getStatusFgColor(widget.warranty.status),
                                    ),
                                  ),
                                  if (widget.warranty.claimedAt != null)
                                    Text(
                                      'Submitted on ${dateFmt.format(widget.warranty.claimedAt!)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: _getStatusFgColor(widget.warranty.status).withValues(alpha: 0.8),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Lifecycle Timeline Stepper
                      _WarrantyTimelineSection(warranty: widget.warranty),

                      const SizedBox(height: 24),

                      // Customer & Booking Quick Link Cards
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Customer Info Card
                          Expanded(
                            child: _InfoSectionCard(
                              title: 'Customer Details',
                              icon: Icons.person_rounded,
                              children: [
                                _InfoRow(label: 'Name', value: widget.warranty.customerName ?? 'Customer'),
                                _InfoRow(label: 'Email', value: widget.warranty.customerEmail ?? '—'),
                                _InfoRow(label: 'Phone', value: widget.warranty.customerPhone ?? '—'),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Booking & Quick Link Card
                          Expanded(
                            child: _InfoSectionCard(
                              title: 'Bookings & Links',
                              icon: Icons.link_rounded,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Original Booking:', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                    InkWell(
                                      onTap: () => _openBookingDetails(widget.warranty.bookingId),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text('#$bookingNum', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                                          const SizedBox(width: 2),
                                          const Icon(Icons.open_in_new_rounded, size: 12, color: AppColors.primary),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                if (widget.warranty.reworkBookingId != null) ...[
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Rework Booking:', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                      InkWell(
                                        onTap: () => _openBookingDetails(widget.warranty.reworkBookingId!),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '#${widget.warranty.reworkBookingNumber ?? widget.warranty.reworkBookingId!.substring(0, 8)}',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF38A169)),
                                            ),
                                            const SizedBox(width: 2),
                                            const Icon(Icons.open_in_new_rounded, size: 12, color: Color(0xFF38A169)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                ],
                                _InfoRow(
                                  label: 'Assigned Vendor',
                                  value: widget.warranty.reworkVendorName ?? widget.warranty.vendorName ?? 'Unassigned',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Claimed Issue Description Section
                      const Text(
                        'Claimed Issue Description',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          ServiceWarranty.cleanIssueDescription(
                            widget.warranty.issueDescription ?? widget.warranty.notes,
                          ),
                          style: const TextStyle(fontSize: 13, height: 1.4),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Rejection Reason (if rejected)
                      if (widget.warranty.isRejected && widget.warranty.notes != null) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.cancel_outlined, size: 16, color: AppColors.error),
                                  SizedBox(width: 8),
                                  Text(
                                    'Rejection Reason:',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.error,
                                        fontSize: 13),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                widget.warranty.notes!,
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Categorized Photos Section (Evidence, Before, After)
                      photosAsync.when(
                        data: (grouped) => _GroupedPhotoGallerySection(
                          groupedPhotos: grouped,
                          onImageTap: _showImageLightboxGallery,
                        ),
                        loading: () => const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                        error: (err, _) => Text(
                          'Error loading photos: $err',
                          style: const TextStyle(color: AppColors.error, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Action Buttons Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                  Row(
                    children: [
                      if (widget.warranty.isClaimed) ...[
                        OutlinedButton.icon(
                          onPressed: _approving ? null : _rejectClaim,
                          icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.error),
                          label: const Text('Reject Claim', style: TextStyle(color: AppColors.error)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.error),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: _approving ? null : _approveClaim,
                          icon: _approving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.check_circle_rounded, size: 16),
                          label: Text(_approving ? 'Approving...' : 'Approve Claim'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF38A169),
                          ),
                        ),
                      ] else if (widget.warranty.isApproved && !widget.warranty.isResolved) ...[
                        FilledButton.icon(
                          onPressed: _resolving ? null : _markResolved,
                          icon: _resolving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.task_alt_rounded, size: 16),
                          label: const Text('Mark as Resolved'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF3182CE),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getDisplayStatusLabel(ServiceWarranty w) {
    if (w.isResolved) return 'RESOLVED';
    if (w.isRejected) return 'REJECTED';
    if (w.isReworkInProgress) return 'REWORK IN PROGRESS';
    if (w.isReworkAccepted) return 'VENDOR ACCEPTED REWORK';
    if (w.isApproved) return 'APPROVED (PENDING VENDOR)';
    if (w.isClaimed) return 'PENDING REVIEW';
    return w.status.toUpperCase();
  }

  Color _getStatusBgColor(String status) {
    switch (status.toLowerCase()) {
      case 'claimed':
        return const Color(0xFFFFFAF0);
      case 'approved':
        return const Color(0xFFF0FFF4);
      case 'resolved':
        return const Color(0xFFE6FFFA);
      case 'rejected':
        return const Color(0xFFFFF5F5);
      default:
        return Colors.grey.shade100;
    }
  }

  Color _getStatusBorderColor(String status) {
    switch (status.toLowerCase()) {
      case 'claimed':
        return const Color(0xFFFBD38D);
      case 'approved':
        return const Color(0xFF9AE6B4);
      case 'resolved':
        return const Color(0xFF319795);
      case 'rejected':
        return const Color(0xFFFEB2B2);
      default:
        return Colors.grey.shade300;
    }
  }

  Color _getStatusFgColor(String status) {
    switch (status.toLowerCase()) {
      case 'claimed':
        return const Color(0xFFDD6B20);
      case 'approved':
        return const Color(0xFF276749);
      case 'resolved':
        return const Color(0xFF2C7A7B);
      case 'rejected':
        return const Color(0xFFC53030);
      default:
        return AppColors.textSecondary;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'claimed':
        return Icons.pending_actions_rounded;
      case 'approved':
        return Icons.verified_rounded;
      case 'resolved':
        return Icons.check_circle_rounded;
      case 'rejected':
        return Icons.cancel_outlined;
      default:
        return Icons.shield_rounded;
    }
  }
}

// ── Timeline Section ─────────────────────────────────────────────────────────

class _WarrantyTimelineSection extends StatelessWidget {
  final ServiceWarranty warranty;

  const _WarrantyTimelineSection({required this.warranty});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd MMM yyyy, hh:mm a');

    final steps = <_TimelineStepData>[
      _TimelineStepData(
        title: 'Claim Submitted',
        subtitle: warranty.claimedAt != null ? 'Submitted by customer on ${dateFmt.format(warranty.claimedAt!)}' : 'Claim submitted',
        isDone: warranty.claimedAt != null,
        isCurrent: warranty.isClaimed,
      ),
      _TimelineStepData(
        title: 'Admin Review',
        subtitle: warranty.isClaimed ? 'Under Admin Review' : 'Reviewed by Admin',
        isDone: !warranty.isClaimed,
        isCurrent: warranty.isClaimed,
      ),
      _TimelineStepData(
        title: warranty.isRejected ? 'Claim Rejected' : 'Claim Approved',
        subtitle: warranty.isRejected
            ? (warranty.notes != null ? 'Rejected: ${warranty.notes}' : 'Claim rejected by Admin')
            : (warranty.isApproved || warranty.isResolved ? 'Approved by Admin — Rework Booking Issued' : 'Pending Decision'),
        isDone: warranty.isApproved || warranty.isRejected || warranty.isResolved,
        isCurrent: warranty.isApproved && (warranty.reworkStatus == null || warranty.reworkStatus == 'pending'),
        isFailed: warranty.isRejected,
      ),
      _TimelineStepData(
        title: 'Vendor Accepted',
        subtitle: (warranty.reworkVendorName ?? warranty.vendorName) != null
            ? '${warranty.reworkVendorName ?? warranty.vendorName} assigned'
            : (warranty.isReworkAccepted || warranty.isReworkInProgress || warranty.isResolved ? 'Accepted by Vendor' : 'Awaiting Vendor Assignment'),
        isDone: warranty.isReworkAccepted || warranty.isReworkInProgress || warranty.isReworkCompleted || warranty.isResolved,
        isCurrent: warranty.isReworkAccepted,
      ),
      _TimelineStepData(
        title: 'Rework In Progress',
        subtitle: warranty.isReworkInProgress ? 'Vendor is executing rework service' : 'Before photos verified',
        isDone: warranty.isReworkInProgress || warranty.isReworkCompleted || warranty.isResolved,
        isCurrent: warranty.isReworkInProgress,
      ),
      _TimelineStepData(
        title: 'Completion & OTP Verified',
        subtitle: warranty.reworkCompletedAt != null
            ? 'Completed & verified on ${dateFmt.format(warranty.reworkCompletedAt!)}'
            : (warranty.isReworkCompleted || warranty.isResolved ? 'After photos & OTP verified' : 'Awaiting completion OTP'),
        isDone: warranty.isReworkCompleted || warranty.isResolved,
        isCurrent: warranty.reworkStatus == 'awaiting_verification',
      ),
      _TimelineStepData(
        title: 'Warranty Resolved',
        subtitle: warranty.isResolved ? 'Rework complete — Warranty claim resolved' : 'Pending final resolution',
        isDone: warranty.isResolved,
        isCurrent: warranty.isResolved,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.timeline_rounded, size: 18, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                'Warranty Lifecycle Timeline',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...List.generate(steps.length, (i) {
            final step = steps[i];
            final isLast = i == steps.length - 1;
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: step.isFailed
                              ? AppColors.error
                              : (step.isDone
                                  ? const Color(0xFF38A169)
                                  : (step.isCurrent
                                      ? AppColors.primary
                                      : Colors.grey.shade300)),
                        ),
                        child: Icon(
                          step.isFailed
                              ? Icons.close_rounded
                              : (step.isDone ? Icons.check_rounded : Icons.circle_rounded),
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                      if (!isLast)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: step.isDone ? const Color(0xFF38A169) : Colors.grey.shade300,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: step.isFailed
                                  ? AppColors.error
                                  : (step.isDone || step.isCurrent
                                      ? AppColors.textPrimary
                                      : AppColors.textSecondary),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            step.subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: step.isDone || step.isCurrent
                                  ? AppColors.textSecondary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _TimelineStepData {
  final String title;
  final String subtitle;
  final bool isDone;
  final bool isCurrent;
  final bool isFailed;

  const _TimelineStepData({
    required this.title,
    required this.subtitle,
    required this.isDone,
    required this.isCurrent,
    this.isFailed = false,
  });
}

// ── Grouped Photo Gallery Section ───────────────────────────────────────────

class _GroupedPhotoGallerySection extends StatelessWidget {
  final Map<String, List<String>> groupedPhotos;
  final Function(List<String> urls, int initialIndex, String title) onImageTap;

  const _GroupedPhotoGallerySection({
    required this.groupedPhotos,
    required this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    final evidence = groupedPhotos['evidence'] ?? [];
    final before = groupedPhotos['before'] ?? [];
    final after = groupedPhotos['after'] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCategoryGallery('Customer Evidence Photos', evidence, Icons.image_outlined, const Color(0xFFDD6B20)),
        const SizedBox(height: 16),
        _buildCategoryGallery('Vendor Before Photos', before, Icons.camera_alt_outlined, const Color(0xFF3182CE)),
        const SizedBox(height: 16),
        _buildCategoryGallery('Vendor After Photos & Completed Work', after, Icons.task_alt_rounded, const Color(0xFF38A169)),
      ],
    );
  }

  Widget _buildCategoryGallery(String title, List<String> urls, IconData icon, Color themeColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: themeColor),
              const SizedBox(width: 8),
              Text(
                '$title (${urls.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (urls.isEmpty)
            Text(
              'No photos available for this stage yet.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: urls.asMap().entries.map((entry) {
                final index = entry.key;
                final url = entry.value;
                return GestureDetector(
                  onTap: () => onImageTap(urls, index, title),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Tooltip(
                      message: 'Click to view full size',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 110,
                          height: 90,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                url,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Center(
                                  child: Icon(Icons.broken_image_rounded, color: AppColors.textSecondary),
                                ),
                              ),
                              Positioned(
                                right: 4,
                                bottom: 4,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.zoom_in_rounded, size: 12, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

// ── Full-Screen Image Gallery Lightbox Dialog ────────────────────────────────

class _ImageGalleryLightboxDialog extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  final String title;

  const _ImageGalleryLightboxDialog({
    required this.urls,
    required this.initialIndex,
    required this.title,
  });

  @override
  State<_ImageGalleryLightboxDialog> createState() =>
      __ImageGalleryLightboxDialogState();
}

class __ImageGalleryLightboxDialogState
    extends State<_ImageGalleryLightboxDialog> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.urls.length;

    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 780),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Lightbox Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${widget.title} (${_currentIndex + 1}/$total)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Lightbox Main Image PageView
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PageView.builder(
                      controller: _pageController,
                      itemCount: total,
                      onPageChanged: (idx) => setState(() => _currentIndex = idx),
                      itemBuilder: (context, index) {
                        return InteractiveViewer(
                          child: Center(
                            child: Image.network(
                              widget.urls[index],
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.broken_image_rounded, size: 64, color: Colors.white54),
                                  SizedBox(height: 8),
                                  Text(
                                    'Failed to load image',
                                    style: TextStyle(color: Colors.white70, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    // Left Navigation Arrow
                    if (total > 1 && _currentIndex > 0)
                      Positioned(
                        left: 8,
                        child: Material(
                          color: Colors.black54,
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: IconButton(
                            icon: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 28),
                            onPressed: () {
                              _pageController.previousPage(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut,
                              );
                            },
                          ),
                        ),
                      ),

                    // Right Navigation Arrow
                    if (total > 1 && _currentIndex < total - 1)
                      Positioned(
                        right: 8,
                        child: Material(
                          color: Colors.black54,
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: IconButton(
                            icon: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 28),
                            onPressed: () {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut,
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Thumbnail Navigation Bar (when multiple images)
              if (total > 1) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 54,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    shrinkWrap: true,
                    itemCount: total,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final isSelected = index == _currentIndex;
                      return GestureDetector(
                        onTap: () {
                          _pageController.animateToPage(
                            index,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? AppColors.primary : Colors.white24,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              widget.urls[index],
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Info Card Helpers ────────────────────────────────────────────────────────

class _InfoSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _InfoSectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          const Divider(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
