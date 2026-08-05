import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/my_booking_model.dart';
import '../models/service_warranty_model.dart';
import '../services/warranty_providers.dart';
import '../widgets/claim_warranty_modal.dart';

class WarrantyDetailsScreen extends ConsumerWidget {
  final MyBookingModel booking;
  final ServiceWarrantyModel warranty;

  const WarrantyDetailsScreen({
    super.key,
    required this.booking,
    required this.warranty,
  });

  Color _getStatusColor(String effStatus) {
    switch (effStatus.toLowerCase()) {
      case 'active':
        return const Color(0xFF38A169);
      case 'under review':
        return const Color(0xFF805AD5);
      case 'approved':
      case 'vendor accepted':
        return const Color(0xFF3182CE);
      case 'in progress':
        return const Color(0xFFD69E2E);
      case 'rework completed':
      case 'resolved':
        return const Color(0xFF2B6CB0);
      case 'rejected':
        return const Color(0xFFE53E3E);
      case 'expired':
      default:
        return const Color(0xFF718096);
    }
  }

  IconData _getStatusIcon(String effStatus) {
    switch (effStatus.toLowerCase()) {
      case 'active':
        return Icons.verified_user_rounded;
      case 'under review':
        return Icons.rate_review_rounded;
      case 'approved':
      case 'vendor accepted':
        return Icons.assignment_turned_in_rounded;
      case 'in progress':
        return Icons.engineering_rounded;
      case 'rework completed':
      case 'resolved':
        return Icons.task_alt_rounded;
      case 'rejected':
        return Icons.cancel_rounded;
      case 'expired':
      default:
        return Icons.history_rounded;
    }
  }

