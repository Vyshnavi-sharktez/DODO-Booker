import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../customers/application/providers/customers_providers.dart';
import '../../../customers/domain/models/customer.dart';
import '../../../dodo_teams/application/providers/dodo_teams_providers.dart';
import '../../../vendors/application/providers/vendors_providers.dart';
import '../../application/invoice_service.dart';
import '../../application/providers/bookings_providers.dart';
import '../../domain/models/booking.dart';
import '../../domain/models/booking_addon.dart';
import '../../domain/models/booking_item.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../amc_plans/presentation/widgets/amc_contract_details_dialog.dart';

const _statusConfig = <String, (String, Color, Color)>{
  'pending': ('Pending', Color(0xFFDD6B20), Color(0xFFFEEBC8)),
  'assigned': ('Assigned', Color(0xFF3182CE), Color(0xFFEBF8FF)),
  'assigned_to_dodo_team': (
    'DODO Assigned',
    Color(0xFF6B46C1),
    Color(0xFFF3E8FF),
  ),
  'accepted': ('Accepted', Color(0xFF2C7A7B), Color(0xFFE6FFFA)),
  'on_the_way': ('On The Way', Color(0xFF4A6FA5), Color(0xFFEBF4FF)),
  'arrived': ('Arrived', Color(0xFF6B46C1), Color(0xFFF3E8FF)),
  'in_progress': ('In Progress', Color(0xFF805AD5), Color(0xFFFAF5FF)),
  'completed': ('Completed', Color(0xFF38A169), Color(0xFFF0FFF4)),
  'rejected': ('Rejected', Color(0xFFC05621), Color(0xFFFEEBC8)),
  'cancelled': ('Cancelled', Color(0xFFE53E3E), Color(0xFFFFF5F5)),
};

const _cancellableStatuses = {
  'pending',
  'assigned',
  'assigned_to_dodo_team',
  'accepted',
  'on_the_way',
  'arrived',
  'in_progress',
};

final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
final _dateFmt = DateFormat('dd MMM yyyy');

// ── AMC contract snapshot model (inline, booking details only) ────────────────

class _AmcData {
  final String planName;
  final String status;
  final String? packageDuration;
  final String? serviceInterval;
  final double pricePerVisit;
  final int effectiveTotal;
  final int completedCount;
  final double? originalTotal;
  final String? discountType;
  final double? discountValue;
  final double? discountAmount;
  final double? finalPrice;
  final DateTime createdAt;
  final int quantity;

  const _AmcData({
    required this.planName,
    required this.status,
    this.packageDuration,
    this.serviceInterval,
    required this.pricePerVisit,
    required this.effectiveTotal,
    required this.completedCount,
    this.originalTotal,
    this.discountType,
    this.discountValue,
    this.discountAmount,
    this.finalPrice,
    required this.createdAt,
    this.quantity = 1,
  });

  int get remainingCount => (effectiveTotal - completedCount).clamp(0, 9999);

  DateTime? get endDate {
    final days = switch (packageDuration) {
      'monthly' => 30,
      'quarterly' => 91,
      'half_yearly' => 182,
      'yearly' => 365,
      _ => null,
    };
    return days != null ? createdAt.add(Duration(days: days)) : null;
  }
}


class BookingDetailsDialog extends ConsumerStatefulWidget {
  final Booking booking;
  final VoidCallback? onAssign;
  final VoidCallback? onCancel;

  const BookingDetailsDialog({
    super.key,
    required this.booking,
    this.onAssign,
    this.onCancel,
  });

  @override
  ConsumerState<BookingDetailsDialog> createState() =>
      _BookingDetailsDialogState();
}

class _BookingDetailsDialogState extends ConsumerState<BookingDetailsDialog> {
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes =
      List.generate(6, (_) => FocusNode());
  bool _isVerifying = false;
  bool _isDownloadingInvoice = false;

  @override
  void dispose() {
    for (final c in _otpControllers) c.dispose();
    for (final f in _otpFocusNodes) f.dispose();
    super.dispose();
  }

