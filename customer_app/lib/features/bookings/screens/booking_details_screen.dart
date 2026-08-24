import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_modal_dialog.dart';
import '../../../models/booking_item.dart';
import '../../../models/my_booking_model.dart';
import '../../catalog/providers/catalog_providers.dart';
import '../../catalog/utils/catalog_launcher.dart';
import '../services/bookings_providers.dart';
import '../widgets/booking_status_timeline.dart';
import '../../notifications/services/notification_providers.dart';
import '../../profile/services/profile_providers.dart';
import '../../reviews/services/review_providers.dart';
import '../../reviews/widgets/review_modal.dart';
import '../services/invoice_service.dart';
import '../widgets/cancel_booking_reason_dialog.dart';
import '../widgets/vendor_nearby_warning_dialog.dart';
import '../../amc/screens/amc_contract_details_screen.dart';
import '../../amc/providers/amc_contract_provider.dart';
import '../../amc/models/amc_contract_model.dart';
import '../../warranties/widgets/warranty_card.dart';
import '../../call_bridge/widgets/call_bridge_dialog.dart';

class BookingDetailsScreen extends ConsumerStatefulWidget {
  final MyBookingModel booking;
  final bool inModal;
  final VoidCallback? onClose;

  const BookingDetailsScreen({
    super.key,
    required this.booking,
    this.inModal = false,
    this.onClose,
  });

  @override
  ConsumerState<BookingDetailsScreen> createState() =>
      _BookingDetailsScreenState();
}

