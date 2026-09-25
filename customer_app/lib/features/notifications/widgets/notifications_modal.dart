import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_modal_dialog.dart';
import '../../../core/widgets/page_sheet.dart';
import '../../../routes/app_router.dart';
import '../../bookings/screens/booking_details_screen.dart';
import '../../bookings/services/bookings_providers.dart';
import '../../catalog/providers/catalog_providers.dart';
import '../../reviews/widgets/review_modal.dart';
import '../../catalog/utils/catalog_launcher.dart';
import '../../refund_queries/screens/refund_queries_flow.dart';
import '../../vendor_custom_service/widgets/vendor_custom_service_sheet.dart';
import '../models/notification_model.dart';
import '../services/notification_providers.dart';

class NotificationsModal extends ConsumerStatefulWidget {
  const NotificationsModal({super.key});

  @override
  ConsumerState<NotificationsModal> createState() =>
      _NotificationsModalState();
}

class _NotificationsModalState extends ConsumerState<NotificationsModal> {
  final _locallyRead = <String>{};
  final _locallyUnread = <String>{};
  final _locallyDeleted = <String>{};

  @override
  void initState() {
    super.initState();
    debugPrint('[DODO][Notif] modal initState — ${DateTime.now().millisecondsSinceEpoch}ms');
  }

  bool _isRead(NotificationModel n) {
    if (_locallyUnread.contains(n.id)) return false;
    return n.isRead || _locallyRead.contains(n.id);
  }

  Future<void> _markRead(NotificationModel n) async {
    if (_isRead(n)) return;
    setState(() {
      _locallyRead.add(n.id);
      _locallyUnread.remove(n.id);
    });
    try {
      await ref.read(notificationServiceProvider).markAsRead(n.id);
      ref.invalidate(notificationsProvider);
    } catch (_) {
      // Non-fatal — optimistic state already applied.
    }
  }

  Future<void> _toggleRead(NotificationModel n) async {
    final currentlyRead = _isRead(n);
    setState(() {
      if (currentlyRead) {
        _locallyUnread.add(n.id);
        _locallyRead.remove(n.id);
      } else {
        _locallyRead.add(n.id);
        _locallyUnread.remove(n.id);
      }
    });
    try {
      if (currentlyRead) {
        await ref.read(notificationServiceProvider).markAsUnread(n.id);
      } else {
        await ref.read(notificationServiceProvider).markAsRead(n.id);
      }
      ref.invalidate(notificationsProvider);
    } catch (_) {}
  }

  Future<void> _delete(NotificationModel n) async {
    setState(() => _locallyDeleted.add(n.id));
    try {
      await ref.read(notificationServiceProvider).deleteNotification(n.id);
      ref.invalidate(notificationsProvider);
    } catch (_) {}
  }

  Future<void> _handleTap(NotificationModel n) async {
    debugPrint(
        '[NOTIF][Customer] tapped — entity_type=${n.entityType}, entity_id=${n.entityId}, customer_question_id=${n.customerQuestionId}');
    _markRead(n);
    if (n.entityId == null) return;
    if (n.entityType == 'booking') {
      final isDesktop = MediaQuery.of(context).size.width >= 768;
      if (isDesktop) {
        final targetContext = Navigator.of(context).context;
        Navigator.of(context).pop();
        final booking =
            await ref.read(bookingByIdProvider(n.entityId!).future);
        if (booking != null && targetContext.mounted) {
          PageSheet.show(
            targetContext,
            title: 'Booking Details',
            child: BookingDetailsScreen(booking: booking, inModal: true),
          );
        }
      } else {
        final route =
            AppRoutes.notificationBooking.replaceFirst(':id', n.entityId!);
        debugPrint('[NOTIF][Customer] navigating → $route');
        Navigator.of(context).pop();
        GoRouter.of(context).push(route);
      }
    } else if (n.entityType == 'custom_service_question') {
      // Vendor answered a custom service question → open the service sheet.
      // The answered question is visible in the FAQ block (customServiceFaqsProvider
      // already merges admin FAQs + answered customer questions).
      final customServiceId = n.entityId!;
      final targetContext = Navigator.of(context).context;
      Navigator.of(context).pop();
      final service = await ref
          .read(catalogServiceProvider)
          .fetchCustomServiceById(customServiceId);
      if (service != null && targetContext.mounted) {
        VendorCustomServiceSheet.show(targetContext, service);
      }
    } else if (n.entityType == 'service_faq' ||
        n.entityType == 'customer_question' ||
        n.notificationType == 'question_answered') {
      final serviceId = n.entityId!;
      final targetContext = Navigator.of(context).context;
      Navigator.of(context).pop();
      final node = await ref.read(catalogServiceProvider).fetchNode(serviceId);
      if (node != null && targetContext.mounted) {
        openCatalogNode(targetContext, node, parentId: n.parentNodeId);
      }
    } else if (n.entityType == 'refund_request') {
      final targetContext = Navigator.of(context).context;
      Navigator.of(context).pop();
      if (targetContext.mounted) {
        PageSheet.show(
          targetContext,
          title: 'Refund Queries',
          child: RefundQueriesFlow(initialRequestId: n.entityId!),
        );
      }
    }
  }

