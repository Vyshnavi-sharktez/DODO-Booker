import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../amc_plans/presentation/widgets/amc_contract_details_dialog.dart';
import '../../../customers/application/providers/customers_providers.dart';
import '../../../customers/domain/models/customer.dart';
import '../../../dodo_teams/application/providers/dodo_teams_providers.dart';
import '../../../vendors/application/providers/vendors_providers.dart';
import '../../application/invoice_service.dart';
import '../../application/providers/bookings_providers.dart';
import '../../domain/models/booking.dart';
import '../../domain/models/booking_addon.dart';
import '../../domain/models/booking_item.dart';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'booking_assignment_dialog.dart';
import '../../../../core/services/nominatim_service.dart';

const _navyPrimary = Color(0xFF1D4ED8);
const _navyDark = Color(0xFF0F172A);
const _cardBg = Colors.white;
const _borderColor = Color(0xFFE2E8F0);
const _textSecondary = Color(0xFF64748B);

final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
final _dateFmt = DateFormat('dd MMM yyyy');
final _dateTimeFmt = DateFormat('dd MMM yyyy, hh:mm a');

// ── AMC Data helper model ───────────────────────────────────────────────────

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

  const BookingDetailsDialog({
    super.key,
    required this.booking,
    this.onAssign,
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
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
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
      for (final c in _otpControllers) {
        c.clear();
      }
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

void _triggerAssign(Booking booking) {
    if (widget.onAssign != null) {
      Navigator.of(context).pop();
      widget.onAssign!();
    } else {
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

    final placedAtText = booking.createdAt != null
        ? _dateTimeFmt.format(booking.createdAt!.toLocal())
        : (booking.serviceDate != null
            ? _dateFmt.format(booking.serviceDate!)
            : '—');

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 900),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header Bar ────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(bottom: BorderSide(color: _borderColor)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: const Icon(
                      Icons.calendar_month_rounded,
                      color: _navyPrimary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            RichText(
                              text: TextSpan(
                                children: [
                                  const TextSpan(
                                    text: 'Booking # ',
                                    style: TextStyle(
                                      color: _navyDark,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  TextSpan(
                                    text: booking.bookingNumber,
                                    style: const TextStyle(
                                      color: _navyPrimary,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            _BadgePill(
                              label: statusLabel,
                              textColor: statusColor,
                              bgColor: statusBg,
                            ),
                            if (booking.isWarrantyRework) ...[
                              const SizedBox(width: 8),
                              const _BadgePill(
                                label: 'WARRANTY REWORK',
                                textColor: Color(0xFF9B2C2C),
                                bgColor: Color(0xFFFED7D7),
                                icon: Icons.shield_rounded,
                              ),
                            ],
                            if (booking.isAmc) ...[
                              const SizedBox(width: 8),
                              const _BadgePill(
                                label: 'AMC',
                                textColor: Color(0xFF3182CE),
                                bgColor: Color(0xFFEBF8FF),
                                icon: Icons.autorenew_rounded,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Placed on $placedAtText',
                          style: const TextStyle(
                            color: _textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: _textSecondary,
                      size: 22,
                    ),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),

            // ── Scrollable Body Layout ─────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 720;
                    if (isWide) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Left Column
                              Expanded(
                                flex: 11,
                                child: Column(
                                  children: [
                                    _CustomerCard(
                                      customer: bookingCustomer,
                                      customerId: booking.customerId,
                                      onViewProfile: () {
                                        Navigator.of(context).pop();
                                        context.push(
                                            '/dashboard/customers/${booking.customerId}');
                                      },
                                    ),
                                    const SizedBox(height: 16),
                                    _ServicesCard(booking: booking),
                                    const SizedBox(height: 16),
                                    _AssignedToCard(
                                      booking: booking,
                                      vendorNameResolved: vendorNameResolved,
                                      teamName: team?.teamName,
                                      onAssign: () => _triggerAssign(booking),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),

                              // Right Column
                              Expanded(
                                flex: 10,
                                child: Column(
                                  children: [
                                    _BookingInfoCard(
                                      booking: booking,
                                      statusLabel: statusLabel,
                                      statusColor: statusColor,
                                      statusBg: statusBg,
                                      placedAtText: placedAtText,
                                    ),
                                    const SizedBox(height: 16),
                                    _ServiceAddressCard(
                                      address: booking.address,
                                      isCancelled: booking.status == 'cancelled',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          // ── Extended Sections (AMC, Reconciliation, OTP, Photos, Review) ──
                          if (booking.isAmc) ...[
                            const SizedBox(height: 16),
                            _AmcContractExpandedSection(booking: booking),
                          ],

                          if (booking.isCod) ...[
                            const SizedBox(height: 16),
                            _CodReconciliationCard(booking: booking),
                          ],

                          if (!booking.isCod &&
                              booking.paymentStatus == 'failed') ...[
                            const SizedBox(height: 16),
                            _PaymentReconciliationSection(booking: booking),
                          ],

                          if (!booking.isCod &&
                              booking.paymentStatus == 'success' &&
                              (booking.status == 'cancelled' ||
                                  booking.status ==
                                      'cancelled_by_customer')) ...[
                            const SizedBox(height: 16),
                            _CancelledPaymentRefundSection(booking: booking),
                          ],

                          if (imagesAsync.valueOrNull?.isNotEmpty ?? false) ...[
                            const SizedBox(height: 16),
                            _ServicePhotosCard(images: imagesAsync.value!),
                          ],

                          if (booking.assignmentType == 'DODO Team' &&
                              booking.status == 'in_progress') ...[
                            const SizedBox(height: 16),
                            _OtpVerificationCard(
                              controllers: _otpControllers,
                              focusNodes: _otpFocusNodes,
                              isVerifying: _isVerifying,
                              onVerify: () => _verifyOtp(booking.id),
                            ),
                          ],

                          if (booking.review != null) ...[
                            const SizedBox(height: 16),
                            _ReviewCard(review: booking.review!),
                          ],
                        ],
                      );
                    } else {
                      // Mobile / Narrow Stack Layout
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _CustomerCard(
                            customer: bookingCustomer,
                            customerId: booking.customerId,
                            onViewProfile: () {
                              Navigator.of(context).pop();
                              context.push(
                                  '/dashboard/customers/${booking.customerId}');
                            },
                          ),
                          const SizedBox(height: 16),
                          _BookingInfoCard(
                            booking: booking,
                            statusLabel: statusLabel,
                            statusColor: statusColor,
                            statusBg: statusBg,
                            placedAtText: placedAtText,
                          ),
                          const SizedBox(height: 16),
                          _ServicesCard(booking: booking),
                          const SizedBox(height: 16),
                          _ServiceAddressCard(
                            address: booking.address,
                            isCancelled: booking.status == 'cancelled',
                          ),
                          const SizedBox(height: 16),
                          _AssignedToCard(
                            booking: booking,
                            vendorNameResolved: vendorNameResolved,
                            teamName: team?.teamName,
                            onAssign: () => _triggerAssign(booking),
                          ),
                          if (booking.isAmc) ...[
                            const SizedBox(height: 16),
                            _AmcContractExpandedSection(booking: booking),
                          ],
                          if (booking.isCod) ...[
                            const SizedBox(height: 16),
                            _CodReconciliationCard(booking: booking),
                          ],
                          if (!booking.isCod &&
                              booking.paymentStatus == 'failed') ...[
                            const SizedBox(height: 16),
                            _PaymentReconciliationSection(booking: booking),
                          ],
                          if (!booking.isCod &&
                              booking.paymentStatus == 'success' &&
                              (booking.status == 'cancelled' ||
                                  booking.status ==
                                      'cancelled_by_customer')) ...[
                            const SizedBox(height: 16),
                            _CancelledPaymentRefundSection(booking: booking),
                          ],
                          if (imagesAsync.valueOrNull?.isNotEmpty ?? false) ...[
                            const SizedBox(height: 16),
                            _ServicePhotosCard(images: imagesAsync.value!),
                          ],
                          if (booking.assignmentType == 'DODO Team' &&
                              booking.status == 'in_progress') ...[
                            const SizedBox(height: 16),
                            _OtpVerificationCard(
                              controllers: _otpControllers,
                              focusNodes: _otpFocusNodes,
                              isVerifying: _isVerifying,
                              onVerify: () => _verifyOtp(booking.id),
                            ),
                          ],
                          if (booking.review != null) ...[
                            const SizedBox(height: 16),
                            _ReviewCard(review: booking.review!),
                          ],
                        ],
                      );
                    }
                  },
                ),
              ),
            ),

            // ── Footer Bar ────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(16)),
                border: Border(top: BorderSide(color: _borderColor)),
              ),
              child: Row(
                children: [
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_rounded, size: 16),
                      label: const Text('Download Invoice'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _navyDark,
                        side: const BorderSide(color: _borderColor),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _textSecondary,
                      side: const BorderSide(color: _borderColor),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
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

// ── Shared Card Container Widget ─────────────────────────────────────────────

class _CardContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const _CardContainer({
    required this.child,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;

  const _SectionHeader({
    required this.icon,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: _navyDark),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _navyDark,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _BadgePill extends StatelessWidget {
  final String label;
  final Color textColor;
  final Color bgColor;
  final IconData? icon;

  const _BadgePill({
    required this.label,
    required this.textColor,
    required this.bgColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: textColor),
            const SizedBox(width: 4),
          ] else ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: textColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Left Column Cards ─────────────────────────────────────────────────────────

class _CustomerCard extends StatelessWidget {
  final Customer? customer;
  final String customerId;
  final VoidCallback onViewProfile;

  const _CustomerCard({
    required this.customer,
    required this.customerId,
    required this.onViewProfile,
  });

  @override
  Widget build(BuildContext context) {
    final name = customer?.fullName.isNotEmpty == true
        ? customer!.fullName
        : 'Customer';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'C';

    final truncatedId = customerId.length > 24
        ? '${customerId.substring(0, 24)}...'
        : customerId;

    return _CardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.person_outline_rounded,
            title: 'Customer Information',
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFDBEAFE),
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _navyPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _navyDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.phone_outlined,
                            size: 14, color: _textSecondary),
                        const SizedBox(width: 6),
                        Text(
                          customer?.phone.isNotEmpty == true
                              ? customer!.phone
                              : '—',
                          style: const TextStyle(
                            fontSize: 13,
                            color: _navyDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.email_outlined,
                            size: 14, color: _textSecondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            customer?.email.isNotEmpty == true
                                ? customer!.email
                                : '—',
                            style: const TextStyle(
                              fontSize: 13,
                              color: _navyDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.person_outline_rounded,
                            size: 14, color: _textSecondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Customer ID: $truncatedId',
                            style: const TextStyle(
                              fontSize: 13,
                              color: _navyDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: customerId));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Copied Customer ID to clipboard'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(4),
                          child: const Padding(
                            padding: EdgeInsets.all(4.0),
                            child: Icon(
                              Icons.copy_rounded,
                              size: 14,
                              color: _textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ServicesCard extends StatelessWidget {
  final Booking booking;

  const _ServicesCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final totalServicesCount = booking.items.length + booking.addons.length;

    return _CardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.layers_outlined,
            title: 'Services ($totalServicesCount)',
            trailing: Text(
              'Total: ${_currency.format(booking.totalAmount)}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _navyDark,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Main Service Items
          ...booking.items.map((item) => _ServiceRow(item: item)),

          // Add-on Items
          ...booking.addons.map((addon) => _AddonRow(addon: addon)),

          const SizedBox(height: 16),

          // Price Details Card Container
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.description_outlined,
                        size: 16, color: _navyPrimary),
                    SizedBox(width: 6),
                    Text(
                      'Price Details',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _navyDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _PriceRow(
                  label: 'Subtotal',
                  value: _currency.format(booking.subtotal),
                ),
                if (booking.discountAmount > 0) ...[
                  const SizedBox(height: 6),
                  _PriceRow(
                    label: booking.couponCode != null
                        ? 'Discount (${booking.couponCode!})'
                        : 'Discount',
                    value: '-${_currency.format(booking.discountAmount)}',
                    isDiscount: true,
                  ),
                ],
                if (booking.taxAmount > 0) ...[
                  const SizedBox(height: 6),
                  _PriceRow(
                    label: _taxLabel(booking),
                    value: _currency.format(booking.taxAmount),
                  ),
                ],
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1, color: _borderColor),
                ),
                _PriceRow(
                  label: 'Total Amount',
                  value: _currency.format(booking.totalAmount),
                  isTotal: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  final BookingItem item;

  const _ServiceRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final catPath = item.serviceId.isEmpty
        ? (item.categoryName.isNotEmpty ? item.categoryName : 'Custom Item')
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.displayName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _navyDark,
                  ),
                ),
                if (catPath.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    catPath,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.assignment_outlined,
                        size: 13, color: _textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      'Qty: ${item.quantity}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: _textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _currency.format(item.totalPrice),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _navyDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddonRow extends StatelessWidget {
  final BookingAddon addon;

  const _AddonRow({required this.addon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${addon.name} (Add-on)',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _navyDark,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Home Cleaning > Add-on',
                  style: TextStyle(
                    fontSize: 12,
                    color: _textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                const Row(
                  children: [
                    Icon(Icons.assignment_outlined,
                        size: 13, color: _textSecondary),
                    SizedBox(width: 4),
                    Text(
                      'Qty: 1',
                      style: TextStyle(
                        fontSize: 12,
                        color: _textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _currency.format(addon.price),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _navyDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isTotal;
  final bool isDiscount;

  const _PriceRow({
    required this.label,
    required this.value,
    this.isTotal = false,
    this.isDiscount = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 14 : 13,
              fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
              color: isTotal ? _navyDark : _textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isTotal ? 15 : 13,
            fontWeight: isTotal ? FontWeight.w700 : FontWeight.w600,
            color: isTotal
                ? _navyDark
                : (isDiscount ? AppColors.error : _navyDark),
          ),
        ),
      ],
    );
  }
}

class _AssignedToCard extends StatelessWidget {
  final Booking booking;
  final String vendorNameResolved;
  final String? teamName;
  final VoidCallback onAssign;

  const _AssignedToCard({
    required this.booking,
    required this.vendorNameResolved,
    required this.teamName,
    required this.onAssign,
  });

  @override
  Widget build(BuildContext context) {
    final isUnassigned = booking.isUnassigned;
    final isCancelled = booking.status == 'cancelled';

    final (badgeLabel, badgeColor, badgeBg) = switch (booking.assignmentType) {
      'External Vendor' => (
          'Assigned',
          const Color(0xFF2563EB),
          const Color(0xFFDBEAFE)
        ),
      'DODO Team' => (
          'Assigned',
          const Color(0xFF6B46C1),
          const Color(0xFFF3E8FF)
        ),
      _ => isCancelled
          ? ('Cancelled', const Color(0xFFDC2626), const Color(0xFFFEE2E2))
          : ('Unassigned', const Color(0xFFD97706), const Color(0xFFFEF3C7)),
    };

    final assignedToLabel = switch (booking.assignmentType) {
      'External Vendor' =>
        vendorNameResolved.isNotEmpty ? vendorNameResolved : 'Unassigned',
      'DODO Team' => teamName ?? _truncateId(booking.dodoTeamId),
      _ => isCancelled ? 'Cancelled' : 'Unassigned',
    };

    return _CardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.people_outline_rounded,
            title: 'Assigned To',
            trailing: _BadgePill(
              label: badgeLabel,
              textColor: badgeColor,
              bgColor: badgeBg,
            ),
          ),
          const SizedBox(height: 16),
          if (isUnassigned)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _borderColor),
              ),
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isCancelled ? const Color(0xFFFEE2E2) : const Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isCancelled ? Icons.cancel_outlined : Icons.person_outline_rounded,
                      color: isCancelled ? const Color(0xFFDC2626) : _textSecondary,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isCancelled ? 'Booking is cancelled. No vendor assigned.' : 'No vendor assigned yet',
                    style: TextStyle(
                      fontSize: 13,
                      color: isCancelled ? const Color(0xFFDC2626) : _textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (!isCancelled) ...[
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: onAssign,
                      child: const Text(
                        'Assign a vendor to this booking',
                        style: TextStyle(
                          fontSize: 13,
                          color: _navyPrimary,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: onAssign,
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Assign Vendor'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _navyDark,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _borderColor),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: badgeBg,
                    child: Icon(
                      booking.assignmentType == 'DODO Team'
                          ? Icons.groups_rounded
                          : Icons.person_rounded,
                      color: badgeColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          assignedToLabel,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _navyDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          booking.assignmentType,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isCancelled)
                    OutlinedButton.icon(
                      onPressed: onAssign,
                      icon: const Icon(Icons.swap_horiz_rounded, size: 14),
                      label: const Text('Reassign'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _navyPrimary,
                        side: const BorderSide(color: _navyPrimary),
                        visualDensity: VisualDensity.compact,
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

// ── Right Column Cards ────────────────────────────────────────────────────────

class _BookingInfoCard extends StatelessWidget {
  final Booking booking;
  final String statusLabel;
  final Color statusColor;
  final Color statusBg;
  final String placedAtText;

  const _BookingInfoCard({
    required this.booking,
    required this.statusLabel,
    required this.statusColor,
    required this.statusBg,
    required this.placedAtText,
  });

  @override
  Widget build(BuildContext context) {
    final serviceDateText = booking.serviceDate != null
        ? _dateFmt.format(booking.serviceDate!)
        : '—';

    final timeSlotText = booking.scheduledTime != null &&
            booking.scheduledTime!.trim().isNotEmpty
        ? booking.scheduledTime!
        : '10:00 AM - 12:00 PM';

    final isCancelled = booking.status == 'cancelled';

    final (pmtStatusLabel, pmtColor, pmtBg) = switch (booking.paymentStatus) {
      'success' => ('Paid', const Color(0xFF166534), const Color(0xFFDCFCE7)),
      'failed' => (
          'Payment Failed',
          const Color(0xFFDC2626),
          const Color(0xFFFEE2E2)
        ),
      'pending' => isCancelled
          ? ('Cancelled', const Color(0xFFDC2626), const Color(0xFFFEE2E2))
          : ('Pending', const Color(0xFFD97706), const Color(0xFFFEF3C7)),
      _ => isCancelled
          ? ('Cancelled', const Color(0xFFDC2626), const Color(0xFFFEE2E2))
          : ('Not Paid', const Color(0xFFDC2626), const Color(0xFFFEE2E2)),
    };

    final (asgLabel, asgColor, asgBg) = switch (booking.assignmentType) {
      'External Vendor' => (
          'External Vendor',
          const Color(0xFF2563EB),
          const Color(0xFFDBEAFE)
        ),
      'DODO Team' => (
          'DODO Team',
          const Color(0xFF6B46C1),
          const Color(0xFFF3E8FF)
        ),
      _ => isCancelled
          ? ('Cancelled', const Color(0xFFDC2626), const Color(0xFFFEE2E2))
          : ('Unassigned', const Color(0xFFD97706), const Color(0xFFFEF3C7)),
    };

    return _CardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.article_outlined,
            title: 'Booking Information',
          ),
          const SizedBox(height: 16),
          _InfoKeyValRow(
            icon: Icons.calendar_today_outlined,
            label: 'Booking Number',
            valueWidget: Text(
              booking.bookingNumber,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _navyPrimary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _InfoKeyValRow(
            icon: Icons.event_note_outlined,
            label: 'Order Date',
            value: placedAtText,
          ),
          const SizedBox(height: 12),
          _InfoKeyValRow(
            icon: Icons.calendar_month_outlined,
            label: 'Service Date',
            value: serviceDateText,
          ),
          const SizedBox(height: 12),
          _InfoKeyValRow(
            icon: Icons.access_time_rounded,
            label: 'Time Slot',
            value: timeSlotText,
          ),
          const SizedBox(height: 12),
          _InfoKeyValRow(
            icon: Icons.payment_rounded,
            label: 'Payment Method',
            value: booking.paymentMethodLabel,
          ),
          const SizedBox(height: 12),
          _InfoKeyValRow(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Payment Status',
            valueWidget: _BadgePill(
              label: pmtStatusLabel,
              textColor: pmtColor,
              bgColor: pmtBg,
            ),
          ),
          const SizedBox(height: 12),
          _InfoKeyValRow(
            icon: Icons.assignment_ind_outlined,
            label: 'Assignment Type',
            valueWidget: _BadgePill(
              label: asgLabel,
              textColor: asgColor,
              bgColor: asgBg,
            ),
          ),
          const SizedBox(height: 12),
          _InfoKeyValRow(
            icon: Icons.info_outline_rounded,
            label: 'Status',
            valueWidget: _BadgePill(
              label: statusLabel,
              textColor: statusColor,
              bgColor: statusBg,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoKeyValRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final Widget? valueWidget;

  const _InfoKeyValRow({
    required this.icon,
    required this.label,
    this.value,
    this.valueWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _textSecondary),
        const SizedBox(width: 8),
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: _textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: valueWidget ??
              Text(
                value ?? '—',
                style: const TextStyle(
                  fontSize: 14,
                  color: _navyDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
        ),
      ],
    );
  }
}

class _ServiceAddressCard extends StatelessWidget {
  final String? address;
  final bool isCancelled;

  const _ServiceAddressCard({
    required this.address,
    this.isCancelled = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasAddress = address != null && address!.trim().isNotEmpty;

    return _CardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.location_on_outlined,
            title: 'Service Address',
          ),
          const SizedBox(height: 16),
          Text(
            hasAddress ? address! : 'No service address provided.',
            style: const TextStyle(
              fontSize: 14,
              color: _navyDark,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Change Address Dialog ───────────────────────────────────────────────────

// ── Change Address Dialog ───────────────────────────────────────────────────

class _AddressChangeDialog extends StatefulWidget {
  final Booking booking;
  final Future<void> Function(String newAddress, double? lat, double? lng) onSave;

  const _AddressChangeDialog({
    required this.booking,
    required this.onSave,
  });

  @override
  State<_AddressChangeDialog> createState() => _AddressChangeDialogState();
}

class _AddressChangeDialogState extends State<_AddressChangeDialog> {
  final _formKey = GlobalKey<FormState>();

  final _line1Ctrl = TextEditingController();
  final _landmarkCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _pincodeCtrl = TextEditingController();

  double? _latitude;
  double? _longitude;

  bool _saving = false;
  bool _isLocating = false;
  String? _error;

  bool get _hasCoordinates => _latitude != null && _longitude != null;

  @override
  void initState() {
    super.initState();
    _latitude = widget.booking.latitude;
    _longitude = widget.booking.longitude;

    final full = widget.booking.address ?? '';
    if (full.isNotEmpty) {
      _parseAddress(full);
    }
  }

  void _parseAddress(String raw) {
    final parts = raw.split(', ');
    if (parts.length >= 3) {
      final last = parts.last.replaceAll(RegExp(r'[^\d]'), '');
      if (last.length == 6) {
        _pincodeCtrl.text = last;
        _stateCtrl.text = parts[parts.length - 2];
        _cityCtrl.text = parts[parts.length - 3];
        final remaining = parts.sublist(0, parts.length - 3);

        final landmarkIdx = remaining.indexWhere((p) =>
            p.toLowerCase().startsWith('landmark:') ||
            p.toLowerCase().startsWith('near '));
        if (landmarkIdx != -1) {
          _landmarkCtrl.text = remaining[landmarkIdx]
              .replaceAll(RegExp(r'^landmark:\s*', caseSensitive: false), '');
          final line1Parts = [...remaining]..removeAt(landmarkIdx);
          _line1Ctrl.text = line1Parts.join(', ');
        } else {
          _line1Ctrl.text = remaining.join(', ');
        }
        return;
      }
    }
    _line1Ctrl.text = raw;
  }

  @override
  void dispose() {
    _line1Ctrl.dispose();
    _landmarkCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _pincodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickOnMap() async {
    final result = await showDialog<_MapPickerModalResult>(
      context: context,
      useRootNavigator: false,
      builder: (_) => _MapPickerModal(
        initialLatitude: _latitude,
        initialLongitude: _longitude,
      ),
    );
    if (result == null || !mounted) return;

    setState(() {
      _latitude = result.latitude;
      _longitude = result.longitude;
    });

    if (result.address != null) {
      final addr = result.address!;
      setState(() {
        if (addr.line1?.isNotEmpty ?? false) _line1Ctrl.text = addr.line1!;
        if (addr.city?.isNotEmpty ?? false) _cityCtrl.text = addr.city!;
        if (addr.state?.isNotEmpty ?? false) _stateCtrl.text = addr.state!;
        if (addr.pincode?.isNotEmpty ?? false) _pincodeCtrl.text = addr.pincode!;
      });
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final line1 = _line1Ctrl.text.trim();
    final landmark = _landmarkCtrl.text.trim();
    final city = _cityCtrl.text.trim();
    final state = _stateCtrl.text.trim();
    final pincode = _pincodeCtrl.text.trim();

    final parts = <String>[
      if (line1.isNotEmpty) line1,
      if (landmark.isNotEmpty) landmark,
      if (city.isNotEmpty) city,
      if (state.isNotEmpty) state,
      if (pincode.isNotEmpty) pincode,
    ];
    final formattedAddress = parts.join(', ');

    try {
      await widget.onSave(formattedAddress, _latitude, _longitude);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to update address: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ─────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Add Address',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded,
                          size: 20, color: Color(0xFF64748B)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // ── Location Button ────────────────────────────────
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickOnMap,
                  icon: _isLocating
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.map_outlined, size: 18),
                  label: const Text(
                    'Pick on Map',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    foregroundColor: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),

                if (_hasCoordinates) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle_outline_rounded,
                          size: 14, color: Color(0xFF2E7D32)),
                      const SizedBox(width: 4),
                      Text(
                        'Location pinned (${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)})',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF2E7D32),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 16),

                // ── Divider ────────────────────────────────────────
                const Row(
                  children: [
                    Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'or fill manually',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                  ],
                ),

                const SizedBox(height: 16),

                // ── House / Flat No., Street & Area ──────────────
                const Text(
                  'House / Flat No., Street & Area',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _line1Ctrl,
                  decoration: _inputDecoration(
                      'e.g. 204, Sunrise Apartments, MG Road'),
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'Required' : null,
                ),

                const SizedBox(height: 14),

                // ── Landmark ───────────────────────────────────────
                const Text(
                  'Landmark (Optional)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _landmarkCtrl,
                  decoration: _inputDecoration('e.g. Near City Mall'),
                ),

                const SizedBox(height: 14),

                // ── City & State Row ───────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'City',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF475569),
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _cityCtrl,
                            decoration: _inputDecoration('e.g. Bengaluru'),
                            textCapitalization: TextCapitalization.words,
                            validator: (v) =>
                                (v?.trim().isEmpty ?? true) ? 'Required' : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'State',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF475569),
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _stateCtrl,
                            decoration: _inputDecoration('e.g. Karnataka'),
                            textCapitalization: TextCapitalization.words,
                            validator: (v) =>
                                (v?.trim().isEmpty ?? true) ? 'Required' : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // ── Pincode ────────────────────────────────────────
                const Text(
                  'Pincode',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _pincodeCtrl,
                  decoration: _inputDecoration('e.g. 560001'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (v.trim().length != 6) return '6 digits required';
                    return null;
                  },
                ),

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(fontSize: 13, color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ],

                const SizedBox(height: 24),

                // ── Save Address Button ───────────────────────────
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: _navyPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save Address',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF0F172A), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        isDense: true,
      );
}

// ── Floating Map Picker Modal ──────────────────────────────────────────────

class _MapPickerModalResult {
  final double latitude;
  final double longitude;
  final NominatimAddress? address;

  const _MapPickerModalResult({
    required this.latitude,
    required this.longitude,
    this.address,
  });
}

class _MapPickerModal extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;

  const _MapPickerModal({
    this.initialLatitude,
    this.initialLongitude,
  });

  @override
  State<_MapPickerModal> createState() => _MapPickerModalState();
}

class _MapPickerModalState extends State<_MapPickerModal> {
  static const _fallback = LatLng(17.3850, 78.4867);
  static const _streetZoom = 14.0;

  late final MapController _mapController;
  late final TextEditingController _searchCtrl;
  late LatLng _selectedLatLng;
  double _currentZoom = _streetZoom;
  bool _isConfirming = false;

  List<NominatimSearchResult> _searchResults = [];
  bool _searching = false;
  bool _showResults = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _searchCtrl = TextEditingController();
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selectedLatLng =
          LatLng(widget.initialLatitude!, widget.initialLongitude!);
      _currentZoom = 15;
    } else {
      _selectedLatLng = _fallback;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _showResults = false;
      });
      return;
    }
    _debounce =
        Timer(const Duration(milliseconds: 500), () => _doSearch(value));
  }

  Future<void> _doSearch(String query) async {
    if (!mounted) return;
    setState(() {
      _searching = true;
      _showResults = true;
    });
    try {
      final results =
          await NominatimService().search(query, countrycodes: 'in');
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searchResults = [];
        _searching = false;
      });
    }
  }

  void _selectSearchResult(NominatimSearchResult result) {
    final newCenter = LatLng(result.lat, result.lon);
    setState(() {
      _selectedLatLng = newCenter;
      _showResults = false;
      _searchResults = [];
      _searchCtrl.text = result.displayName;
    });
    try {
      _mapController.move(newCenter, 15);
    } catch (_) {}
  }

  Future<void> _confirm() async {
    setState(() => _isConfirming = true);
    try {
      final addr = await NominatimService().reverseGeocode(
        _selectedLatLng.latitude,
        _selectedLatLng.longitude,
      );
      if (!mounted) return;
      Navigator.of(context).pop(_MapPickerModalResult(
        latitude: _selectedLatLng.latitude,
        longitude: _selectedLatLng.longitude,
        address: addr,
      ));
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop(_MapPickerModalResult(
        latitude: _selectedLatLng.latitude,
        longitude: _selectedLatLng.longitude,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              color: _navyPrimary,
              child: Row(
                children: [
                  const Icon(Icons.map_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  const Text(
                    'Pick Location on Map',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            // Map body
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _selectedLatLng,
                      initialZoom: _currentZoom,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all,
                      ),
                      onPositionChanged: (camera, _) {
                        setState(() {
                          _selectedLatLng = camera.center;
                          _currentZoom = camera.zoom;
                        });
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.dodo.admin_panel',
                      ),
                    ],
                  ),

                  // Center Pin Indicator
                  IgnorePointer(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_pin,
                            size: 44,
                            color: _navyPrimary,
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),

                  // Search Bar Overlay
                  Positioned(
                    top: 12,
                    left: 16,
                    right: 16,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(35),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: TextFormField(
                            controller: _searchCtrl,
                            onChanged: _onSearchChanged,
                            decoration: InputDecoration(
                              hintText: 'Search location (e.g. MG Road, Bengaluru)',
                              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                              prefixIcon: const Icon(Icons.search_rounded, size: 20),
                              suffixIcon: _searching
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    )
                                  : _searchCtrl.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear_rounded, size: 18),
                                          onPressed: () {
                                            _searchCtrl.clear();
                                            setState(() {
                                              _searchResults = [];
                                              _showResults = false;
                                            });
                                          },
                                        )
                                      : null,
                              border: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              isDense: true,
                            ),
                          ),
                        ),
                        if (_showResults)
                          Container(
                            margin: const EdgeInsets.only(top: 6),
                            constraints: const BoxConstraints(maxHeight: 180),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: _searchResults.isEmpty && !_searching
                                    ? [
                                        const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: Text(
                                            'No results found.',
                                            style: TextStyle(
                                                fontSize: 13, color: Color(0xFF64748B)),
                                          ),
                                        ),
                                      ]
                                    : _searchResults.map((r) {
                                        return InkWell(
                                          onTap: () => _selectSearchResult(r),
                                          borderRadius: BorderRadius.circular(12),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 14, vertical: 10),
                                            child: Row(
                                              children: [
                                                Icon(Icons.place_rounded,
                                                    size: 16, color: _navyPrimary),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    r.displayName,
                                                    style: const TextStyle(
                                                        fontSize: 13, color: Color(0xFF1E293B)),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Bottom Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_selectedLatLng.latitude.toStringAsFixed(5)}, ${_selectedLatLng.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed:
                        _isConfirming ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      foregroundColor: const Color(0xFF475569),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _isConfirming ? null : _confirm,
                    style: FilledButton.styleFrom(
                      backgroundColor: _navyPrimary,
                    ),
                    child: _isConfirming
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Select Location'),
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

// ── Extended Cards (AMC, Photos, Review, OTP, COD, Reconciliation) ───────────

class _CodReconciliationCard extends StatelessWidget {
  final Booking booking;

  const _CodReconciliationCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final isCancelled = booking.status == 'cancelled';

    return _CardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.monetization_on_outlined,
            title: 'COD Reconciliation',
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                width: 140,
                child: Text(
                  'Collection Status',
                  style: TextStyle(
                    fontSize: 13,
                    color: _textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: isCancelled && booking.codCashCollected != true
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFFCA5A5)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cancel_rounded,
                                size: 14, color: Color(0xFFDC2626)),
                            SizedBox(width: 4),
                            Text(
                              'Cancelled',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFDC2626),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      )
                    : (booking.codConfirmedAt == null
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Pending Vendor Confirmation',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFD97706),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        : (booking.codCashCollected == true
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: const Color(0xFF86EFAC)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.check_circle_rounded,
                                        size: 14, color: Color(0xFF166534)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Cash Collected (${_dateFmt.format(booking.codConfirmedAt!)})',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF166534),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: const Color(0xFFFCA5A5)),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.cancel_rounded,
                                            size: 14,
                                            color: Color(0xFFDC2626)),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Cash Not Collected (${_dateFmt.format(booking.codConfirmedAt!)})',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFFDC2626),
                                            fontWeight: FontWeight.bold,
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
                                          color: Color(0xFF991B1B),
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ))),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Cancelled booking with successful online payment — admin refund action ────

class _CancelledPaymentRefundSection extends ConsumerStatefulWidget {
  final Booking booking;
  const _CancelledPaymentRefundSection({required this.booking});

  @override
  ConsumerState<_CancelledPaymentRefundSection> createState() =>
      _CancelledPaymentRefundSectionState();
}

class _CancelledPaymentRefundSectionState
    extends ConsumerState<_CancelledPaymentRefundSection> {
  bool _loading = false;
  String? _error;
  String? _successMsg;

  Future<void> _initiateRefund(
    String refundRequestId,
    double amount,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Initiate Razorpay Refund'),
        content: Text(
          'This will initiate a refund of ${_currency.format(amount)} '
          'to the customer\'s original payment method via Razorpay.\n\n'
          'This action cannot be undone. Proceed?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1D4ED8)),
            child: const Text('Initiate Refund',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _loading = true;
      _error = null;
      _successMsg = null;
    });

    try {
      final client = Supabase.instance.client;

      // Step 1: create a pending refund_transaction for this request.
      final txnId = await client.rpc(
        'admin_initiate_refund_transaction',
        params: {
          'p_request_id': refundRequestId,
          'p_amount': amount,
          'p_gateway': 'razorpay',
          'p_refund_method': 'original_payment_method',
        },
      ) as String;

      // Step 2: call process-razorpay-refund edge function with transaction_id.
      final result = await client.functions.invoke(
        'process-razorpay-refund',
        body: {'transaction_id': txnId},
      );

      final data = result.data as Map?;
      if (data?['pending'] == true) {
        setState(() {
          _successMsg =
              'Refund queued — Razorpay will process it within 5–7 business days.';
        });
      } else if (data?['success'] == true) {
        setState(() {
          _successMsg = 'Refund processed immediately.';
        });
      } else {
        setState(() {
          _error = data?['error'] as String? ?? 'Unexpected response from gateway.';
        });
      }
      ref.invalidate(bookingPaymentAuditProvider(widget.booking.id));
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  @override
  Widget build(BuildContext context) {
    final auditAsync =
        ref.watch(bookingPaymentAuditProvider(widget.booking.id));

    return _CardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.currency_rupee_rounded,
            title: 'Refund — Cancelled Online Payment',
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFED7AA)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 16, color: Color(0xFFD97706)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This booking was cancelled but the online payment was '
                    'successfully captured. A Razorpay refund must be initiated '
                    'to return the money to the customer.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          auditAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
            error: (_, __) => const Text('Could not load refund details.',
                style: TextStyle(
                    fontSize: 12,
                    color: _textSecondary,
                    fontStyle: FontStyle.italic)),
            data: (audit) {
              final requestId = audit.refundRequestId;
              final eligible = audit.refundEligibleAmount ??
                  widget.booking.totalAmount;
              final txnStatus = audit.refundTransactionStatus;
              final refundStatus = audit.refundStatus;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoKeyValRow(
                    icon: Icons.attach_money_rounded,
                    label: 'Eligible Refund',
                    value: _currency.format(eligible),
                  ),
                  const SizedBox(height: 8),
                  _InfoKeyValRow(
                    icon: Icons.receipt_long_rounded,
                    label: 'Refund Ticket',
                    value: refundStatus != null
                        ? _capitalize(refundStatus.replaceAll('_', ' '))
                        : 'Not created yet',
                  ),
                  if (txnStatus != null) ...[
                    const SizedBox(height: 8),
                    _InfoKeyValRow(
                      icon: Icons.sync_rounded,
                      label: 'Transaction Status',
                      value: _capitalize(txnStatus.replaceAll('_', ' ')),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Text(_error!,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF991B1B))),
                    ),
                  ],
                  if (_successMsg != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF86EFAC)),
                      ),
                      child: Text(_successMsg!,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF166534))),
                    ),
                  ],
                  // Show refund button only when ticket exists + no active transaction.
                  if (requestId != null &&
                      (txnStatus == null || txnStatus == 'failed') &&
                      _successMsg == null) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _loading
                            ? null
                            : () => _initiateRefund(requestId, eligible),
                        icon: _loading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.currency_rupee_rounded,
                                size: 16),
                        label: Text(_loading
                            ? 'Initiating...'
                            : 'Initiate Razorpay Refund'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1D4ED8),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                  // No ticket yet — inform admin that trigger may not have fired.
                  if (requestId == null && _successMsg == null) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'No refund ticket found. The auto-creation trigger may '
                      'still be processing. Refresh in a moment or create a '
                      'manual ticket via the Refund Queries module.',
                      style: TextStyle(
                          fontSize: 12,
                          color: _textSecondary,
                          fontStyle: FontStyle.italic),
                    ),
                  ],
                  // In-flight or completed — show informational state only.
                  if (txnStatus == 'processing' || txnStatus == 'completed') ...[
                    const SizedBox(height: 10),
                    Text(
                      txnStatus == 'completed'
                          ? 'Refund has been completed.'
                          : 'Refund is being processed by Razorpay. '
                              'This may take 5–7 business days.',
                      style: TextStyle(
                        fontSize: 12,
                        color: txnStatus == 'completed'
                            ? const Color(0xFF166534)
                            : _textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _PaymentReconciliationSection extends ConsumerWidget {
  final Booking booking;

  const _PaymentReconciliationSection({required this.booking});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auditAsync = ref.watch(bookingPaymentAuditProvider(booking.id));

    return _CardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.warning_amber_rounded,
            title: 'Payment Reconciliation',
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: Color(0xFFDC2626),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This booking\'s payment was marked failed. '
                    'If the customer reports a debit, verify gateway IDs below '
                    'before initiating a refund to avoid duplicate processing.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF991B1B),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          auditAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (_, __) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Could not load gateway payment details.',
                style: TextStyle(
                  fontSize: 12,
                  color: _textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            data: (audit) {
              if (audit.attempts.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'No payment attempt records found.',
                    style: TextStyle(
                      fontSize: 12,
                      color: _textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                );
              }
              final attempt = audit.attempts.first;
              final orderId = attempt['gateway_order_id'] as String?;
              final paymentId = attempt['gateway_payment_id'] as String?;
              final amount = (attempt['amount'] as num?)?.toDouble();
              final gwStatus = attempt['status'] as String?;
              final failureReason = attempt['failure_reason'] as String?;
              final attemptNum = attempt['attempt_number'] as int?;
              final refundStatus = audit.refundStatus;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 16),
                  _InfoKeyValRow(
                    icon: Icons.credit_card_rounded,
                    label: 'Gateway',
                    value: ((attempt['gateway'] as String?) ?? 'razorpay')
                        .toUpperCase(),
                  ),
                  const SizedBox(height: 8),
                  _InfoKeyValRow(
                    icon: Icons.tag_rounded,
                    label: 'Order ID',
                    value: orderId ?? '—',
                  ),
                  const SizedBox(height: 8),
                  _InfoKeyValRow(
                    icon: Icons.confirmation_number_outlined,
                    label: 'Payment ID',
                    value: paymentId ?? '—',
                  ),
                  if (amount != null) ...[
                    const SizedBox(height: 8),
                    _InfoKeyValRow(
                      icon: Icons.attach_money_rounded,
                      label: 'Amount',
                      value: _currency.format(amount),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _InfoKeyValRow(
                    icon: Icons.info_outline_rounded,
                    label: 'Gateway Status',
                    value: _capitalize(gwStatus ?? '—'),
                  ),
                  if (failureReason != null && failureReason.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _InfoKeyValRow(
                      icon: Icons.error_outline_rounded,
                      label: 'Failure Reason',
                      value: failureReason,
                    ),
                  ],
                  if (attemptNum != null) ...[
                    const SizedBox(height: 8),
                    _InfoKeyValRow(
                      icon: Icons.numbers_rounded,
                      label: 'Attempt #',
                      value: '$attemptNum',
                    ),
                  ],
                  const Divider(height: 16),
                  _InfoKeyValRow(
                    icon: Icons.replay_rounded,
                    label: 'Refund Status',
                    value: refundStatus != null
                        ? _capitalize(refundStatus.replaceAll('_', ' '))
                        : 'No refund ticket',
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

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

    return _CardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.autorenew_rounded,
            title: 'Annual Maintenance Contract',
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_data != null)
            _dataRows(_data!, booking)
          else
            _basicRows(booking),
          if (contractId != null) ...[
            const SizedBox(height: 12),
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
                label: const Text('View AMC Contract Details'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _navyPrimary,
                  side: const BorderSide(color: _navyPrimary),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _basicRows(Booking booking) => Column(
        children: [
          if (booking.amcPlanName != null && booking.amcPlanName!.isNotEmpty)
            _InfoKeyValRow(
                icon: Icons.workspace_premium_rounded,
                label: 'Plan',
                value: booking.amcPlanName!),
          if (booking.amcRecurrenceInterval != null &&
              booking.amcRecurrenceInterval!.isNotEmpty)
            _InfoKeyValRow(
                icon: Icons.repeat_rounded,
                label: 'Recurrence',
                value: booking.amcRecurrenceInterval!),
          if (booking.amcContractId != null)
            _InfoKeyValRow(
                icon: Icons.tag_rounded,
                label: 'Contract ID',
                value: _truncateId(booking.amcContractId!)),
        ],
      );

  Widget _dataRows(_AmcData data, Booking booking) {
    return Column(
      children: [
        _InfoKeyValRow(
          icon: Icons.workspace_premium_rounded,
          label: 'Plan',
          value: data.planName.isNotEmpty
              ? data.planName
              : (booking.amcPlanName ?? '—'),
        ),
        const SizedBox(height: 8),
        _InfoKeyValRow(
          icon: Icons.info_outline_rounded,
          label: 'Status',
          value: _statusLabel(data.status),
        ),
        if (data.packageDuration != null) ...[
          const SizedBox(height: 8),
          _InfoKeyValRow(
            icon: Icons.timer_outlined,
            label: 'Package Duration',
            value: _durationLabel(data.packageDuration!),
          ),
        ],
        if (data.serviceInterval != null) ...[
          const SizedBox(height: 8),
          _InfoKeyValRow(
            icon: Icons.repeat_rounded,
            label: 'Service Interval',
            value: _intervalLabel(data.serviceInterval!),
          ),
        ],
        const SizedBox(height: 8),
        _InfoKeyValRow(
          icon: Icons.payments_outlined,
          label: 'Price Per Visit',
          value: _currency.format(data.pricePerVisit),
        ),
        const SizedBox(height: 8),
        _InfoKeyValRow(
          icon: Icons.numbers_rounded,
          label: 'Total Visits',
          value: '${data.effectiveTotal}',
        ),
        const SizedBox(height: 8),
        _InfoKeyValRow(
          icon: Icons.check_circle_outline_rounded,
          label: 'Completed Visits',
          value: '${data.completedCount}',
        ),
        const SizedBox(height: 8),
        _InfoKeyValRow(
          icon: Icons.hourglass_empty_rounded,
          label: 'Remaining Visits',
          value: '${data.remainingCount}',
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

class _ServicePhotosCard extends StatelessWidget {
  final List<Map<String, dynamic>> images;

  const _ServicePhotosCard({required this.images});

  @override
  Widget build(BuildContext context) {
    final before = images.where((i) => i['image_type'] == 'before').toList();
    final after = images.where((i) => i['image_type'] == 'after').toList();

    return _CardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.photo_library_outlined,
            title: 'Service Photos',
          ),
          const SizedBox(height: 14),
          if (before.isNotEmpty) ...[
            _PhotoRow(label: 'Before Service', photos: before),
            if (after.isNotEmpty) const SizedBox(height: 12),
          ],
          if (after.isNotEmpty)
            _PhotoRow(label: 'After Service', photos: after),
        ],
      ),
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
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: _textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final url = photos[i]['image_url'] as String;
              final isVideo = photos[i]['media_type'] == 'video';
              if (isVideo) {
                return Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8EAF6),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFC5CAE9)),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.videocam_rounded,
                          color: Color(0xFF5C6BC0), size: 26),
                      SizedBox(height: 2),
                      Text(
                        'Video',
                        style: TextStyle(
                          color: Color(0xFF5C6BC0),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  url,
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 80,
                    height: 80,
                    color: const Color(0xFFF1F5F9),
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: _textSecondary,
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
    return _CardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.verified_user_outlined,
            title: 'Complete Service OTP',
          ),
          const SizedBox(height: 12),
          const Text(
            'Ask the customer for their OTP and enter it below to complete the service.',
            style: TextStyle(fontSize: 13, color: _textSecondary),
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
          color: Color(0xFF6B46C1),
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

class _ReviewCard extends StatelessWidget {
  final BookingReview review;

  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    return _CardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.star_outline_rounded,
            title: 'Customer Review',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Row(
                children: List.generate(5, (i) {
                  return Icon(
                    i < review.rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 20,
                    color: i < review.rating
                        ? const Color(0xFFEAB308)
                        : const Color(0xFFCBD5E1),
                  );
                }),
              ),
              const SizedBox(width: 8),
              Text(
                '${review.rating} / 5',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _navyDark,
                ),
              ),
            ],
          ),
          if (review.reviewText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '"${review.reviewText}"',
              style: const TextStyle(
                fontSize: 13,
                color: _navyDark,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _truncateId(String id) {
  if (id.length <= 8) return id;
  return '${id.substring(0, 8)}…';
}

String _taxLabel(Booking booking) {
  final base = booking.subtotal - booking.discountAmount;
  if (booking.taxAmount <= 0 || base <= 0) return 'Tax (GST 10%)';
  final rate = booking.taxAmount / base * 100;
  final rounded = (rate * 10).round() / 10;
  final label = rounded == rounded.truncate().toDouble()
      ? '${rounded.toInt()}%'
      : '$rounded%';
  return 'Tax (GST $label)';
}
