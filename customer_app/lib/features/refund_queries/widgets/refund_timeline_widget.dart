import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../models/refund_status_event_model.dart';

class RefundTimelineWidget extends StatelessWidget {
  const RefundTimelineWidget({super.key, required this.events});

  final List<RefundStatusEventModel> events;

  static String _statusLabel(String? status) {
    switch (status) {
      case 'submitted':           return 'Submitted';
      case 'under_review':        return 'Under Review';
      case 'more_info_requested': return 'Info Requested';
      case 'approved':            return 'Approved';
      case 'partially_approved':  return 'Partially Approved';
      case 'rejected':            return 'Rejected';
      case 'processing':          return 'Processing';
      case 'completed':           return 'Completed';
      case 'failed':              return 'Retrying';
      case 'closed':              return 'Closed';
      default:                    return status ?? 'Unknown';
    }
  }

  static Color _statusColor(String? status) {
    switch (status) {
      case 'completed':          return AppColors.success;
      case 'approved':
      case 'partially_approved': return const Color(0xFF1A73E8);
      case 'rejected':
      case 'failed':             return AppColors.error;
      case 'more_info_requested': return AppColors.warning;
      case 'processing':         return const Color(0xFF9C27B0);
      case 'under_review':       return AppColors.gold;
      case 'closed':             return AppColors.textHint;
      default:                   return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    if (events.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No history yet'),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: events.length,
      itemBuilder: (ctx, i) {
        final e = events[i];
        final isLast = i == events.length - 1;
        final color = _statusColor(e.toStatus);
        final label = _statusLabel(e.toStatus);
        final byLine = e.changedByType == 'customer'
            ? 'You'
            : e.changedByType == 'admin'
                ? 'DODO Support'
                : 'System';

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Timeline spine
              SizedBox(
                width: 32,
                child: Column(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: color.withAlpha(60),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 1.5,
                          color: AppColors.divider,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: isLast ? 0 : 20,
                    top: 0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            byLine,
                            style: tt.labelSmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const Text(
                            ' · ',
                            style: TextStyle(
                              color: AppColors.textHint,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            DateFormat('d MMM, h:mm a')
                                .format(e.createdAt.toLocal()),
                            style: tt.labelSmall?.copyWith(
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      ),
                      if (e.notes != null && e.notes!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            e.notes!,
                            style: tt.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.5,
                            ),
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
      },
    );
  }
}
