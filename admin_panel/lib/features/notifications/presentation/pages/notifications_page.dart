import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/notifications_providers.dart';
import '../../domain/models/app_notification.dart';
import '../widgets/notification_form_dialog.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

final _dateFmtShort = DateFormat('dd MMM yyyy');

const _typeColors = <String, Color>{
  'booking': Color(0xFF3182CE),
  'payment': Color(0xFF38A169),
  'system': Color(0xFF718096),
  'promotion': Color(0xFFDD6B20),
  'reminder': Color(0xFF805AD5),
  'vendor_started': Color(0xFF2C7A7B),
  'vendor_rejected': Color(0xFFC53030),
};

const _userTypeColors = <String, Color>{
  'customer': Color(0xFF3182CE),
  'vendor': Color(0xFF38A169),
  'admin': Color(0xFF805AD5),
};

// ── Read filter enum ──────────────────────────────────────────────────────────

enum _ReadFilter { all, unread, read }

// ── Page ──────────────────────────────────────────────────────────────────────

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() =>
      _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  _ReadFilter _readFilter = _ReadFilter.all;
  String? _userTypeFilter;
  String? _typeFilter;
  final Set<String> _selectedIds = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Filtering ──────────────────────────────────────────────────────────────

  List<AppNotification> _applyFilters(List<AppNotification> all) {
    var result = all;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where((n) =>
              n.title.toLowerCase().contains(q) ||
              n.message.toLowerCase().contains(q))
          .toList();
    }
    switch (_readFilter) {
      case _ReadFilter.read:
        result = result.where((n) => n.isRead).toList();
      case _ReadFilter.unread:
        result = result.where((n) => !n.isRead).toList();
      case _ReadFilter.all:
        break;
    }
    if (_userTypeFilter != null) {
      result =
          result.where((n) => n.userType == _userTypeFilter).toList();
    }
    if (_typeFilter != null) {
      result = result
          .where((n) => n.notificationType == _typeFilter)
          .toList();
    }
    return result;
  }

  bool get _hasFilters =>
      _readFilter != _ReadFilter.all ||
      _userTypeFilter != null ||
      _typeFilter != null;

  List<String> _uniqueUserTypes(List<AppNotification> items) {
    return items
        .map((n) => n.userType)
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  List<String> _uniqueNotifTypes(List<AppNotification> items) {
    return items
        .map((n) => n.notificationType)
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void _openCreate() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => NotificationFormDialog(
        onSave: ({
          required userType,
          required userId,
          required title,
          required message,
          required notificationType,
        }) async {
          await ref
              .read(notificationsNotifierProvider.notifier)
              .createNotification(
                userType: userType,
                userId: userId,
                title: title,
                message: message,
                notificationType: notificationType,
              );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Notification sent successfully')),
            );
          }
        },
      ),
    );
  }

  Future<void> _toggleRead(AppNotification n) async {
    try {
      await ref
          .read(notificationsNotifierProvider.notifier)
          .toggleRead(n.id, currentIsRead: n.isRead);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Update failed: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _confirmDelete(AppNotification n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Notification'),
        content: Text(
            'Delete "${n.title}"?\n\nThis action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(notificationsNotifierProvider.notifier)
          .deleteNotification(n.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Delete failed: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _bulkMarkRead() async {
    final ids = _selectedIds.toList();
    try {
      await ref
          .read(notificationsNotifierProvider.notifier)
          .bulkMarkAsRead(ids);
      setState(() => _selectedIds.clear());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${ids.length} notification${ids.length == 1 ? '' : 's'} marked as read')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _handleNavigate(AppNotification n) {
    debugPrint('[NOTIF][Admin] tapped — entity_type=${n.entityType}, entity_id=${n.entityId}');
    if (n.entityType == 'booking' && n.entityId != null) {
      if (!n.isRead) _toggleRead(n);
      final route = '/dashboard/vendor-assignment?bookingId=${n.entityId}';
      debugPrint('[NOTIF][Admin] navigating → $route');
      context.go(route);
    }
  }

  Future<void> _bulkDelete() async {
    final ids = _selectedIds.toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Selected'),
        content: Text(
            'Delete ${ids.length} notification${ids.length == 1 ? '' : 's'}?\n\nThis action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(notificationsNotifierProvider.notifier)
          .bulkDelete(ids);
      setState(() => _selectedIds.clear());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${ids.length} notification${ids.length == 1 ? '' : 's'} deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsNotifierProvider);
    final unread = ref.watch(unreadCountProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Responsive Header ─────────────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 600;
              return Flex(
                direction: narrow ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: narrow
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Notifications',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (!state.isLoading && unread > 0) ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3182CE),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$unread unread',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Manage platform notifications',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  if (narrow) const SizedBox(height: 12) else const Spacer(),
                  FilledButton.icon(
                    onPressed: _openCreate,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('New Notification'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),

          // ── Bulk action bar ────────────────────────────────────────────────
          if (_selectedIds.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_box_rounded,
                          size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        '${_selectedIds.length} selected',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  OutlinedButton.icon(
                    onPressed: _bulkMarkRead,
                    icon: const Icon(Icons.mark_email_read_rounded,
                        size: 15),
                    label: const Text('Mark as Read'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _bulkDelete,
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 15, color: AppColors.error),
                    label: Text('Delete',
                        style: TextStyle(color: AppColors.error)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      side: BorderSide(
                          color: AppColors.error.withValues(alpha: 0.4)),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _selectedIds.clear()),
                    child: Text(
                      'Clear',
                      style:
                          TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),

          // ── Search + Filters ──────────────────────────────────────────────
          state.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
            data: (all) => Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search title or message…',
                      prefixIcon: const Icon(Icons.search_rounded,
                          size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded,
                                  size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    onChanged: (v) =>
                        setState(() => _searchQuery = v.trim()),
                  ),
                ),
                // Read filter chips
                _Chip(
                  label: 'All',
                  selected: _readFilter == _ReadFilter.all,
                  onTap: () =>
                      setState(() => _readFilter = _ReadFilter.all),
                ),
                _Chip(
                  label: 'Unread',
                  selected: _readFilter == _ReadFilter.unread,
                  color: const Color(0xFF3182CE),
                  onTap: () =>
                      setState(() => _readFilter = _ReadFilter.unread),
                ),
                _Chip(
                  label: 'Read',
                  selected: _readFilter == _ReadFilter.read,
                  color: const Color(0xFF718096),
                  onTap: () =>
                      setState(() => _readFilter = _ReadFilter.read),
                ),
                // User type filter
                if (_uniqueUserTypes(all).isNotEmpty)
                  SizedBox(
                    width: 150,
                    child: DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: _userTypeFilter,
                      decoration: const InputDecoration(
                        hintText: 'User Type',
                        prefixIcon:
                            Icon(Icons.person_rounded, size: 18),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('User Type')),
                        ..._uniqueUserTypes(all).map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(t[0].toUpperCase() +
                                t.substring(1)),
                          ),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _userTypeFilter = v),
                    ),
                  ),
                // Notification type filter
                if (_uniqueNotifTypes(all).isNotEmpty)
                  SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: _typeFilter,
                      decoration: const InputDecoration(
                        hintText: 'Notif. Type',
                        prefixIcon:
                            Icon(Icons.category_rounded, size: 18),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('Notif. Type')),
                        ..._uniqueNotifTypes(all).map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(t[0].toUpperCase() +
                                t.substring(1)),
                          ),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _typeFilter = v),
                    ),
                  ),
                if (_hasFilters)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _readFilter = _ReadFilter.all;
                      _userTypeFilter = null;
                      _typeFilter = null;
                    }),
                    icon: const Icon(Icons.filter_alt_off_rounded,
                        size: 16),
                    label: const Text('Clear'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Body ──────────────────────────────────────────────────────────
          Expanded(
            child: state.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 48, color: AppColors.error),
                    const SizedBox(height: 12),
                    Text('Failed to load notifications',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(e.toString(),
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => ref
                          .read(notificationsNotifierProvider.notifier)
                          .refresh(),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (all) {
                final filtered = _applyFilters(all);
                if (all.isEmpty) {
                  return _EmptyState(
                    message: 'No notifications yet',
                    sub: 'Click "New Notification" to send the first one.',
                    onAdd: _openCreate,
                  );
                }
                if (filtered.isEmpty) {
                  return const _EmptyState(
                    message: 'No notifications match your filters',
                    sub: 'Try adjusting your search or filters.',
                  );
                }
                return _NotificationsTable(
                  notifications: filtered,
                  totalCount: all.length,
                  selectedIds: _selectedIds,
                  onSelectionChanged: (id, selected) {
                    setState(() {
                      if (selected) {
                        _selectedIds.add(id);
                      } else {
                        _selectedIds.remove(id);
                      }
                    });
                  },
                  onSelectAll: (selectAll) {
                    setState(() {
                      if (selectAll) {
                        _selectedIds
                            .addAll(filtered.map((n) => n.id));
                      } else {
                        _selectedIds.removeAll(
                            filtered.map((n) => n.id));
                      }
                    });
                  },
                  onToggleRead: _toggleRead,
                  onDelete: _confirmDelete,
                  onNavigate: _handleNavigate,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Filter chip ────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    this.color = const Color(0xFF4A90D9),
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.12)
              : AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.5)
                : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? color : AppColors.textSecondary,
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ── Table ──────────────────────────────────────────────────────────────────────

class _NotificationsTable extends StatelessWidget {
  final List<AppNotification> notifications;
  final int totalCount;
  final Set<String> selectedIds;
  final void Function(String id, bool selected) onSelectionChanged;
  final void Function(bool selectAll) onSelectAll;
  final void Function(AppNotification) onToggleRead;
  final void Function(AppNotification) onDelete;
  final void Function(AppNotification) onNavigate;

  const _NotificationsTable({
    required this.notifications,
    required this.totalCount,
    required this.selectedIds,
    required this.onSelectionChanged,
    required this.onSelectAll,
    required this.onToggleRead,
    required this.onDelete,
    required this.onNavigate,
  });

  static const double _minTableWidth = 750;

  @override
  Widget build(BuildContext context) {
    final allSelected = notifications.isNotEmpty &&
        notifications.every((n) => selectedIds.contains(n.id));
    final someSelected = !allSelected &&
        notifications.any((n) => selectedIds.contains(n.id));

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tableWidth = constraints.maxWidth < _minTableWidth
                      ? _minTableWidth
                      : constraints.maxWidth;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            color: AppColors.background,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 40,
                                  child: Checkbox(
                                    value: allSelected
                                        ? true
                                        : (someSelected ? null : false),
                                    tristate: true,
                                    onChanged: (v) =>
                                        onSelectAll(v ?? false),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                                const _HCell('Title / Message', flex: 4),
                                const _HCell('User Type', flex: 2),
                                const _HCell('User ID', flex: 2),
                                const _HCell('Type', flex: 2),
                                const _HCell('Status', flex: 1),
                                const _HCell('Created', flex: 2),
                                const _HCell('Actions', flex: 2,
                                    align: TextAlign.center),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: ListView.separated(
                              itemCount: notifications.length,
                              separatorBuilder: (_, idx) =>
                                  const Divider(height: 1),
                              itemBuilder: (ctx, i) {
                                final n = notifications[i];
                                return _NotificationRow(
                                  notification: n,
                                  isSelected: selectedIds.contains(n.id),
                                  onSelectionChanged: (v) =>
                                      onSelectionChanged(n.id, v),
                                  onToggleRead: () => onToggleRead(n),
                                  onDelete: () => onDelete(n),
                                  onNavigate: () => onNavigate(n),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              color: AppColors.background,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              child: Text(
                notifications.length == totalCount
                    ? '${notifications.length} notification${notifications.length == 1 ? '' : 's'}'
                    : '${notifications.length} of $totalCount notification${totalCount == 1 ? '' : 's'}',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HCell extends StatelessWidget {
  final String label;
  final int flex;
  final TextAlign align;

  const _HCell(this.label,
      {required this.flex, this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: align,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  final AppNotification notification;
  final bool isSelected;
  final void Function(bool) onSelectionChanged;
  final VoidCallback onToggleRead;
  final VoidCallback onDelete;
  final VoidCallback onNavigate;

  const _NotificationRow({
    required this.notification,
    required this.isSelected,
    required this.onSelectionChanged,
    required this.onToggleRead,
    required this.onDelete,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final typeColor =
        _typeColors[n.notificationType] ?? const Color(0xFF718096);
    final userTypeColor =
        _userTypeColors[n.userType] ?? const Color(0xFF718096);
    final createdStr =
        n.createdAt != null ? _dateFmtShort.format(n.createdAt!) : '—';

    return Container(
      color: isSelected
          ? AppColors.primary.withValues(alpha: 0.04)
          : (!n.isRead ? const Color(0xFF3182CE).withValues(alpha: 0.03) : null),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Checkbox
          SizedBox(
            width: 40,
            child: Checkbox(
              value: isSelected,
              onChanged: (v) => onSelectionChanged(v ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),

          // Title + Message
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (!n.isRead)
                      Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.only(right: 6, top: 2),
                        decoration: const BoxDecoration(
                          color: Color(0xFF3182CE),
                          shape: BoxShape.circle,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        n.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: n.isRead
                              ? FontWeight.w400
                              : FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  n.message,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // User Type
          Expanded(
            flex: 2,
            child: _TypeBadge(
              label: n.userType.isEmpty
                  ? '—'
                  : n.userType[0].toUpperCase() + n.userType.substring(1),
              color: userTypeColor,
            ),
          ),

          // User ID
          Expanded(
            flex: 2,
            child: Tooltip(
              message: n.userId,
              child: Text(
                n.userId.length > 12
                    ? '${n.userId.substring(0, 12)}…'
                    : n.userId,
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          // Notification Type
          Expanded(
            flex: 2,
            child: _TypeBadge(
              label: n.notificationType.isEmpty
                  ? '—'
                  : n.notificationType[0].toUpperCase() +
                      n.notificationType.substring(1),
              color: typeColor,
            ),
          ),

          // Read status
          Expanded(
            flex: 1,
            child: n.isRead
                ? Text(
                    'Read',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3182CE)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Unread',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF3182CE),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          ),

          // Created At
          Expanded(
            flex: 2,
            child: Text(
              createdStr,
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
          ),

          // Actions
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (n.entityType == 'booking' && n.entityId != null)
                  IconButton(
                    onPressed: onNavigate,
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    tooltip: 'View Booking',
                    color: AppColors.primary,
                    visualDensity: VisualDensity.compact,
                  ),
                Tooltip(
                  message: n.isRead ? 'Mark as Unread' : 'Mark as Read',
                  child: IconButton(
                    onPressed: onToggleRead,
                    icon: Icon(
                      n.isRead
                          ? Icons.mark_email_unread_rounded
                          : Icons.mark_email_read_rounded,
                      size: 16,
                      color: n.isRead
                          ? AppColors.textSecondary
                          : const Color(0xFF3182CE),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 16, color: AppColors.error),
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _TypeBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String message;
  final String sub;
  final VoidCallback? onAdd;

  const _EmptyState({
    required this.message,
    required this.sub,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 56,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(sub,
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
          if (onAdd != null) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('New Notification'),
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary),
            ),
          ],
        ],
      ),
    );
  }
}
