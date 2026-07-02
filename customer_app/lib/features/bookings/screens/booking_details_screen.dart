import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_modal_dialog.dart';
import '../../../models/booking_item.dart';
import '../../../models/my_booking_model.dart';
import '../services/bookings_providers.dart';
import '../widgets/booking_status_timeline.dart';
import '../../notifications/services/notification_providers.dart';
import '../../reviews/services/review_providers.dart';
import '../../reviews/widgets/review_modal.dart';

class BookingDetailsScreen extends ConsumerStatefulWidget {
  final MyBookingModel booking;
  final bool inModal;

  const BookingDetailsScreen({
    super.key,
    required this.booking,
    this.inModal = false,
  });

  @override
  ConsumerState<BookingDetailsScreen> createState() =>
      _BookingDetailsScreenState();
}

class _BookingDetailsScreenState extends ConsumerState<BookingDetailsScreen> {
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    // Force a re-fetch every time this screen opens so the customer always
    // sees the latest vendor assignment and status from the server.
    Future.microtask(() {
      if (mounted) ref.invalidate(bookingByIdProvider(widget.booking.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    final bookingAsync = ref.watch(bookingByIdProvider(widget.booking.id));
    final booking = bookingAsync.valueOrNull ?? widget.booking;
    debugPrint('[OTP][Screen] build — asyncState=${bookingAsync.runtimeType}  '
        'status=${booking.status}  completionOtp=${booking.completionOtp}  '
        'source=${bookingAsync.valueOrNull != null ? "provider" : "widget.booking"}');
    final reviewAsync = booking.canReview
        ? ref.watch(bookingReviewProvider(booking.id))
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 700;
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: widget.inModal
              ? null
              : AppBar(
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Booking Details'),
                      Text(
                        booking.id,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
          body: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? (constraints.maxWidth - 600) / 2 : 0,
            ),
            child: Column(
              children: [
                _StatusBanner(booking: booking),
                if (booking.completionOtp != null &&
                    _otpVisibleForStatus(booking.status))
                  _OtpDisplayCard(otp: booking.completionOtp!),
                _BookingInfoCard(booking: booking),
                _ServiceInfoCard(booking: booking),
                _AddressCard(booking: booking),
                if (!booking.isDodoTeam) _VendorCard(booking: booking),
                _TimelineCard(booking: booking),
                _PaymentCard(booking: booking),
                const SizedBox(height: 16),
                _ActionButtons(
                  booking: booking,
                  isLoading: _isCancelling,
                  hasReview: reviewAsync?.valueOrNull != null,
                  onCancel: () => _confirmCancel(booking),
                  onRebook: () => _rebook(booking),
                  onRate: () => _openReviewModal(booking),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmCancel(MyBookingModel b) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel Booking?'),
        content: const Text('Are you sure you want to cancel this booking?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No, Keep It'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _isCancelling = true);
    try {
      await ref.read(bookingsServiceProvider).cancelBooking(b.id);
      if (!mounted) return;
      ref.invalidate(myBookingsProvider);
      ref.invalidate(bookingByIdProvider(b.id));
      ref.invalidate(notificationsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking cancelled successfully'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to cancel: $e')),
      );
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  void _rebook(MyBookingModel b) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Rebook feature coming soon')),
    );
  }

  Future<void> _openReviewModal(MyBookingModel b) async {
    debugPrint('[DODO][Review] Opening review modal for bookingId=${b.id}');
    await AppModalDialog.show(
      context: context,
      child: ReviewModal(bookingId: b.id, serviceName: b.serviceName),
    );
    // Refresh review state after modal closes (submitted or viewed)
    ref.invalidate(bookingReviewProvider(b.id));
  }
}

bool _otpVisibleForStatus(String status) => const {
      BookingStatus.inProgress,
      BookingStatus.started,
      BookingStatus.awaitingVerification,
      BookingStatus.completed,
    }.contains(status);

// ── Status Banner ─────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final MyBookingModel booking;

  const _StatusBanner({required this.booking});

  @override
  Widget build(BuildContext context) {
    final (color, label, icon) = _bannerMeta(booking.status);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(55)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withAlpha(35),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              BookingStatus.labelFor(booking.status, assignmentType: booking.assignmentType),
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  (Color, String, IconData) _bannerMeta(String status) {
    switch (status) {
      case BookingStatus.pending:
        return (AppColors.warning, 'Waiting for provider assignment', Icons.hourglass_top_rounded);
      case BookingStatus.assigned:
        return (AppColors.primary, 'Vendor has been assigned', Icons.person_pin_rounded);
      case BookingStatus.assignedToDodoTeam:
        return (const Color(0xFF6B46C1), 'DODO Team has been assigned', Icons.groups_rounded);
      case BookingStatus.accepted:
        return (const Color(0xFF00ACC1), 'Vendor confirmed your booking', Icons.thumb_up_rounded);
      case BookingStatus.enRoute:
        return (const Color(0xFF5C6BC0), 'Technician is on the way', Icons.directions_bike_rounded);
      case BookingStatus.inProgress:
      case BookingStatus.started:
        return (const Color(0xFFFF6D00), 'Service is in progress', Icons.construction_rounded);
      case BookingStatus.awaitingVerification:
        return (AppColors.warning, 'Share OTP with provider to complete service', Icons.lock_clock_rounded);
      case BookingStatus.completed:
        return (AppColors.success, 'Service completed successfully', Icons.check_circle_rounded);
      case BookingStatus.cancelled:
        return (AppColors.error, 'This booking was cancelled', Icons.cancel_rounded);
      default:
        return (AppColors.textHint, status, Icons.info_rounded);
    }
  }
}

// ── Section card helper ───────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: tt.labelMedium?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
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
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: tt.labelSmall?.copyWith(color: AppColors.textSecondary),
                ),
                Text(
                  value,
                  style: tt.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? AppColors.textPrimary,
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

// ── Individual section cards ──────────────────────────────────────────────────

class _BookingInfoCard extends StatelessWidget {
  final MyBookingModel booking;

  const _BookingInfoCard({required this.booking});

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  String get _scheduledDate {
    final d = booking.scheduledDate;
    return '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  String get _createdDate {
    final d = booking.createdAt;
    return '${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'BOOKING INFORMATION',
      children: [
        _DetailRow(
          icon: Icons.confirmation_number_rounded,
          label: 'Booking ID',
          value: booking.id,
          valueColor: AppColors.primary,
        ),
        _DetailRow(
          icon: Icons.calendar_today_rounded,
          label: 'Scheduled Date',
          value: '$_scheduledDate · ${booking.timeSlot}',
        ),
        _DetailRow(
          icon: Icons.access_time_rounded,
          label: 'Booked On',
          value: _createdDate,
        ),
      ],
    );
  }
}

class _ServiceInfoCard extends StatelessWidget {
  final MyBookingModel booking;

  const _ServiceInfoCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final items = booking.items;

    // Multi-service: list each booking item
    if (items.length > 1) {
      return _SectionCard(
        title: 'SERVICES (${items.length})',
        children: [
          for (int i = 0; i < items.length; i++) ...[
            _BookingItemRow(item: items[i], index: i + 1),
            if (i < items.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Divider(height: 0),
              ),
          ],
        ],
      );
    }

    // Single service: original display
    return _SectionCard(
      title: 'SERVICE INFORMATION',
      children: [
        _DetailRow(
          icon: Icons.home_repair_service_rounded,
          label: 'Service',
          value: items.isNotEmpty && items.first.serviceName.isNotEmpty
              ? items.first.serviceName
              : booking.serviceName,
        ),
        if (booking.categoryName != null)
          _DetailRow(
            icon: Icons.category_rounded,
            label: 'Category',
            value: booking.categoryName!,
          ),
        if (booking.subcategoryName != null)
          _DetailRow(
            icon: Icons.subdirectory_arrow_right_rounded,
            label: 'Subcategory',
            value: booking.subcategoryName!,
          ),
      ],
    );
  }
}

class _BookingItemRow extends StatelessWidget {
  final BookingItem item;
  final int index;

  const _BookingItemRow({required this.item, required this.index});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(
              '$index',
              style: tt.labelSmall?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.serviceName.isNotEmpty ? item.serviceName : 'Service',
                style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (item.categoryName != null)
                Text(
                  item.categoryName!,
                  style: tt.labelSmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₹${item.totalPrice.toStringAsFixed(0)}',
              style: tt.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            if (item.quantity > 1)
              Text(
                '${item.quantity} × ₹${item.unitPrice.toStringAsFixed(0)}',
                style:
                    tt.labelSmall?.copyWith(color: AppColors.textHint),
              ),
          ],
        ),
      ],
    );
  }
}