  Future<void> _verifyOtp(String bookingId) async {
    final otp = _otpControllers.map((c) => c.text).join();
    if (otp.length != 6) return;
    setState(() => _isVerifying = true);
    try {
      await ref
          .read(bookingsNotifierProvider.notifier)
          .completeDodoTeamBooking(bookingId, otp);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking completed successfully')),
      );
    } catch (_) {
      if (!mounted) return;
      for (final c in _otpControllers) c.clear();
      _otpFocusNodes.first.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid OTP')),
      );
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _downloadInvoice({
    required Booking booking,
    required String assigneeName,
    Customer? customer,
  }) async {
    setState(() => _isDownloadingInvoice = true);
    try {
      await InvoiceService.downloadInvoice(
        booking: booking,
        customerName: customer?.fullName ?? '',
        customerPhone:
            customer?.phone.isNotEmpty == true ? customer!.phone : null,
        customerEmail:
            customer?.email.isNotEmpty == true ? customer!.email : null,
        assigneeName: assigneeName.isNotEmpty ? assigneeName : null,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not generate invoice: $e')),
      );
    } finally {
      if (mounted) setState(() => _isDownloadingInvoice = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookings = ref.watch(bookingsNotifierProvider).valueOrNull ?? [];
    final booking = bookings.firstWhere(
      (b) => b.id == widget.booking.id,
      orElse: () => widget.booking,
    );

    final vendors = ref.watch(vendorsNotifierProvider).valueOrNull ?? [];
    final teams = ref.watch(dodoTeamsNotifierProvider).valueOrNull ?? [];
    final customers = ref.watch(customersNotifierProvider).valueOrNull ?? [];
    final imagesAsync = ref.watch(bookingImagesProvider(booking.id));
    final vendor = vendors.where((v) => v.id == booking.vendorId).firstOrNull;
    final team = teams.where((t) => t.id == booking.dodoTeamId).firstOrNull;
    final bookingCustomer =
        customers.where((c) => c.id == booking.customerId).firstOrNull;

    final vendorNameResolved = vendor?.businessName ??
        (booking.vendorName.isNotEmpty
            ? booking.vendorName
            : _truncateId(booking.vendorId));

    final assignedToLabel = switch (booking.assignmentType) {
      'External Vendor' =>
        vendorNameResolved.isNotEmpty ? vendorNameResolved : 'Unassigned',
      'DODO Team' => team?.teamName ?? _truncateId(booking.dodoTeamId),
      _ => 'Unassigned',
    };

    final (statusLabel, statusColor, statusBg) = booking.statusConfig;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ────────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.receipt_long_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Booking #${booking.bookingNumber}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (booking.isWarrantyRework) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFED7D7),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFFEB2B2)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shield_rounded, size: 11, color: Color(0xFF9B2C2C)),
                          SizedBox(width: 3),
                          Text(
                            'WARRANTY REWORK',
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(0xFF9B2C2C),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (booking.isAmc) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEBF8FF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.autorenew_rounded, size: 11, color: Color(0xFF3182CE)),
                          SizedBox(width: 3),
                          Text(
                            'AMC',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF3182CE),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // ── Content ───────────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel('Booking Info'),
                    const SizedBox(height: 12),
                    _InfoRow('Booking Number', booking.bookingNumber),
                    if (booking.isWarrantyRework) ...[
                      _InfoRow('Booking Type', 'Warranty Rework', bold: true),
                      if (booking.originalBookingNumber != null)
                        _InfoRow('Original Booking', '#${booking.originalBookingNumber}'),
                      if (booking.reworkIssueDescription != null)
                        _InfoRow('Reported Issue', booking.reworkIssueDescription!),
                    ],
                    _InfoRow(
                      'Customer ID',
                      _truncateId(booking.customerId),
                      tooltip: booking.customerId,
                    ),
                    _InfoRow('Assignment Type', booking.assignmentType),
                    _InfoRow('Assigned To', assignedToLabel),
                    if (booking.assignmentType == 'External Vendor' &&
                        vendorNameResolved.isNotEmpty &&
                        vendorNameResolved != 'Unassigned')
                      _InfoRow('Accepted By', vendorNameResolved, bold: true),
                    _InfoRow(
                      'Service Date',
                      booking.serviceDate != null
                          ? _dateFmt.format(booking.serviceDate!)
                          : '—',
                    ),
                    _InfoRow('Status', statusLabel),
                    if (booking.address != null && booking.address!.isNotEmpty)
                      _InfoRow('Address', booking.address!),
                    if (booking.notes != null && booking.notes!.isNotEmpty)
                      _InfoRow('Notes', booking.notes!),
                    const SizedBox(height: 20),

                    if (booking.isAmc) ...[
                      const SizedBox(height: 20),
                      _SectionLabel('AMC Contract'),
                      const SizedBox(height: 12),
                      _AmcContractExpandedSection(booking: booking),
                      const SizedBox(height: 4),
                    ],

                    if (booking.items.isNotEmpty) ...[
                      _SectionLabel('Services (${booking.items.length})'),
                      const SizedBox(height: 12),
                      ...booking.items.map(
                        (item) =>
                            _ServiceItemRow(item: item, currency: _currency),
                      ),
                      const SizedBox(height: 20),
                    ],

                    if (booking.addons.isNotEmpty) ...[
                      _SectionLabel('Add-ons (${booking.addons.length})'),
                      const SizedBox(height: 12),
                      ...booking.addons.map(
                        (addon) => _AddonItemRow(
                            addon: addon, currency: _currency),
                      ),
                      const SizedBox(height: 20),
                    ],

                    _SectionLabel('Financials'),
                    const SizedBox(height: 12),
                    _InfoRow('Subtotal', _currency.format(booking.subtotal)),
                    _InfoRow(
                      'Discount',
                      _currency.format(booking.discountAmount),
                    ),
                    const Divider(height: 16),
                    _InfoRow(
                      'Total Amount',
                      _currency.format(booking.totalAmount),
                      bold: true,
                    ),
                    const SizedBox(height: 20),

                    if (booking.isCod) ...[
                      _SectionLabel('COD Reconciliation'),
                      const SizedBox(height: 12),
                      _InfoRow('Payment Method', 'Cash on Delivery (COD)', bold: true),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 140,
                              child: Text(
                                'Collection Status',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            Expanded(
                              child: booking.codConfirmedAt == null
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEEBC8),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'Pending Vendor Confirmation',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFFDD6B20),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    )
                                  : (booking.codCashCollected == true
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF0FFF4),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            border: Border.all(
                                                color: const Color(0xFFC6F6D5)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                  Icons.check_circle_rounded,
                                                  size: 14,
                                                  color: Color(0xFF38A169)),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Cash Collected (${_dateFmt.format(booking.codConfirmedAt!)})',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF2F855A),
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFF5F5),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            border: Border.all(
                                                color: const Color(0xFFFEB2B2)),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                      Icons.cancel_rounded,
                                                      size: 14,
                                                      color: Color(0xFFE53E3E)),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'Cash Not Collected (${_dateFmt.format(booking.codConfirmedAt!)})',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Color(0xFFC53030),
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (booking.codNotCollectedReason !=
                                                      null &&
                                                  booking.codNotCollectedReason!
                                                      .isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Reason: ${booking.codNotCollectedReason}',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Color(0xFF9B2C2C),
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        )),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    _SectionLabel('Timestamps'),
                    const SizedBox(height: 12),
                    _InfoRow(
                      'Created',
                      booking.createdAt != null
                          ? DateFormat(
                              'dd MMM yyyy, hh:mm a',
                            ).format(booking.createdAt!.toLocal())
                          : '—',
                    ),
                    _InfoRow(
                      'Updated',
                      booking.updatedAt != null
                          ? DateFormat(
                              'dd MMM yyyy, hh:mm a',
                            ).format(booking.updatedAt!.toLocal())
                          : '—',
                    ),
                    const SizedBox(height: 20),