  void _openLightbox(BuildContext context, String title, List<String> photos, int initialIndex) {
    if (photos.isEmpty) return;
    showDialog(
      context: context,
      builder: (_) => _ImageGalleryLightboxDialog(
        title: title,
        imageUrls: photos,
        initialIndex: initialIndex,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat('dd MMMM yyyy');
    final timeFmt = DateFormat('hh:mm a');

    final statusColor = _getStatusColor(warranty.effectiveStatus);
    final statusIcon = _getStatusIcon(warranty.effectiveStatus);

    final assignedVendor = warranty.reworkVendorName ?? warranty.vendorName ?? booking.vendorName ?? 'DODO Authorized Vendor';
    final reworkPhotosAsync = warranty.reworkBookingId != null
        ? ref.watch(reworkImagesGroupedProvider(warranty.reworkBookingId!))
        : const AsyncValue.data(<String, List<String>>{});

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Warranty & Claim Details'),
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Status Banner Card ───────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    statusColor,
                    statusColor.withValues(alpha: 0.85),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: statusColor.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(statusIcon, size: 36, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'DODO Service Warranty',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'STATUS: ${warranty.effectiveStatus.toUpperCase()}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white30, height: 1),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _BannerMetric(
                        label: 'WARRANTY DURATION',
                        value: '${warranty.warrantyDays} Days',
                      ),
                      Container(height: 30, width: 1, color: Colors.white30),
                      _BannerMetric(
                        label: 'REMAINING DAYS',
                        value: warranty.isActive ? '${warranty.remainingDays} Days' : '0 Days',
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Rejection Reason Card (If Rejected) ─────────────────────────
            if (warranty.isRejected) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Claim Rejected by Admin',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.error,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      warranty.notes != null && warranty.notes!.trim().isNotEmpty
                          ? warranty.notes!
                          : 'Your warranty claim was reviewed and could not be approved based on the provided evidence.',
                      style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ── Final Resolution Summary Card (If Resolved) ─────────────────
            if (warranty.isResolved) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF38A169).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF38A169).withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.verified_rounded, color: Color(0xFF38A169), size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Warranty Claim Resolved',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF276749),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      warranty.reworkCompletedAt != null
                          ? 'Rework service completed and verified via OTP on ${dateFmt.format(warranty.reworkCompletedAt!)}.'
                          : 'Rework service completed successfully. Warranty issue resolved.',
                      style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ── Lifecycle Stepper Section ─────────────────────────────────────
            _CustomerWarrantyLifecycleStepper(warranty: warranty),

            const SizedBox(height: 24),

            // ── Assigned Vendor & Rework Info Card ───────────────────────────
            if (warranty.isApproved || warranty.isReworkAccepted || warranty.isReworkInProgress || warranty.isResolved) ...[
              Text(
                'Assigned Service Technician / Vendor',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _DetailRow(
                      icon: Icons.store_rounded,
                      label: 'Technician / Vendor',
                      value: assignedVendor,
                      valueColor: AppColors.primary,
                    ),
                    if (warranty.reworkBookingNumber != null) ...[
                      const Divider(height: 24),
                      _DetailRow(
                        icon: Icons.confirmation_number_outlined,
                        label: 'Rework Booking Ref.',
                        value: '#${warranty.reworkBookingNumber}',
                        valueColor: const Color(0xFF38A169),
                      ),
                    ],
                    const Divider(height: 24),
                    _DetailRow(
                      icon: Icons.info_outline_rounded,
                      label: 'Rework Status',
                      value: (warranty.reworkStatus ?? 'Assigned').toUpperCase().replaceAll('_', ' '),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // ── Issue & Photo Galleries Section ──────────────────────────────
            if (warranty.claimedAt != null || warranty.issueDescription != null) ...[
              Text(
                'Claim Issue & Evidence Photos',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Customer Reported Issue:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      ServiceWarrantyModel.cleanIssueDescription(warranty.issueDescription ?? warranty.notes),
                      style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.textPrimary),
                    ),

                    const SizedBox(height: 16),

                    // Categorized Photos
                    reworkPhotosAsync.when(
                      data: (photosMap) {
                        final evidence = photosMap['evidence'] ?? [];
                        final before = photosMap['before'] ?? [];
                        final after = photosMap['after'] ?? [];

                        if (evidence.isEmpty && before.isEmpty && after.isEmpty) {
                          return const SizedBox.shrink();
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Divider(height: 24),
                            if (evidence.isNotEmpty) ...[
                              _PhotoSubGallery(
                                title: 'Claim Evidence Photos (${evidence.length})',
                                photoUrls: evidence,
                                onPhotoTap: (idx) => _openLightbox(context, 'Evidence Photos', evidence, idx),
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (before.isNotEmpty) ...[
                              _PhotoSubGallery(
                                title: 'Technician Before Photos (${before.length})',
                                photoUrls: before,
                                onPhotoTap: (idx) => _openLightbox(context, 'Before Photos', before, idx),
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (after.isNotEmpty) ...[
                              _PhotoSubGallery(
                                title: 'Technician After Photos (${after.length})',
                                photoUrls: after,
                                onPhotoTap: (idx) => _openLightbox(context, 'After Photos', after, idx),
                              ),
                            ],
                          ],
                        );
                      },
                      loading: () => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // ── Certificate & Warranty Info Card ──────────────────────────────
            Text(
              'Certificate Information',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  _DetailRow(
                    icon: Icons.confirmation_number_outlined,
                    label: 'Certificate No.',
                    value: warranty.certificateNumber,
                    valueColor: AppColors.primary,
                  ),
                  const Divider(height: 24),
                  _DetailRow(
                    icon: Icons.calendar_today_rounded,
                    label: 'Issued Date',
                    value: dateFmt.format(warranty.issuedAt),
                  ),
                  const Divider(height: 24),
                  _DetailRow(
                    icon: Icons.event_available_rounded,
                    label: 'Valid Until',
                    value: dateFmt.format(warranty.expiresAt),
                  ),
                  if (warranty.claimedAt != null) ...[
                    const Divider(height: 24),
                    _DetailRow(
                      icon: Icons.check_circle_outline_rounded,
                      label: 'Claimed Date',
                      value: '${dateFmt.format(warranty.claimedAt!)} at ${timeFmt.format(warranty.claimedAt!)}',
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Linked Booking Info Card ─────────────────────────────────────
            Text(
              'Original Service Booking',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '#${booking.displayBookingNumber}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        dateFmt.format(booking.scheduledDate),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    booking.serviceName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.store_rounded, size: 15, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        'Fulfilled by: ',
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                      ),
                      Expanded(
                        child: Text(
                          assignedVendor,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Amount Paid',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        '₹${booking.totalAmount.toStringAsFixed(2)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Coverage Terms & Exclusions Bullet Cards ───────────────────────
            Text(
              'Warranty Terms & Coverage',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.verified_rounded, size: 18, color: Color(0xFF38A169)),
                      const SizedBox(width: 8),
                      Text(
                        'Warranty Covers:',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF276749),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const _BulletPoint(
                    icon: Icons.check_circle_outline_rounded,
                    iconColor: Color(0xFF38A169),
                    text: 'Workmanship and labor quality for the service performed.',
                  ),
                  const _BulletPoint(
                    icon: Icons.check_circle_outline_rounded,
                    iconColor: Color(0xFF38A169),
                    text: 'Spare parts and replacement components supplied during the service.',
                  ),
                  const _BulletPoint(
                    icon: Icons.check_circle_outline_rounded,
                    iconColor: Color(0xFF38A169),
                    text: 'Operational defects directly arising from the completed job within the warranty period.',
                  ),

                  const Divider(height: 28),

                  Row(
                    children: [
                      const Icon(Icons.do_not_disturb_on_rounded, size: 18, color: Color(0xFFE53E3E)),
                      const SizedBox(width: 8),
                      Text(
                        'Warranty Does Not Cover:',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF9B2C2C),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const _BulletPoint(
                    icon: Icons.highlight_off_rounded,
                    iconColor: Color(0xFFE53E3E),
                    text: 'Physical, liquid, or accidental damage occurring post-service completion.',
                  ),
                  const _BulletPoint(
                    icon: Icons.highlight_off_rounded,
                    iconColor: Color(0xFFE53E3E),
                    text: 'Misuse, unauthorized third-party tampering, or electrical voltage surges.',
                  ),
                  const _BulletPoint(
                    icon: Icons.highlight_off_rounded,
                    iconColor: Color(0xFFE53E3E),
                    text: 'Normal wear and tear or pre-existing defects not included in the original job scope.',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Claim Warranty CTA (With Duplicate Prevention) ────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: warranty.canClaim
                          ? () async {
                              final reworkId = await showModalBottomSheet<String>(
                                context: context,
                                isScrollControlled: true,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                                ),
                                builder: (_) => ClaimWarrantyModal(
                                  booking: booking,
                                  warranty: warranty,
                                ),
                              );

                              if (reworkId != null && context.mounted) {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    title: const Row(
                                      children: [
                                        Icon(Icons.check_circle_rounded, color: Color(0xFF38A169), size: 24),
                                        SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            'Claim Submitted',
                                            style: TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                    content: Text(
                                      'Warranty claim submitted successfully. We\'ll assign a technician shortly.\n\n'
                                      'Rework Booking Reference:\n#$reworkId',
                                    ),
                                    actions: [
                                      FilledButton(
                                        onPressed: () => Navigator.of(ctx).pop(),
                                        style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                                        child: const Text('OK'),
                                      ),
                                    ],
                                  ),
                                );
                              }
                            }
                          : null,
                      icon: Icon(
                        warranty.canClaim
                            ? Icons.shield_outlined
                            : (warranty.isResolved
                                ? Icons.verified_rounded
                                : (warranty.isRejected ? Icons.cancel_outlined : Icons.lock_clock_outlined)),
                        size: 18,
                      ),
                      label: Text(
                        warranty.canClaim
                            ? 'Claim Warranty'
                            : (warranty.isResolved
                                ? 'Warranty Claim Resolved'
                                : (warranty.isClaimed
                                    ? 'Claim Under Review'
                                    : (warranty.isReworkInProgress
                                        ? 'Rework In Progress'
                                        : (warranty.isApproved || warranty.isReworkAccepted
                                            ? 'Claim Approved — Awaiting Rework'
                                            : (warranty.isRejected
                                                ? 'Claim Rejected'
                                                : 'Warranty Expired'))))),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: statusColor,
                        disabledBackgroundColor: AppColors.border,
                        disabledForegroundColor: AppColors.textSecondary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  if (warranty.isActive && warranty.canClaim) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Coverage is active until ${dateFmt.format(warranty.expiresAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _CustomerWarrantyLifecycleStepper extends StatelessWidget {
  final ServiceWarrantyModel warranty;

  const _CustomerWarrantyLifecycleStepper({required this.warranty});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd MMM yyyy, hh:mm a');

    final vendorDisplayName = warranty.reworkVendorName ?? warranty.vendorName;

    final steps = <_TimelineStepData>[
      _TimelineStepData(
        title: 'Claim Submitted',
        subtitle: warranty.claimedAt != null ? 'Submitted on ${dateFmt.format(warranty.claimedAt!)}' : 'Awaiting claim submission',
        isDone: warranty.claimedAt != null,
        isCurrent: warranty.isClaimed,
      ),
      _TimelineStepData(
        title: 'Admin Review',
        subtitle: warranty.isClaimed ? 'Under Admin Review' : 'Reviewed by Admin',
        isDone: !warranty.isClaimed && (warranty.isApproved || warranty.isRejected || warranty.isResolved),
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
        subtitle: vendorDisplayName != null
            ? '$vendorDisplayName assigned'
            : (warranty.isReworkAccepted || warranty.isReworkInProgress || warranty.isResolved ? 'Accepted by Vendor' : 'Awaiting Vendor Assignment'),
        isDone: warranty.isReworkAccepted || warranty.isReworkInProgress || warranty.isReworkCompleted || warranty.isResolved,
        isCurrent: warranty.isReworkAccepted,
      ),
      _TimelineStepData(
        title: 'Rework In Progress',
        subtitle: warranty.isReworkInProgress ? 'Technician is executing rework service' : 'Before photos verified',
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
        color: Colors.white,
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
                'Claim Progress Tracker',
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
                              fontSize: 11,
                              color: step.isFailed
                                  ? AppColors.error.withValues(alpha: 0.8)
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

  _TimelineStepData({
    required this.title,
    required this.subtitle,
    required this.isDone,
    required this.isCurrent,
    this.isFailed = false,
  });
}

class _PhotoSubGallery extends StatelessWidget {
  final String title;
  final List<String> photoUrls;
  final Function(int) onPhotoTap;

  const _PhotoSubGallery({
    required this.title,
    required this.photoUrls,
    required this.onPhotoTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photoUrls.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, idx) {
              final url = photoUrls[idx];
              return InkWell(
                onTap: () => onPhotoTap(idx),
                borderRadius: BorderRadius.circular(8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 80,
                    height: 80,
                    color: Colors.grey.shade200,
                    child: Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image_rounded, color: Colors.grey, size: 24),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ImageGalleryLightboxDialog extends StatefulWidget {
  final String title;
  final List<String> imageUrls;
  final int initialIndex;

  const _ImageGalleryLightboxDialog({
    required this.title,
    required this.imageUrls,
    required this.initialIndex,
  });

  @override
  State<_ImageGalleryLightboxDialog> createState() => _ImageGalleryLightboxDialogState();
}

class _ImageGalleryLightboxDialogState extends State<_ImageGalleryLightboxDialog> {
  late PageController _pageController;
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
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.85,
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            // Top Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.black87,
              child: Row(
                children: [
                  const Icon(Icons.photo_library_rounded, color: Colors.white70, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    widget.title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const Spacer(),
                  Text(
                    '${_currentIndex + 1} / ${widget.imageUrls.length}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // PageView
            Expanded(
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _pageController,
                    itemCount: widget.imageUrls.length,
                    onPageChanged: (idx) {
                      setState(() {
                        _currentIndex = idx;
                      });
                    },
                    itemBuilder: (context, idx) {
                      return InteractiveViewer(
                        panEnabled: true,
                        minScale: 0.8,
                        maxScale: 4.0,
                        child: Center(
                          child: Image.network(
                            widget.imageUrls[idx],
                            fit: BoxFit.contain,
                            loadingBuilder: (_, child, progress) {
                              if (progress == null) return child;
                              return const Center(child: CircularProgressIndicator(color: Colors.white));
                            },
                            errorBuilder: (_, __, ___) => const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.broken_image_rounded, color: Colors.white54, size: 48),
                                SizedBox(height: 8),
                                Text('Failed to load image', style: TextStyle(color: Colors.white54)),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  if (_currentIndex > 0)
                    Positioned(
                      left: 12,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: CircleAvatar(
                          backgroundColor: Colors.black54,
                          child: IconButton(
                            icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
                            onPressed: () {
                              _pageController.previousPage(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  if (_currentIndex < widget.imageUrls.length - 1)
                    Positioned(
                      right: 12,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: CircleAvatar(
                          backgroundColor: Colors.black54,
                          child: IconButton(
                            icon: const Icon(Icons.chevron_right_rounded, color: Colors.white),
                            onPressed: () {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Bottom Thumbnail Bar
            if (widget.imageUrls.length > 1)
              Container(
                height: 70,
                color: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: widget.imageUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, idx) {
                    final isSelected = idx == _currentIndex;
                    return InkWell(
                      onTap: () {
                        _pageController.animateToPage(
                          idx,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isSelected ? AppColors.primary : Colors.transparent,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.network(
                            widget.imageUrls[idx],
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BannerMetric extends StatelessWidget {
  final String label;
  final String value;

  const _BannerMetric({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _BulletPoint extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;

  const _BulletPoint({
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textPrimary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