class _AddressCard extends StatelessWidget {
  final MyBookingModel booking;

  const _AddressCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final addr = booking.address;
    return _SectionCard(
      title: 'SERVICE ADDRESS',
      children: [
        _DetailRow(
          icon: Icons.location_on_rounded,
          label: addr.label,
          value: addr.fullAddress,
        ),
      ],
    );
  }
}

class _VendorCard extends StatelessWidget {
  final MyBookingModel booking;

  const _VendorCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final hasVendor = booking.vendorName != null;

    return _SectionCard(
      title: 'ASSIGNED VENDOR',
      children: [
        if (hasVendor)
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    booking.vendorName![0].toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.vendorName!,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (booking.vendorPhone != null)
                      Text(
                        booking.vendorPhone!,
                        style: tt.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (booking.vendorPhone != null)
                Container(
                  decoration: const BoxDecoration(
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.phone_rounded, size: 18),
                    color: AppColors.primary,
                    tooltip: 'Copy phone number',
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: booking.vendorPhone!),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Phone number copied to clipboard'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ),
            ],
          )
        else
          Row(
            children: [
              const Icon(
                Icons.pending_rounded,
                size: 16,
                color: AppColors.textHint,
              ),
              const SizedBox(width: 8),
              Text(
                'Vendor assignment in progress…',
                style: tt.bodySmall?.copyWith(
                  color: AppColors.textHint,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _TimelineCard extends StatelessWidget {
  final MyBookingModel booking;

  const _TimelineCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'STATUS TIMELINE',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
            ),
            const SizedBox(height: 16),
            BookingStatusTimeline(booking: booking),
          ],
        ),
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final MyBookingModel booking;

  const _PaymentCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return _SectionCard(
      title: 'PAYMENT INFORMATION',
      children: [
        _PaymentRow(
          label: 'Base Amount',
          value: '₹${booking.baseAmount.toStringAsFixed(2)}',
          tt: tt,
        ),
        _PaymentRow(
          label: 'GST (18%)',
          value: '₹${booking.taxAmount.toStringAsFixed(2)}',
          tt: tt,
        ),
        const Divider(height: 16),
        _PaymentRow(
          label: 'Total Paid',
          value: '₹${booking.totalAmount.toStringAsFixed(2)}',
          tt: tt,
          isTotal: true,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(Icons.info_outline_rounded, size: 12, color: AppColors.textHint),
            const SizedBox(width: 6),
            Text(
              'Payment integration coming soon',
              style: tt.labelSmall?.copyWith(
                color: AppColors.textHint,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final String label;
  final String value;
  final TextTheme tt;
  final bool isTotal;

  const _PaymentRow({
    required this.label,
    required this.value,
    required this.tt,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: isTotal
                ? tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)
                : tt.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          Text(
            value,
            style: isTotal
                ? tt.titleMedium?.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w800,
                  )
                : tt.bodySmall?.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// ── Action buttons ─────────────────────────────────────────────────────────────

// ── OTP Display Card (awaiting_verification) ──────────────────────────────────

class _OtpDisplayCard extends StatefulWidget {
  final String otp;

  const _OtpDisplayCard({required this.otp});

  @override
  State<_OtpDisplayCard> createState() => _OtpDisplayCardState();
}

class _OtpDisplayCardState extends State<_OtpDisplayCard> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.lock_clock_rounded,
                  size: 18,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'SERVICE COMPLETION OTP',
                    style: tt.labelMedium?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _visible = !_visible),
                  icon: Icon(
                    _visible
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 16,
                  ),
                  label: Text(_visible ? 'Hide OTP' : 'Show OTP'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.warning,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Digit boxes
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: widget.otp.split('').map((digit) {
                return Container(
                  width: 44,
                  height: 54,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withAlpha(18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.warning.withAlpha(80),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _visible ? digit : '•',
                      style: tt.headlineMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.warning.withAlpha(15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Share this OTP with your service provider when the service is complete.',
                      style: tt.bodySmall?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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

// ── Action buttons ─────────────────────────────────────────────────────────────

class _ActionButtons extends StatelessWidget {
  final MyBookingModel booking;
  final VoidCallback onCancel;
  final VoidCallback onRebook;
  final VoidCallback onRate;
  final bool isLoading;
  final bool hasReview;

  const _ActionButtons({
    required this.booking,
    required this.onCancel,
    required this.onRebook,
    required this.onRate,
    this.isLoading = false,
    this.hasReview = false,
  });

  @override
  Widget build(BuildContext context) {
    final showAny =
        booking.canCancel || booking.canRebook || booking.canReview;
    if (!showAny) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          if (booking.canReview) ...[
            FilledButton.icon(
              onPressed: onRate,
              icon: Icon(
                hasReview ? Icons.rate_review_rounded : Icons.star_rounded,
                size: 18,
              ),
              label: Text(hasReview ? 'View Review' : 'Rate Service'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor:
                    hasReview ? AppColors.textSecondary : AppColors.warning,
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (booking.canRebook) ...[
            FilledButton.icon(
              onPressed: onRebook,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Rebook This Service'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (booking.canCancel)
            OutlinedButton.icon(
              onPressed: isLoading ? null : onCancel,
              icon: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cancel_outlined, size: 18),
              label: Text(isLoading ? 'Cancelling…' : 'Cancel Booking'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
              ),
            ),
        ],
      ),
    );
  }
}