  Future<void> _openRatingModal(NotificationModel n) async {
    if (n.entityId == null) return;
    _markRead(n);
    final parentContext = Navigator.of(context).context;
    Navigator.of(context).pop();
    final booking =
        await ref.read(bookingByIdProvider(n.entityId!).future);
    if (booking == null || !parentContext.mounted) return;
    AppModalDialog.show(
      context: parentContext,
      child: ReviewModal(
          bookingId: booking.id, serviceName: booking.serviceName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notificationsAsync = ref.watch(notificationsProvider);

    return AppModalDialog(
      title: 'Notifications',
      child: notificationsAsync.when(
        loading: () => const SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => const _EmptyState(),
        data: (notifications) {
            final visible = notifications
                .where((n) => !_locallyDeleted.contains(n.id))
                .toList();
            // During a refresh (isAuth false→true), Riverpod calls data: with
            // the stale [] instead of loading:. Treat that as loading.
            if (visible.isEmpty && notificationsAsync.isLoading) {
              return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return visible.isEmpty
                ? const _EmptyState()
                : _NotificationList(
                    notifications: visible,
                    isRead: _isRead,
                    onTap: _handleTap,
                    onRateService: _openRatingModal,
                    onToggleRead: _toggleRead,
                    onDelete: _delete,
                  );
          },
      ),
    );
  }
}

// ── Notification list ─────────────────────────────────────────────────────────

class _NotificationList extends StatelessWidget {
  final List<NotificationModel> notifications;
  final bool Function(NotificationModel) isRead;
  final void Function(NotificationModel) onTap;
  final void Function(NotificationModel)? onRateService;
  final void Function(NotificationModel) onToggleRead;
  final void Function(NotificationModel) onDelete;

  const _NotificationList({
    required this.notifications,
    required this.isRead,
    required this.onTap,
    this.onRateService,
    required this.onToggleRead,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < notifications.length; i++) ...[
          _NotificationTile(
            notification: notifications[i],
            read: isRead(notifications[i]),
            onTap: () => onTap(notifications[i]),
            onRateService: notifications[i].notificationType == 'booking_completed' &&
                    onRateService != null
                ? () => onRateService!(notifications[i])
                : null,
            onToggleRead: () => onToggleRead(notifications[i]),
            onDelete: () => onDelete(notifications[i]),
          ),
          if (i < notifications.length - 1)
            const Divider(height: 1, indent: 16, endIndent: 16),
        ],
      ],
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationModel notification;
  final bool read;
  final VoidCallback onTap;
  final VoidCallback? onRateService;
  final VoidCallback onToggleRead;
  final VoidCallback onDelete;

  const _NotificationTile({
    required this.notification,
    required this.read,
    required this.onTap,
    this.onRateService,
    required this.onToggleRead,
    required this.onDelete,
  });

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final d = notification.createdAt.toLocal();
    final date = '${d.day} ${_months[d.month - 1]} · '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

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
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 10),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: read ? Colors.transparent : AppColors.primary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notification.title,
                          style: tt.bodySmall?.copyWith(
                            fontWeight: read ? FontWeight.w500 : FontWeight.w700,
                            color: read
                                ? AppColors.textSecondary
                                : AppColors.textPrimary,
                          ),
                        ),
                        if (notification.message.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            notification.message,
                            style: tt.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.4,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          date,
                          style: tt.labelSmall?.copyWith(color: AppColors.textHint),
                        ),
                        if (onRateService != null) ...[
                          const SizedBox(height: 8),
                          MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              onTap: onRateService,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: AppColors.gold.withAlpha(20),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: AppColors.gold.withAlpha(100)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.star_rounded,
                                        size: 13, color: AppColors.gold),
                                    SizedBox(width: 4),
                                    Text(
                                      'Rate Service',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.gold,
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
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 10, 8, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SmallAction(
                icon: read
                    ? Icons.mark_email_unread_outlined
                    : Icons.mark_email_read_outlined,
                tooltip: read ? 'Mark unread' : 'Mark read',
                onTap: onToggleRead,
              ),
              const SizedBox(height: 2),
              _SmallAction(
                icon: Icons.delete_outline_rounded,
                tooltip: 'Delete',
                onTap: onDelete,
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

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return SizedBox(
      height: 320,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: AppColors.surfaceVariant,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_off_outlined,
              size: 36,
              color: AppColors.textHint,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No Notifications',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            "You're all caught up!\nWe'll let you know about bookings, offers and more.",
            style: tt.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
