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
        timestamp: booking.createdAt.add(const Duration(hours: 1)),
      ));
    }

    return Column(
      children: List.generate(events.length, (i) {
        final event = events[i];
        final isLast = i == events.length - 1;
        return _TimelineStep(
          event: event,
          isLast: isLast,
          isCancelledStep: event.status == BookingStatus.cancelled,
        );
      }),
    );
  }
}

class _TimelineStep extends StatelessWidget {
  final BookingStatusEvent event;
  final bool isLast;
  final bool isCancelledStep;

  const _TimelineStep({
    required this.event,
    required this.isLast,
    required this.isCancelledStep,
  });

  Color get _dotColor {
    if (isCancelledStep) return AppColors.error;
    if (event.isReached) return AppColors.success;
    return AppColors.border;
  }

  Color get _lineColor =>
      event.isReached ? AppColors.success : AppColors.border;

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
                // Dot
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: reached ? _dotColor : AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _dotColor,
                      width: reached ? 0 : 2,
                    ),
                  ),
                  child: reached
                      ? Icon(
                          isCancelledStep
                              ? Icons.close_rounded
                              : Icons.check_rounded,
                          size: 14,
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
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.label,
                    style: tt.bodySmall?.copyWith(
                      fontWeight:
                          reached ? FontWeight.w700 : FontWeight.w400,
                      color: reached
                          ? (isCancelledStep
                              ? AppColors.error
                              : AppColors.textPrimary)
                          : AppColors.textHint,
                    ),
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
