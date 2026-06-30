import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/service_image_registry.dart';
import '../../../core/widgets/section_header.dart';
import '../../../models/my_booking_model.dart';
import '../../bookings/utils/booking_detail_launcher.dart';
import '../../bookings/utils/my_bookings_launcher.dart';

class RecentBookingsSection extends StatelessWidget {
  final List<MyBookingModel> bookings;

  const RecentBookingsSection({super.key, required this.bookings});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SectionHeader(
            title: 'Recent Bookings',
            onSeeAll: () => openMyBookings(context),
          ),
        ),
        const SizedBox(height: 10),
        ...bookings.map((b) => _BookingCard(booking: b)),
      ],
    );
  }
}

class _BookingCard extends StatelessWidget {
  final MyBookingModel booking;

  const _BookingCard({required this.booking});

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String get _formattedDate {
    final d = booking.scheduledDate;
    return '${d.day} ${_months[d.month - 1]} · ${booking.timeSlot}';
  }

  (Color, Color, String) get _statusMeta {
    return switch (booking.status) {
      BookingStatus.completed =>
        (AppColors.success, const Color(0xFFE6F4EA), 'Completed'),
      BookingStatus.cancelled =>
        (AppColors.error, const Color(0xFFFCE8E6), 'Cancelled'),
      BookingStatus.inProgress ||
      BookingStatus.started ||
      BookingStatus.enRoute ||
      BookingStatus.awaitingVerification =>
        (AppColors.warning, const Color(0xFFFFF8E1), 'Ongoing'),
      _ => (AppColors.textPrimary, const Color(0xFFF3F4F6), 'Upcoming'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (statusColor, statusBg, statusLabel) = _statusMeta;
    final imageUrl =
        ServiceImageRegistry.resolve(null, booking.categoryName);

    return GestureDetector(
      onTap: () => openBookingDetail(context, booking),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 0.8),
            boxShadow: const [
              BoxShadow(
                color: Color(0x07000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Service image ─────────────────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  imageUrl,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => Container(
                    width: 64,
                    height: 64,
                    color: AppColors.surfaceVariant,
                    child: const Icon(
                      Icons.home_repair_service_rounded,
                      size: 24,
                      color: AppColors.textHint,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // ── Text content ──────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            booking.serviceName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Status pill
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: statusColor.withAlpha(60)),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _formattedDate,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textHint,
                        height: 1.3,
                      ),
                    ),
                    // Rebook button (completed or cancelled)
                    if (booking.canRebook) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => context
                              .push('/service-detail/${booking.serviceId}'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.textPrimary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.replay_rounded,
                                  size: 11,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Rebook',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
