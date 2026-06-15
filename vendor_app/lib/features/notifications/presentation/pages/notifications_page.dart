import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/widgets/vendor_scaffold.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../providers/notifications_provider.dart';
import '../widgets/notification_tile.dart';
import '../../domain/models/vendor_notification.dart';

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  // Tracks IDs marked read locally so the UI responds instantly before the
  // provider refresh completes.
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

  void _handleTap(VendorNotification n) {
    debugPrint('[NOTIF][Vendor] tapped — entity_type=${n.entityType}, entity_id=${n.entityId}');
    _markRead(n);
    if (n.entityType == 'booking' && n.entityId != null) {
      final router = GoRouter.of(context);
      debugPrint('[NOTIF][Vendor] navigating → ${RouteNames.bookingDetail} id=${n.entityId}');
      router.goNamed(
        RouteNames.bookingDetail,
        pathParameters: {'id': n.entityId!},
      );
    }
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

  @override
  Widget build(BuildContext context) {
    final notificationsAsync = ref.watch(vendorNotificationsProvider);

    return VendorScaffold(
      title: 'Notifications',
      child: notificationsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(
          onRetry: () => ref.invalidate(vendorNotificationsProvider),
        ),
        data: (notifications) {
          final hasUnread = notifications.any((n) => !_isRead(n));
          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(vendorNotificationsProvider),
            child: CustomScrollView(
              slivers: [
                if (hasUnread)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => _markAllRead(notifications),
                          child: const Text('Mark all as read'),
                        ),
                      ),
                    ),
                  ),
                if (notifications.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final n = notifications[i];
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            NotificationTile(
                              notification: n,
                              isRead: _isRead(n),
                              onTap: () => _handleTap(n),
                            ),
                            if (i < notifications.length - 1)
                              const Divider(
                                height: 1,
                                indent: 68,
                                endIndent: 16,
                              ),
                          ],
                        );
                      },
                      childCount: notifications.length,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: const BoxDecoration(
            color: AppColors.background,
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
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          "You're all caught up!\nBooking events will appear here.",
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 48, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text(
              'Failed to load notifications',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