                    // ── Service Photos ────────────────────────────────────────
                    if (imagesAsync.valueOrNull?.isNotEmpty ?? false) ...[
                      _SectionLabel('Service Photos'),
                      const SizedBox(height: 12),
                      _AdminPhotosGrid(images: imagesAsync.value!),
                      const SizedBox(height: 20),
                    ],

                    if (booking.assignmentType == 'DODO Team' &&
                        booking.status == 'in_progress') ...[
                      _SectionLabel('Complete Service'),
                      const SizedBox(height: 12),
                      _OtpVerificationCard(
                        controllers: _otpControllers,
                        focusNodes: _otpFocusNodes,
                        isVerifying: _isVerifying,
                        onVerify: () => _verifyOtp(booking.id),
                      ),
                      const SizedBox(height: 20),
                    ],

                    _SectionLabel('Review'),
                    const SizedBox(height: 12),
                    if (booking.review != null) ...[
                      _InfoRow('Rating', '${booking.review!.rating} / 5'),
                      _StarRatingRow(rating: booking.review!.rating),
                      const SizedBox(height: 8),
                      _InfoRow('Review Text', booking.review!.reviewText),
                      _InfoRow(
                        'Submitted',
                        booking.review!.createdAt != null
                            ? DateFormat(
                                'dd MMM yyyy, hh:mm a',
                              ).format(booking.review!.createdAt!.toLocal())
                            : '—',
                      ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          'No review submitted',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Footer ────────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  if (widget.onCancel != null &&
                      _cancellableStatuses.contains(booking.status))
                    OutlinedButton.icon(
                      onPressed: widget.onCancel,
                      icon: const Icon(Icons.cancel_outlined, size: 16),
                      label: const Text('Cancel Booking'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: BorderSide(color: AppColors.error),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  const Spacer(),
                  if (widget.onAssign != null)
                    FilledButton.icon(
                      onPressed: widget.onAssign,
                      icon: Icon(
                        booking.isUnassigned
                            ? Icons.assignment_ind_rounded
                            : Icons.swap_horiz_rounded,
                        size: 16,
                      ),
                      label: Text(booking.isUnassigned ? 'Assign' : 'Reassign'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                  if (widget.onAssign != null) const SizedBox(width: 10),
                  if (booking.status == 'completed') ...[
                    OutlinedButton.icon(
                      onPressed: _isDownloadingInvoice
                          ? null
                          : () => _downloadInvoice(
                                booking: booking,
                                assigneeName: assignedToLabel,
                                customer: bookingCustomer,
                              ),
                      icon: _isDownloadingInvoice
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_rounded, size: 16),
                      label: const Text('Invoice'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
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

String _truncateId(String id) {
  if (id.length <= 8) return id;
  return '${id.substring(0, 8)}…';
}

class _OtpVerificationCard extends StatelessWidget {
  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final bool isVerifying;
  final VoidCallback onVerify;

  const _OtpVerificationCard({
    required this.controllers,
    required this.focusNodes,
    required this.isVerifying,
    required this.onVerify,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3E8FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF6B46C1).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ask the customer for their OTP and enter it below to complete the service.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF553C9A),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              6,
              (i) => _OtpBox(
                controller: controllers[i],
                focusNode: focusNodes[i],
                nextFocus: i < 5 ? focusNodes[i + 1] : null,
                prevFocus: i > 0 ? focusNodes[i - 1] : null,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isVerifying ? null : onVerify,
              icon: isVerifying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.verified_user_rounded, size: 16),
              label: const Text('Verify & Complete Service'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6B46C1),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final FocusNode? nextFocus;
  final FocusNode? prevFocus;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    this.nextFocus,
    this.prevFocus,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 52,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Color(0xFF553C9A),
        ),
        decoration: InputDecoration(
          counterText: '',
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD6BCFA)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD6BCFA)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF6B46C1), width: 2),
          ),
          filled: true,
          fillColor: Colors.white,
        ),
        onChanged: (value) {
          if (value.isNotEmpty && nextFocus != null) {
            nextFocus!.requestFocus();
          } else if (value.isEmpty && prevFocus != null) {
            prevFocus!.requestFocus();
          }
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
        letterSpacing: 1.0,
      ),
    );
  }
}

class _StarRatingRow extends StatelessWidget {
  final int rating;
  const _StarRatingRow({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              'Stars',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(5, (i) {
              return Icon(
                i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 18,
                color: i < rating
                    ? const Color(0xFFD69E2E)
                    : AppColors.textSecondary.withValues(alpha: 0.3),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _ServiceItemRow extends StatelessWidget {
  final BookingItem item;
  final NumberFormat currency;

  const _ServiceItemRow({required this.item, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 130,
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 14,
                  color: Color(0xFF38A169),
                ),
                SizedBox(width: 6),
              ],
            ),
          ),
          Expanded(
            child: Text(
              item.serviceName.isNotEmpty ? item.serviceName : '—',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                currency.format(item.totalPrice),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              if (item.quantity > 1)
                Text(
                  '${item.quantity} × ${currency.format(item.unitPrice)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddonItemRow extends StatelessWidget {
  final BookingAddon addon;
  final NumberFormat currency;

  const _AddonItemRow({required this.addon, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 130,
            child: Row(
              children: [
                Icon(
                  Icons.extension_rounded,
                  size: 14,
                  color: Color(0xFFD4AF37),
                ),
                SizedBox(width: 6),
              ],
            ),
          ),
          Expanded(
            child: Text(
              addon.name.isNotEmpty ? addon.name : '—',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            currency.format(addon.price),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFFD4AF37),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminPhotosGrid extends StatelessWidget {
  final List<Map<String, dynamic>> images;

  const _AdminPhotosGrid({required this.images});

  @override
  Widget build(BuildContext context) {
    final before =
        images.where((i) => i['image_type'] == 'before').toList();
    final after =
        images.where((i) => i['image_type'] == 'after').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (before.isNotEmpty) ...[
          _PhotoRow(label: 'Before', photos: before),
          if (after.isNotEmpty) const SizedBox(height: 12),
        ],
        if (after.isNotEmpty) _PhotoRow(label: 'After', photos: after),
      ],
    );
  }
}

class _PhotoRow extends StatelessWidget {
  final String label;
  final List<Map<String, dynamic>> photos;

  const _PhotoRow({required this.label, required this.photos});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 130),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final url = photos[i]['image_url'] as String;
              return ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  url,
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 80,
                    height: 80,
                    color: AppColors.background,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.textSecondary,
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

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final String? tooltip;

  const _InfoRow(this.label, this.value, {this.bold = false, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final valueWidget = Text(
      value,
      style: TextStyle(
        fontSize: 14,
        color: AppColors.textPrimary,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: tooltip != null
                ? Tooltip(message: tooltip!, child: valueWidget)
                : valueWidget,
          ),
        ],
      ),
    );
  }
}

// ── AMC Contract expanded section ─────────────────────────────────────────────

class _AmcContractExpandedSection extends StatefulWidget {
  final Booking booking;

  const _AmcContractExpandedSection({required this.booking});

  @override
  State<_AmcContractExpandedSection> createState() =>
      _AmcContractExpandedSectionState();
}

class _AmcContractExpandedSectionState
    extends State<_AmcContractExpandedSection> {
  _AmcData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final contractId = widget.booking.amcContractId;
    if (contractId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final client = Supabase.instance.client;
      final raw = await client
          .from('amc_contracts')
          .select(
            'plan_name, status, package_duration, service_interval, '
            'price_per_visit, total_visits, num_visits, '
            'original_total, discount_type, discount_value, discount_amount, final_price, created_at, quantity',
          )
          .eq('id', contractId)
          .maybeSingle();

      if (!mounted) return;
      if (raw == null) {
        setState(() => _loading = false);
        return;
      }

      final visitsRaw = await client
          .from('bookings')
          .select('status')
          .eq('amc_contract_id', contractId);

      if (!mounted) return;

      final completedCount = (visitsRaw as List)
          .where((v) => (v as Map)['status'] == 'completed')
          .length;
      final numVisits = (raw['num_visits'] as num?)?.toInt();
      final totalVisits = (raw['total_visits'] as num?)?.toInt() ?? 0;

      setState(() {
        _data = _AmcData(
          planName: raw['plan_name'] as String? ?? '',
          status: raw['status'] as String? ?? 'active',
          packageDuration: raw['package_duration'] as String?,
          serviceInterval: raw['service_interval'] as String?,
          pricePerVisit: (raw['price_per_visit'] as num?)?.toDouble() ?? 0.0,
          effectiveTotal: numVisits ?? totalVisits,
          completedCount: completedCount,
          originalTotal: (raw['original_total'] as num?)?.toDouble(),
          discountType: raw['discount_type'] as String?,
          discountValue: (raw['discount_value'] as num?)?.toDouble(),
          discountAmount: (raw['discount_amount'] as num?)?.toDouble(),
          finalPrice: (raw['final_price'] as num?)?.toDouble(),
          createdAt: DateTime.parse(raw['created_at'] as String),
          quantity: (raw['quantity'] as num?)?.toInt() ?? 1,
        );
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contractId = widget.booking.amcContractId;
    final booking = widget.booking;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEBF8FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: const Color(0xFF3182CE).withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.autorenew_rounded,
                      size: 14, color: Color(0xFF3182CE)),
                  SizedBox(width: 6),
                  Text(
                    'Annual Maintenance Contract',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF3182CE),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_data != null)
                _dataRows(_data!, booking)
              else
                _basicRows(booking),
            ],
          ),
        ),
        if (contractId != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => AmcContractDetailsDialog(
                  contractId: contractId,
                  planName: booking.amcPlanName ?? 'AMC Contract',
                ),
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              label: const Text('View AMC Contract'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF3182CE),
                side: const BorderSide(color: Color(0xFF3182CE)),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _basicRows(Booking booking) => Column(
        children: [
          if (booking.amcPlanName != null && booking.amcPlanName!.isNotEmpty)
            _InfoRow('Plan', booking.amcPlanName!),
          if (booking.amcRecurrenceInterval != null &&
              booking.amcRecurrenceInterval!.isNotEmpty)
            _InfoRow('Recurrence', booking.amcRecurrenceInterval!),
          if (booking.amcContractId != null)
            _InfoRow(
              'Contract ID',
              _truncateId(booking.amcContractId!),
              tooltip: booking.amcContractId,
            ),
        ],
      );

  Widget _dataRows(_AmcData data, Booking booking) {
    final fmt = DateFormat('dd MMM yyyy');
    final contractId = booking.amcContractId;
    return Column(
      children: [
        _InfoRow(
          'Plan',
          data.planName.isNotEmpty
              ? data.planName
              : (booking.amcPlanName ?? '—'),
        ),
        _InfoRow('Status', _statusLabel(data.status)),
        if (data.packageDuration != null)
          _InfoRow('Package Duration', _durationLabel(data.packageDuration!)),
        if (data.serviceInterval != null)
          _InfoRow('Service Interval', _intervalLabel(data.serviceInterval!)),
        _InfoRow(
            'Price Per Visit', '₹${data.pricePerVisit.toStringAsFixed(2)}'),
        _InfoRow('Total Visits', '${data.effectiveTotal}'),
        _InfoRow('Completed Visits', '${data.completedCount}'),
        _InfoRow('Remaining Visits', '${data.remainingCount}'),
        if (data.quantity > 1)
          _InfoRow('Units Covered', '${data.quantity} units'),
        if (data.originalTotal != null && data.originalTotal! > 0)
          _InfoRow(
              'Original Total', '₹${data.originalTotal!.toStringAsFixed(2)}'),
        if (data.discountAmount != null && data.discountAmount! > 0)
          _InfoRow(
            'Discount',
            data.discountType == 'percentage' && data.discountValue != null
                ? '${data.discountValue!.toStringAsFixed(0)}% (−₹${data.discountAmount!.toStringAsFixed(2)})'
                : '−₹${data.discountAmount!.toStringAsFixed(2)}',
          ),
        if (data.finalPrice != null && data.finalPrice! > 0)
          _InfoRow(
            'Final AMC Price',
            '₹${data.finalPrice!.toStringAsFixed(2)}',
            bold: true,
          ),
        _InfoRow('Start Date', fmt.format(data.createdAt.toLocal())),
        if (data.endDate != null)
          _InfoRow('End Date', fmt.format(data.endDate!.toLocal())),
        if (contractId != null)
          _InfoRow(
            'Contract ID',
            _truncateId(contractId),
            tooltip: contractId,
          ),
      ],
    );
  }

  static String _statusLabel(String s) => switch (s) {
        'active' => 'Active',
        'paused' => 'Paused',
        'completed' => 'Completed',
        'cancelled' => 'Cancelled',
        _ => s,
      };

  static String _durationLabel(String d) => switch (d) {
        'monthly' => 'Monthly',
        'quarterly' => 'Quarterly',
        'half_yearly' => 'Half-Yearly',
        'yearly' => 'Yearly',
        _ => d,
      };

  static String _intervalLabel(String i) => switch (i) {
        'weekly' => 'Weekly',
        'bi_weekly' => 'Bi-Weekly',
        'monthly' => 'Monthly',
        _ => i,
      };
}
