import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/my_booking_model.dart';
import '../../../models/booking_status_event.dart';

class BookingStatusTimeline extends StatelessWidget {
  final MyBookingModel booking;

  const BookingStatusTimeline({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    final events = List<BookingStatusEvent>.from(booking.timeline);

    if (booking.isCancelled) {
      events.add(BookingStatusEvent(
        status: BookingStatus.cancelled,
        label: 'Cancelled',
        isReached: true,
        timestamp: booking.createdAt.add(const Duration(hours: 1)),
      ));
    }

    // The last reached non-cancelled step is the "active" (current) step.
    final lastReachedIdx = booking.isCancelled
        ? -1
        : events.lastIndexWhere(
            (e) => e.isReached && e.status != BookingStatus.cancelled,
          );

    return Column(
      children: List.generate(events.length, (i) {
        final event = events[i];
        final isLast = i == events.length - 1;
        return _TimelineStep(
          event: event,
          isLast: isLast,
          isCancelledStep: event.status == BookingStatus.cancelled,
          isActive: i == lastReachedIdx,
        );
      }),
    );
  }
}

class _TimelineStep extends StatelessWidget {
  final BookingStatusEvent event;
  final bool isLast;
  final bool isCancelledStep;
  final bool isActive;

  const _TimelineStep({
    required this.event,
    required this.isLast,
    required this.isCancelledStep,
    required this.isActive,
  });

  Color get _dotColor {
    if (isCancelledStep) return AppColors.error;
    if (isActive) return AppColors.primary;
    if (event.isReached) return AppColors.success;
    return AppColors.border;
  }

  // Line after this step: green if fully completed, gray otherwise.
  Color get _lineColor =>
      event.isReached && !isActive ? AppColors.success : AppColors.border;

  IconData get _dotIcon {
    if (isCancelledStep) return Icons.close_rounded;
    if (isActive) return Icons.radio_button_checked_rounded;
    return Icons.check_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final reached = event.isReached;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: dot + vertical line
          SizedBox(
            width: 32,
            child: Column(
              children: [
                // Dot — slightly larger for the active step
                Container(
                  width: isActive ? 26 : 24,
                  height: isActive ? 26 : 24,
                  decoration: BoxDecoration(
                    color: reached ? _dotColor : AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _dotColor,
                      width: reached ? 0 : 2,
                    ),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withAlpha(60),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: reached
                      ? Icon(
                          _dotIcon,
                          size: isActive ? 15 : 14,
                          color: Colors.white,
                        )
                      : null,
                ),
                // Connecting line
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: _lineColor,
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          // Right: label + timestamp
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.label,
                          style: tt.bodySmall?.copyWith(
                            fontWeight: reached
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: reached
                                ? (isCancelledStep
                                    ? AppColors.error
                                    : isActive
                                        ? AppColors.primary
                                        : AppColors.textPrimary)
                                : AppColors.textHint,
                          ),
                        ),
                      ),
                      if (isActive)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Now',
                            style: tt.labelSmall?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (event.timestamp != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _formatTimestamp(event.timestamp!),
                      style: tt.labelSmall?.copyWith(
                        color: AppColors.textHint,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.day} ${months[dt.month - 1]}  ·  $h:$m $period';
  }
}
