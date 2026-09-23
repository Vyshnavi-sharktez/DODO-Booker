import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../domain/models/refund_status_event.dart';

class RefundStatusTimeline extends StatelessWidget {
  final List<RefundStatusEvent> events;

  const RefundStatusTimeline({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No status history recorded.',
          style: TextStyle(color: Color(0xFF718096), fontSize: 13),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: events.length,
      itemBuilder: (context, i) {
        final event = events[i];
        final isLast = i == events.length - 1;
        return _TimelineEntry(
          event: event,
          isLast: isLast,
        );
      },
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  final RefundStatusEvent event;
  final bool isLast;

  const _TimelineEntry({required this.event, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(event.toStatus);
    final label = _statusLabel(event.toStatus);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: const Color(0xFFE2E8F0),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('d MMM yyyy, h:mm a').format(event.createdAt.toLocal()),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF718096),
                    ),
                  ),
                  if (event.notes != null && event.notes!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      event.notes!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF4A5568),
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

  static Color _statusColor(String status) => switch (status) {
        'submitted' => const Color(0xFF718096),
        'under_review' => const Color(0xFF3182CE),
        'more_info_requested' => const Color(0xFFDD6B20),
        'approved' || 'partially_approved' => const Color(0xFF38A169),
        'rejected' => const Color(0xFFE53E3E),
        'processing' => const Color(0xFF805AD5),
        'completed' => const Color(0xFF2F855A),
        'failed' => const Color(0xFFE53E3E),
        'closed' => const Color(0xFF718096),
        _ => const Color(0xFF718096),
      };

  static String _statusLabel(String status) => switch (status) {
        'submitted' => 'Ticket Submitted',
        'under_review' => 'Under Review',
        'more_info_requested' => 'More Information Requested',
        'approved' => 'Approved',
        'partially_approved' => 'Partially Approved',
        'rejected' => 'Rejected',
        'processing' => 'Refund Processing',
        'completed' => 'Refund Completed',
        'failed' => 'Refund Failed',
        'closed' => 'Ticket Closed',
        _ => status,
      };
}
