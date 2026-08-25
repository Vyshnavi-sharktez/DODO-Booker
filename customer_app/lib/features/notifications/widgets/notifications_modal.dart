import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_modal_dialog.dart';
import '../../../routes/app_router.dart';
import '../../catalog/providers/catalog_providers.dart';
import '../../catalog/widgets/catalog_service_detail_web_modal.dart';
import '../models/notification_model.dart';
import '../services/notification_providers.dart';

class NotificationsModal extends ConsumerStatefulWidget {
  const NotificationsModal({super.key});

  @override
  ConsumerState<NotificationsModal> createState() =>
      _NotificationsModalState();
}

class _NotificationsModalState extends ConsumerState<NotificationsModal> {
  // Tracks IDs marked read locally so the UI updates instantly.
  final _locallyRead = <String>{};

  @override
  void initState() {
    super.initState();
    debugPrint('[DODO][Notif] modal initState — ${DateTime.now().millisecondsSinceEpoch}ms');
  }

  bool _isRead(NotificationModel n) =>
      n.isRead || _locallyRead.contains(n.id);

  Future<void> _markRead(NotificationModel n) async {
    if (_isRead(n)) return;
    setState(() => _locallyRead.add(n.id));
    try {
      await ref.read(notificationServiceProvider).markAsRead(n.id);
      ref.invalidate(notificationsProvider);
    } catch (_) {
      // Non-fatal — optimistic state already applied.
    }
  }

  Future<void> _handleTap(NotificationModel n) async {
    debugPrint(
        '[NOTIF][Customer] tapped — entity_type=${n.entityType}, entity_id=${n.entityId}, customer_question_id=${n.customerQuestionId}');
    _markRead(n);
    if (n.entityId == null) return;
    if (n.entityType == 'booking') {
      final route =
          AppRoutes.notificationBooking.replaceFirst(':id', n.entityId!);
      debugPrint('[NOTIF][Customer] navigating → $route');
      Navigator.of(context).pop();
      GoRouter.of(context).push(route);
    } else if (n.entityType == 'service_faq' ||
        n.entityType == 'customer_question' ||
        n.notificationType == 'question_answered') {
      final serviceId = n.entityId!;
      final questionId = n.customerQuestionId;
      final targetContext = Navigator.of(context).context;
      Navigator.of(context).pop();
      final node = await ref.read(catalogServiceProvider).fetchNode(serviceId);
      if (node != null && targetContext.mounted) {
        CatalogServiceDetailWebModal.show(
          targetContext,
          node,
          initialCustomerQuestionId: questionId,
        );
      }
    }
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
            // During a refresh (isAuth false→true), Riverpod calls data: with
            // the stale [] instead of loading:. Treat that as loading.
            if (notifications.isEmpty && notificationsAsync.isLoading) {
              return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return notifications.isEmpty
                ? const _EmptyState()
                : _NotificationList(
                    notifications: notifications,
                    isRead: _isRead,
                    onTap: _handleTap,
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

  const _NotificationList({
    required this.notifications,
    required this.isRead,
    required this.onTap,
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

  const _NotificationTile({
    required this.notification,
    required this.read,
    required this.onTap,
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

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state (unchanged) ───────────────────────────────────────────────────

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
