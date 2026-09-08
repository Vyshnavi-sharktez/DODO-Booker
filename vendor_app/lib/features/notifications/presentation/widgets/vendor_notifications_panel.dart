import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/routes/route_names.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../providers/notifications_provider.dart';
import 'notification_tile.dart';

class VendorNotificationsPanelDialog extends ConsumerStatefulWidget {
  const VendorNotificationsPanelDialog({super.key});

  @override
  ConsumerState<VendorNotificationsPanelDialog> createState() =>
      _VendorNotificationsPanelDialogState();
}

class _VendorNotificationsPanelDialogState
    extends ConsumerState<VendorNotificationsPanelDialog> {
  final _locallyRead = <String>{};

  bool _isRead(VendorNotification n) =>
      n.isRead || _locallyRead.contains(n.id);

  Future<void> _markRead(VendorNotification n) async {
    if (_isRead(n)) return;
    setState(() => _locallyRead.add(n.id));
    try {
      await ref.read(notificationsRepositoryProvider).markAsRead(n.id);
      ref.invalidate(vendorNotificationsProvider);
    } catch (_) {}
  }

  Future<void> _markAllRead(List<VendorNotification> notifications) async {
    final user = ref.read(currentVendorUserProvider);
    if (user == null) return;
    final unreadIds =
        notifications.where((n) => !_isRead(n)).map((n) => n.id).toSet();
    if (unreadIds.isEmpty) return;
    setState(() => _locallyRead.addAll(unreadIds));
    try {
      await ref
          .read(notificationsRepositoryProvider)
          .markAllAsRead(user.id);
      ref.invalidate(vendorNotificationsProvider);
    } catch (_) {}
  }

  void _handleTap(VendorNotification n) {
    _markRead(n);
    final router = GoRouter.of(context);

    if ((n.entityType == 'booking' ||
            n.notificationType == 'vendor_assigned' ||
            n.notificationType == 'new_dispatch_offer' ||
            n.notificationType == 'vendor_reassigned') &&
        n.entityId != null) {
      Navigator.of(context).pop();
      router.pushNamed(
        RouteNames.bookingDetail,
        pathParameters: {'id': n.entityId!},
      );
    } else if (n.entityType == 'vendor_wallet' ||
        n.entityType == 'wallet' ||
        n.notificationType == 'wallet_low_balance' ||
        n.notificationType == 'wallet_alert' ||
        n.notificationType == 'wallet_penalty') {
      Navigator.of(context).pop();
      router.pushNamed(RouteNames.wallet);
    } else if (n.entityType == 'vendor_service_request' ||
        n.notificationType == 'vendor_service_request') {
      Navigator.of(context).pop();
      router.pushNamed(
        RouteNames.services,
        queryParameters: {'tab': '2'},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final notificationsAsync = ref.watch(vendorNotificationsProvider);

    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 68, right: 12),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 390, maxHeight: 520),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Header ───────────────────────────────────────────────
                  Container(
                    color: AppColors.background,
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    child: Row(
                      children: [
                        const Icon(Icons.notifications_rounded,
                            size: 18, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        const Text(
                          'Notifications',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        notificationsAsync.whenOrNull(
                          data: (items) {
                            final hasUnread = items.any((n) => !_isRead(n));
                            if (!hasUnread) return null;
                            return TextButton(
                              onPressed: () => _markAllRead(items),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                textStyle: const TextStyle(fontSize: 12),
                              ),
                              child: const Text('Mark all read'),
                            );
                          },
                        ) ??
                            const SizedBox.shrink(),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          visualDensity: VisualDensity.compact,
                          color: AppColors.textSecondary,
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // ── Body ─────────────────────────────────────────────────
                  Flexible(
                    child: notificationsAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (e, _) => const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            'Failed to load notifications',
                            style: TextStyle(color: AppColors.error),
                          ),
                        ),
                      ),
                      data: (notifications) {
                        if (notifications.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 48),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.notifications_none_rounded,
                                      size: 40, color: AppColors.textHint),
                                  SizedBox(height: 10),
                                  Text(
                                    'No notifications',
                                    style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        return ListView.separated(
                          shrinkWrap: true,
                          itemCount: notifications.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final n = notifications[i];
                            return NotificationTile(
                              notification: n,
                              isRead: _isRead(n),
                              onTap: () => _handleTap(n),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
