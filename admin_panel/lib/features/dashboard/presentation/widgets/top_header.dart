import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/auth/application/providers/auth_provider.dart';
import '../../../../features/notifications/application/providers/notifications_providers.dart';
import '../../../../features/notifications/domain/models/app_notification.dart';

final _timeFmt = DateFormat('dd MMM, h:mm a');

class TopHeader extends ConsumerWidget {
  const TopHeader({super.key, this.showHamburger = false});

  final bool showHamburger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adminUser = ref.watch(currentAdminUserProvider);
    final title = _resolveTitle(GoRouterState.of(context).matchedLocation);
    final unreadCount = ref.watch(unreadCountProvider);

    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(
        horizontal: showHamburger ? 8 : 24,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          if (showHamburger)
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu_rounded),
                color: AppColors.textPrimary,
                tooltip: 'Open menu',
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),

          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(width: 8),

          _HeaderIconButton(
            icon: Icons.notifications_outlined,
            onTap: () => _openNotificationsPanel(context, ref),
            badgeCount: unreadCount,
          ),
          const SizedBox(width: 8),

          if (adminUser != null)
            _UserChip(
              displayName: adminUser.displayName,
              role: adminUser.primaryRole,
              onLogout: () =>
                  ref.read(authNotifierProvider.notifier).logout(),
            ),
        ],
      ),
    );
  }

  static void _openNotificationsPanel(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      barrierColor: Colors.black12,
      builder: (_) => const _NotificationsPanelDialog(),
    );
  }

  String _resolveTitle(String location) {
    const titles = {
      '/dashboard': 'Dashboard',
      '/dashboard/rbac': 'RBAC & User Management',
      '/dashboard/categories': 'Categories',
      '/dashboard/sub-categories': 'Sub Categories',
      '/dashboard/services': 'Services',
      '/dashboard/vendors': 'Vendors',
      '/dashboard/dodo-teams': 'DODO Teams',
      '/dashboard/bookings': 'Bookings',
      '/dashboard/customers': 'Customers',
      '/dashboard/coupons': 'Coupons & Promotions',
      '/dashboard/vendor-settlement': 'Vendor Settlement',
      '/dashboard/settings': 'Settings',
    };
    return titles[location] ?? 'Admin Panel';
  }
}

// ── Notifications Panel ───────────────────────────────────────────────────────

class _NotificationsPanelDialog extends ConsumerStatefulWidget {
  const _NotificationsPanelDialog();

  @override
  ConsumerState<_NotificationsPanelDialog> createState() =>
      _NotificationsPanelDialogState();
}

class _NotificationsPanelDialogState
    extends ConsumerState<_NotificationsPanelDialog> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsNotifierProvider);

    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 68, right: 12),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 390,
            constraints: const BoxConstraints(maxHeight: 520),
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
                  // ── Header ───────────────────────────────────────────
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
                        state.whenOrNull(
                          data: (items) {
                            final unread =
                                items.where((n) => !n.isRead).toList();
                            if (unread.isEmpty) return null;
                            return TextButton(
                              onPressed: () => ref
                                  .read(notificationsNotifierProvider
                                      .notifier)
                                  .bulkMarkAsRead(
                                      unread.map((n) => n.id).toList()),
                              style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  textStyle: const TextStyle(fontSize: 12)),
                              child: const Text('Mark all read'),
                            );
                          },
                        ) ?? const SizedBox.shrink(),
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

                  // ── Body ─────────────────────────────────────────────
                  Flexible(
                    child: state.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (e, _) => Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            'Failed to load notifications',
                            style: TextStyle(color: AppColors.error),
                          ),
                        ),
                      ),
                      data: (items) {
                        if (items.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 48),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.notifications_none_rounded,
                                      size: 40, color: Color(0xFFCBD5E0)),
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
                        final sorted = [...items]
                          ..sort((a, b) =>
                              (b.createdAt ?? DateTime(0))
                                  .compareTo(a.createdAt ?? DateTime(0)));
                        return ListView.separated(
                          shrinkWrap: true,
                          itemCount: sorted.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final n = sorted[i];
                            return _NotificationTile(
                              notification: n,
                              onToggleRead: () => ref
                                  .read(notificationsNotifierProvider
                                      .notifier)
                                  .toggleRead(n.id,
                                      currentIsRead: n.isRead),
                              onDelete: () => ref
                                  .read(notificationsNotifierProvider
                                      .notifier)
                                  .deleteNotification(n.id),
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

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onToggleRead;
  final VoidCallback onDelete;

  const _NotificationTile({
    required this.notification,
    required this.onToggleRead,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final timeStr =
        n.createdAt != null ? _timeFmt.format(n.createdAt!) : '';

    return Container(
      color: n.isRead
          ? null
          : const Color(0xFF3182CE).withValues(alpha: 0.04),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Unread dot / spacer
          Padding(
            padding: const EdgeInsets.only(top: 5, right: 10),
            child: n.isRead
                ? const SizedBox(width: 7)
                : Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF3182CE),
                      shape: BoxShape.circle,
                    ),
                  ),
          ),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  n.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        n.isRead ? FontWeight.w400 : FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  n.message,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (timeStr.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    timeStr,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: 4),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: onToggleRead,
                icon: Icon(
                  n.isRead
                      ? Icons.mark_email_unread_rounded
                      : Icons.mark_email_read_rounded,
                  size: 15,
                  color: n.isRead
                      ? AppColors.textSecondary
                      : const Color(0xFF3182CE),
                ),
                tooltip: n.isRead ? 'Mark unread' : 'Mark read',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              IconButton(
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline_rounded,
                    size: 15, color: AppColors.error),
                tooltip: 'Delete',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Header icon button ────────────────────────────────────────────────────────

class _HeaderIconButton extends StatefulWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
  });
  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  State<_HeaderIconButton> createState() => _HeaderIconButtonState();
}

class _HeaderIconButtonState extends State<_HeaderIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _hovered
                    ? AppColors.border
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                widget.icon,
                size: 22,
                color: AppColors.textSecondary,
              ),
            ),
            if (widget.badgeCount > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${widget.badgeCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── User chip ─────────────────────────────────────────────────────────────────

class _UserChip extends StatefulWidget {
  const _UserChip({
    required this.displayName,
    required this.role,
    required this.onLogout,
  });
  final String displayName;
  final String role;
  final VoidCallback onLogout;

  @override
  State<_UserChip> createState() => _UserChipState();
}

class _UserChipState extends State<_UserChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'logout') widget.onLogout();
        },
        offset: const Offset(0, 44),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        itemBuilder: (context) => [
          PopupMenuItem(
            enabled: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                ),
                Text(
                  widget.role,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'logout',
            child: Row(
              children: [
                Icon(Icons.logout_rounded,
                    size: 16, color: AppColors.error),
                SizedBox(width: 8),
                Text(
                  'Sign Out',
                  style: TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.border : AppColors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor:
                    AppColors.primary.withValues(alpha: 0.12),
                child: Text(
                  widget.displayName.isNotEmpty
                      ? widget.displayName[0].toUpperCase()
                      : 'A',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.displayName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Text(
                      widget.role,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.expand_more_rounded,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