class _BookingDetailsScreenState extends ConsumerState<BookingDetailsScreen> {
  bool _isCancelling = false;
  bool _isDownloadingInvoice = false;

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
                  actions: [
                    if (widget.onClose != null)
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Close',
                        onPressed: widget.onClose,
                      ),
                  ],
                ),
          body: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? (constraints.maxWidth - 600) / 2 : 0,
            ),
            child: Column(
              children: [
                _StatusBanner(booking: booking),
                if (booking.isCompleted) WarrantyCard(booking: booking),
                if (booking.completionOtp != null &&
                    _otpVisibleForStatus(booking.status))
                  _OtpDisplayCard(otp: booking.completionOtp!),
                if (booking.isAmc) _AmcContractCard(booking: booking),
                _BookingInfoCard(booking: booking),
                _VendorCard(booking: booking),
                _ServiceInfoCard(booking: booking),
                _AddonsCard(booking: booking),
                _ServicePhotosCard(bookingId: booking.id),
                _AddressCard(booking: booking),
                _TimelineCard(booking: booking),
                _PaymentCard(booking: booking),
                const SizedBox(height: 16),
                _ActionButtons(
                  booking: booking,
                  isLoading: _isCancelling,
                  hasReview: reviewAsync?.valueOrNull != null,
                  isDownloadingInvoice: _isDownloadingInvoice,
                  onCancel: () => _confirmCancel(booking),
                  onRebook: () => _rebook(booking),
                  onRate: () => _openReviewModal(booking),
                  onDownloadInvoice: () => _downloadInvoice(booking),
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
    debugPrint('[DODO][CancelFlow] Customer initiated cancel for booking ${b.id}');
    final cancelResult = await showDialog<CancelBookingResult>(
      context: context,
      builder: (_) => const CancelBookingReasonDialog(),
    );
    if (cancelResult == null) {
      debugPrint('[DODO][CancelFlow] Customer dismissed CancelBookingReasonDialog');
      return;
    }
    if (!mounted) return;

    setState(() => _isCancelling = true);
    try {
      debugPrint('[DODO][CancelFlow] Validating vendor geofence for booking ${b.id}');
      final geoResult = await ref
          .read(bookingsServiceProvider)
          .validateVendorGeofence(b.id);

      debugPrint(
          '[DODO][CancelFlow] Geofence check result: isInsideGeofence=${geoResult.isInsideGeofence}, minDistance=${geoResult.minDistanceMeters}');

      if (geoResult.isInsideGeofence) {
        if (!mounted) return;
        setState(() => _isCancelling = false);

        debugPrint(
            '[DODO][CancelFlow] Vendor is inside geofence! Displaying VendorNearbyWarningDialog...');

        final proceed = await showDialog<bool>(
          context: context,
          builder: (_) => VendorNearbyWarningDialog(
            minDistanceMeters: geoResult.minDistanceMeters,
            geofenceRadiusMeters: geoResult.geofenceRadiusMeters,
          ),
        );

        debugPrint(
            '[DODO][CancelFlow] VendorNearbyWarningDialog closed with proceed=$proceed');

        if (proceed != true) {
          debugPrint(
              '[DODO][CancelFlow] Customer elected to Go Back. Cancellation ABORTED.');
          return;
        }
        if (!mounted) return;
        setState(() => _isCancelling = true);
      }

      debugPrint(
          '[DODO][CancelFlow] Executing cancelBooking for booking ${b.id}...');
      await ref.read(bookingsServiceProvider).cancelBooking(
            b.id,
            reason: cancelResult.reason,
            remarks: cancelResult.remarks,
          );
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

  Future<void> _downloadInvoice(MyBookingModel b) async {
    setState(() => _isDownloadingInvoice = true);
    try {
      final profile = await ref.read(profileProvider.future);
      await InvoiceService.downloadInvoice(booking: b, customer: profile);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not generate invoice: $e')),
      );
    } finally {
      if (mounted) setState(() => _isDownloadingInvoice = false);
    }
  }

  Future<void> _rebook(MyBookingModel b) async {
    final parentNodeId =
        b.items.isNotEmpty ? b.items.first.catalogParentNodeId : null;
    final catalogService = ref.read(catalogServiceProvider);
    final node = parentNodeId != null
        ? await catalogService.fetchNodeWithParent(b.serviceId, parentNodeId)
        : await catalogService.fetchNode(b.serviceId);
    if (node == null || !mounted) return;
    openCatalogNode(context, node, parentId: parentNodeId ?? node.parentId);
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
              booking.isAmc && booking.status == BookingStatus.completed
                  ? 'AMC Visit Done'
                  : BookingStatus.labelFor(booking.status, assignmentType: booking.assignmentType),
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
    // AMC bookings: a completed visit means the visit is done, not the contract
    if (booking.isAmc && status == BookingStatus.completed) {
      return (
        AppColors.success,
        'AMC visit completed — contract still active',
        Icons.task_alt_rounded,
      );
    }
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

class _AddonsCard extends StatelessWidget {
  final MyBookingModel booking;

  const _AddonsCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final addons = booking.addons;
    if (addons.isEmpty) return const SizedBox.shrink();
    return _SectionCard(
      title: 'ADD-ONS (${addons.length})',
      children: [
        for (int i = 0; i < addons.length; i++) ...[
          Row(
            children: [
              const Icon(Icons.extension_rounded,
                  size: 14, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  addons[i].name,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                ),
              ),
              Text(
                '+ ₹${addons[i].price % 1 == 0 ? addons[i].price.toInt() : addons[i].price.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
              ),
            ],
          ),
          if (i < addons.length - 1) const SizedBox(height: 8),
        ],
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

// ── Service Photos Card ───────────────────────────────────────────────────────

class _ServicePhotosCard extends ConsumerWidget {
  final String bookingId;

  const _ServicePhotosCard({required this.bookingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imagesAsync = ref.watch(bookingImagesProvider(bookingId));
    return imagesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (images) {
        if (images.isEmpty) return const SizedBox.shrink();
        final before =
            images.where((i) => i['image_type'] == 'before').toList();
        final after =
            images.where((i) => i['image_type'] == 'after').toList();
        if (before.isEmpty && after.isEmpty) return const SizedBox.shrink();
        return _SectionCard(
          title: 'SERVICE PHOTOS',
          children: [
            if (before.isNotEmpty) ...[
              _PhotoGallery(label: 'Before', photos: before),
              if (after.isNotEmpty) const SizedBox(height: 14),
            ],
            if (after.isNotEmpty)
              _PhotoGallery(label: 'After', photos: after),
          ],
        );
      },
    );
  }
}

class _PhotoGallery extends StatelessWidget {
  final String label;
  final List<Map<String, dynamic>> photos;

  const _PhotoGallery({required this.label, required this.photos});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: tt.labelSmall?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final url = photos[i]['image_url'] as String;
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  url,
                  width: 90,
                  height: 90,
                  fit: BoxFit.cover,
                  loadingBuilder: (ctx, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      width: 90,
                      height: 90,
                      color: AppColors.background,
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  },
                  errorBuilder: (_, _, _) => Container(
                    width: 90,
                    height: 90,
                    color: AppColors.background,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.textHint,
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
    final isVendorAssigned = (booking.vendorId != null && booking.vendorId!.isNotEmpty) ||
        (booking.vendorName != null && booking.vendorName!.isNotEmpty);

    final vendorDisplayName = (booking.vendorName != null && booking.vendorName!.isNotEmpty)
        ? booking.vendorName!
        : 'Assigned Vendor';

    final statusLower = booking.status.toLowerCase();
    final isCallActiveStatus = const {
      'assigned',
      'assigned_to_dodo_team',
      'accepted',
      'en_route',
      'in_progress',
      'started',
      'awaiting_verification',
    }.contains(statusLower);

    final showCallButton = isVendorAssigned && isCallActiveStatus;

    return _SectionCard(
      title: 'ASSIGNED VENDOR',
      children: [
        if (isVendorAssigned) ...[
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
                    vendorDisplayName[0].toUpperCase(),
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      vendorDisplayName,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shield_rounded, size: 12, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Protected via DODO Call Bridge',
                            style: tt.bodySmall?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showCallButton) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  CallBridgeDialog.show(
                    context,
                    bookingId: booking.id,
                    bookingNumber: booking.displayBookingNumber,
                    callerId: booking.customerId ?? 'customer_1',
                    calleeId: booking.vendorId ?? 'vendor_1',
                    callerRole: 'customer',
                    recipientName: vendorDisplayName,
                    bookingStatus: booking.status,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  elevation: 0,
                ),
                icon: const Icon(Icons.phone_rounded, size: 16),
                label: const Text(
                  'Call via DODO',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ]
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

// ── AMC Contract Card ─────────────────────────────────────────────────────────

class _AmcContractCard extends ConsumerWidget {
  final MyBookingModel booking;

  const _AmcContractCard({required this.booking});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final contractId = booking.amcContractId;

    final contractAsync =
        contractId != null ? ref.watch(amcContractProvider(contractId)) : null;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.repeat_rounded,
                      color: AppColors.primary, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AMC CONTRACT',
                        style: tt.labelMedium?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (booking.amcPlanName != null)
                        Text(
                          booking.amcPlanName!,
                          style: tt.titleSmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'AMC',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Contract data rows
            if (contractAsync == null)
              // No contract ID — show booking-level fallback
              ...[
              if (booking.amcRecurrenceInterval != null)
                _DetailRow(
                  icon: Icons.schedule_rounded,
                  label: 'Recurrence',
                  value: booking.amcRecurrenceInterval!,
                ),
            ] else
              contractAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (_, __) => _fallbackRows(),
                data: (contract) =>
                    contract != null ? _contractRows(contract) : _fallbackRows(),
              ),

            // View AMC Contract button
            if (contractId != null) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AmcContractDetailsScreen(
                        contractId: contractId,
                        initialPlanName:
                            booking.amcPlanName ?? 'AMC Contract',
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('View AMC Contract'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fallbackRows() => Column(
        children: [
          if (booking.amcRecurrenceInterval != null)
            _DetailRow(
              icon: Icons.schedule_rounded,
              label: 'Recurrence',
              value: booking.amcRecurrenceInterval!,
            ),
          if (booking.amcContractId != null)
            _DetailRow(
              icon: Icons.article_outlined,
              label: 'Contract ID',
              value: booking.amcContractId!,
              valueColor: AppColors.primary,
            ),
        ],
      );

  Widget _contractRows(AmcContractModel c) {
    final fmt = _DateFmt();
    final endDate = c.packageDuration != null
        ? _endDate(c.createdAt, c.packageDuration!)
        : null;
    return Column(
      children: [
        _DetailRow(
          icon: Icons.badge_outlined,
          label: 'Plan Name',
          value: c.planName.isNotEmpty
              ? c.planName
              : (booking.amcPlanName ?? '—'),
        ),
        _DetailRow(
          icon: Icons.circle_outlined,
          label: 'Status',
          value: _statusLabel(c.status),
          valueColor: _statusColor(c.status),
        ),
        if (c.packageDuration != null)
          _DetailRow(
            icon: Icons.date_range_rounded,
            label: 'Package Duration',
            value: _durationLabel(c.packageDuration!),
          ),
        _DetailRow(
          icon: Icons.repeat_rounded,
          label: 'Service Interval',
          value: c.recurrenceInterval.isNotEmpty
              ? c.recurrenceInterval
              : _intervalLabel(c.serviceInterval),
        ),
        _DetailRow(
          icon: Icons.currency_rupee_rounded,
          label: 'Price Per Visit',
          value: '₹${c.pricePerVisit.toStringAsFixed(2)}',
        ),
        _DetailRow(
          icon: Icons.format_list_numbered_rounded,
          label: 'Total Visits',
          value: '${c.effectiveTotalVisits}',
        ),
        _DetailRow(
          icon: Icons.check_circle_outline_rounded,
          label: 'Completed Visits',
          value: '${c.completedVisits}',
        ),
        _DetailRow(
          icon: Icons.pending_outlined,
          label: 'Remaining Visits',
          value: '${c.remainingVisits}',
        ),
        if (c.originalTotal != null && c.originalTotal! > 0)
          _DetailRow(
            icon: Icons.receipt_outlined,
            label: 'Original Total',
            value: '₹${c.originalTotal!.toStringAsFixed(2)}',
          ),
        if (c.discountAmount != null && c.discountAmount! > 0)
          _DetailRow(
            icon: Icons.local_offer_outlined,
            label: 'Discount',
            value: '−₹${c.discountAmount!.toStringAsFixed(2)}',
          ),
        if (c.finalPrice != null && c.finalPrice! > 0)
          _DetailRow(
            icon: Icons.currency_rupee_rounded,
            label: 'Final AMC Price',
            value: '₹${c.finalPrice!.toStringAsFixed(2)}',
            valueColor: AppColors.primary,
          ),
        _DetailRow(
          icon: Icons.calendar_today_rounded,
          label: 'Start Date',
          value: fmt.format(c.createdAt.toLocal()),
        ),
        if (endDate != null)
          _DetailRow(
            icon: Icons.event_rounded,
            label: 'End Date',
            value: fmt.format(endDate.toLocal()),
          ),
      ],
    );
  }

  static DateTime? _endDate(DateTime start, String packageDuration) {
    final days = switch (packageDuration) {
      'monthly' => 30,
      'quarterly' => 91,
      'half_yearly' => 182,
      'yearly' => 365,
      _ => null,
    };
    return days != null ? start.add(Duration(days: days)) : null;
  }

  static String _statusLabel(String s) => switch (s) {
        'active' => 'Active',
        'paused' => 'Paused',
        'completed' => 'Completed',
        'cancelled' => 'Cancelled',
        _ => s,
      };

  static Color _statusColor(String s) => switch (s) {
        'active' => AppColors.success,
        'paused' => AppColors.warning,
        'completed' => AppColors.primary,
        'cancelled' => AppColors.error,
        _ => AppColors.textSecondary,
      };

  static String _durationLabel(String d) => switch (d) {
        'monthly' => 'Monthly',
        'quarterly' => 'Quarterly',
        'half_yearly' => 'Half-Yearly',
        'yearly' => 'Yearly',
        _ => d,
      };

  static String _intervalLabel(String? i) => switch (i) {
        'weekly' => 'Weekly',
        'bi_weekly' => 'Bi-Weekly',
        'monthly' => 'Monthly',
        _ => i ?? '—',
      };
}

class _DateFmt {
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String format(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';
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
  final VoidCallback? onDownloadInvoice;
  final bool isLoading;
  final bool hasReview;
  final bool isDownloadingInvoice;

  const _ActionButtons({
    required this.booking,
    required this.onCancel,
    required this.onRebook,
    required this.onRate,
    this.onDownloadInvoice,
    this.isLoading = false,
    this.hasReview = false,
    this.isDownloadingInvoice = false,
  });

  @override
  Widget build(BuildContext context) {
    final showAny = booking.canCancel ||
        booking.canRebook ||
        booking.canReview ||
        booking.isCompleted;
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
          if (booking.isCompleted) ...[
            OutlinedButton.icon(
              onPressed:
                  isDownloadingInvoice ? null : onDownloadInvoice,
              icon: isDownloadingInvoice
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded, size: 18),
              label: Text(
                  isDownloadingInvoice ? 'Generating…' : 'Download Invoice'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
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
