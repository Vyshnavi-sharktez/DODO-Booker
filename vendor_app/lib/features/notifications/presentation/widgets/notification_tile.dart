import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/date_utils.dart';
import '../../domain/models/vendor_notification.dart';

class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.notification,
    required this.isRead,
    this.onTap,
    this.onToggleRead,
    this.onDelete,
  });

  final VendorNotification notification;
  final bool isRead;
  final VoidCallback? onTap;
  final VoidCallback? onToggleRead;
  final VoidCallback? onDelete;

  static IconData _icon(String type) => switch (type) {
        'vendor_assigned' || 'vendor_reassigned' => Icons.assignment_ind_outlined,
        'vendor_started' => Icons.play_circle_outline_rounded,
        'vendor_rejected' => Icons.block_outlined,
        'booking_completed' => Icons.check_circle_outline_rounded,
        'booking_cancelled' => Icons.cancel_outlined,
        'booking_created' => Icons.add_circle_outline_rounded,
        'promotion' => Icons.local_offer_outlined,
        'system' => Icons.info_outline_rounded,
        _ => Icons.notifications_outlined,
      };

  static Color _iconColor(String type) => switch (type) {
        'vendor_assigned' || 'vendor_reassigned' => AppColors.primary,
        'vendor_started' => AppColors.statusInProgress,
        'vendor_rejected' => AppColors.error,
        'booking_completed' => AppColors.success,
        'booking_cancelled' => AppColors.error,
        'booking_created' => AppColors.accent,
        'promotion' => AppColors.warning,
        _ => AppColors.textHint,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = notification.notificationType;
    final color = _iconColor(type);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type icon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_icon(type), size: 20, color: color),
                  ),
                  const SizedBox(width: 12),
                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                notification.title,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight:
                                      isRead ? FontWeight.w500 : FontWeight.w700,
                                  color: isRead
                                      ? AppColors.textSecondary
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ),
                            if (!isRead)
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(left: 8, top: 4),
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        if (notification.message.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            notification.message,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.4,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 4),
                        if (notification.createdAt != null)
                          Text(
                            AppDateUtils.relativeLabel(notification.createdAt!),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.textHint,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (onToggleRead != null || onDelete != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 10, 8, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onToggleRead != null)
                  _SmallAction(
                    icon: isRead
                        ? Icons.mark_email_unread_outlined
                        : Icons.mark_email_read_outlined,
                    tooltip: isRead ? 'Mark unread' : 'Mark read',
                    onTap: onToggleRead!,
                  ),
                if (onToggleRead != null && onDelete != null)
                  const SizedBox(height: 2),
                if (onDelete != null)
                  _SmallAction(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Delete',
                    onTap: onDelete!,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Small action button ───────────────────────────────────────────────────────

class _SmallAction extends StatelessWidget {
  const _SmallAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 15, color: AppColors.textHint),
        ),
      ),
    );
  }
}
