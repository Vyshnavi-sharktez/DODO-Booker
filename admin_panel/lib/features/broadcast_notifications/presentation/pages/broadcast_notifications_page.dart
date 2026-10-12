import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/broadcast_notifications_providers.dart';
import '../../domain/models/broadcast_notification.dart';
import '../widgets/create_broadcast_dialog.dart';

// ── Tab definition ────────────────────────────────────────────────────────────

enum _NotifTab { all, sent, scheduled, drafts }

extension _TabLabel on _NotifTab {
  String get label => switch (this) {
        _NotifTab.all => 'All',
        _NotifTab.sent => 'Sent',
        _NotifTab.scheduled => 'Scheduled',
        _NotifTab.drafts => 'Drafts',
      };
}

// ── Page ──────────────────────────────────────────────────────────────────────

class BroadcastNotificationsPage extends ConsumerStatefulWidget {
  const BroadcastNotificationsPage({super.key});

  @override
  ConsumerState<BroadcastNotificationsPage> createState() =>
      _BroadcastNotificationsPageState();
}

class _BroadcastNotificationsPageState
    extends ConsumerState<BroadcastNotificationsPage> {
  _NotifTab _tab = _NotifTab.all;

  List<BroadcastNotification> _filtered(List<BroadcastNotification> all) {
    return switch (_tab) {
      _NotifTab.all => all,
      _NotifTab.sent => all.where((b) => b.status == 'sent').toList(),
      _NotifTab.scheduled =>
        all.where((b) => b.status == 'scheduled').toList(),
      _NotifTab.drafts => all.where((b) => b.status == 'draft').toList(),
    };
  }

  Future<void> _openCreateDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CreateBroadcastDialog(),
    );
  }

  Future<void> _confirmDelete(BroadcastNotification b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Notification?'),
        content: Text(
          'Delete "${b.title}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      try {
        await ref
            .read(broadcastNotificationsNotifierProvider.notifier)
            .deleteBroadcast(b.id);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Delete failed: $e'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _sendNow(BroadcastNotification b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send Now?'),
        content: Text(
          'Send "${b.title}" to ${_audienceLabel(b.audience)} immediately?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      try {
        final count = await ref
            .read(broadcastNotificationsNotifierProvider.notifier)
            .sendBroadcast(b.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Sent to $count recipient${count == 1 ? '' : 's'}.'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              width: 360,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Send failed: $e'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(broadcastNotificationsNotifierProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          _buildTabBar(),
          const SizedBox(height: 16),
          state.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => _ErrorCard(
              error: e.toString(),
              onRetry: () => ref
                  .read(broadcastNotificationsNotifierProvider.notifier)
                  .refresh(),
            ),
            data: (all) {
              final items = _filtered(all);
              if (items.isEmpty) return _buildEmpty();
              return _buildList(items);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.campaign_rounded,
            color: AppColors.primary,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Notifications',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                'Send and manage customer & vendor notifications',
                style: TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: _openCreateDialog,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Create Notification'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _NotifTab.values
            .map((tab) => _TabItem(
                  label: tab.label,
                  selected: _tab == tab,
                  onTap: () => setState(() => _tab = tab),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildEmpty() {
    final msg = switch (_tab) {
      _NotifTab.all => 'No notifications yet.',
      _NotifTab.sent => 'No sent notifications.',
      _NotifTab.scheduled => 'No scheduled notifications.',
      _NotifTab.drafts => 'No drafts.',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.border,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.campaign_rounded,
                size: 28, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          Text(
            msg,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          if (_tab == _NotifTab.all) ...[
            const SizedBox(height: 6),
            const Text(
              'Create a notification to start reaching your users.',
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _openCreateDialog,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Create Notification'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildList(List<BroadcastNotification> items) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _buildTableHeader(),
          const Divider(height: 1, color: AppColors.border),
          for (int i = 0; i < items.length; i++) ...[
            _BroadcastRow(
              broadcast: items[i],
              onSend: () => _sendNow(items[i]),
              onDelete: () => _confirmDelete(items[i]),
            ),
            if (i < items.length - 1)
              const Divider(height: 1, color: AppColors.border),
          ],
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: const [
          Expanded(
            flex: 4,
            child: Text(
              'NOTIFICATION',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.6,
              ),
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text(
              'AUDIENCE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.6,
              ),
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: Text(
              'STATUS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.6,
              ),
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            width: 130,
            child: Text(
              'SENT / SCHEDULED',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.6,
              ),
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: Text(
              'ACTIONS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── _BroadcastRow ─────────────────────────────────────────────────────────────

class _BroadcastRow extends StatelessWidget {
  const _BroadcastRow({
    required this.broadcast,
    required this.onSend,
    required this.onDelete,
  });
  final BroadcastNotification broadcast;
  final VoidCallback onSend;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final b = broadcast;
    final canSend = b.status == 'draft' || b.status == 'scheduled';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Notification info ──────────────────────────────────────────────
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  b.message,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                _TypeBadge(type: b.notificationType),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // ── Audience ───────────────────────────────────────────────────────
          SizedBox(
            width: 100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _audienceLabel(b.audience),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (b.targetingType != 'all') ...[
                  const SizedBox(height: 2),
                  Text(
                    b.targetingLabel ?? _targetingTypeLabel(b.targetingType),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          // ── Status ─────────────────────────────────────────────────────────
          SizedBox(
            width: 90,
            child: _StatusBadge(status: b.status),
          ),
          const SizedBox(width: 12),
          // ── Time ───────────────────────────────────────────────────────────
          SizedBox(
            width: 130,
            child: _TimeCell(broadcast: b),
          ),
          const SizedBox(width: 12),
          // ── Actions ────────────────────────────────────────────────────────
          SizedBox(
            width: 80,
            child: Row(
              children: [
                if (canSend)
                  Tooltip(
                    message: 'Send now',
                    child: IconButton(
                      onPressed: onSend,
                      icon: const Icon(Icons.send_rounded),
                      iconSize: 16,
                      color: AppColors.primary,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                Tooltip(
                  message: 'Delete',
                  child: IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    iconSize: 16,
                    color: AppColors.error,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _audienceLabel(String audience) => switch (audience) {
      'customers' => 'Customers',
      'vendors' => 'Vendors',
      'both' => 'Both',
      _ => audience,
    };

String _targetingTypeLabel(String type) => switch (type) {
      'serving_area' => 'By Serving Area',
      'booked_service' => 'By Service',
      'booked_category' => 'By Category',
      _ => 'All',
    };

// ── _StatusBadge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (status) {
      'sent' => (AppColors.success, Icons.check_circle_rounded, 'Sent'),
      'scheduled' => (AppColors.warning, Icons.schedule_rounded, 'Scheduled'),
      'sending' => (AppColors.accent, Icons.send_rounded, 'Sending'),
      'failed' => (AppColors.error, Icons.error_rounded, 'Failed'),
      _ => (AppColors.textSecondary, Icons.drafts_rounded, 'Draft'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── _TypeBadge ────────────────────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final label = switch (type) {
      'offer' => 'Offer',
      'new_service' => 'New Service',
      'announcement' => 'Announcement',
      'custom' => 'Custom',
      _ => type,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: AppColors.accent,
        ),
      ),
    );
  }
}

// ── _TimeCell ─────────────────────────────────────────────────────────────────

class _TimeCell extends StatelessWidget {
  const _TimeCell({required this.broadcast});
  final BroadcastNotification broadcast;

  @override
  Widget build(BuildContext context) {
    final b = broadcast;
    if (b.status == 'sent' && b.sentAt != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('dd MMM yyyy').format(b.sentAt!.toLocal()),
            style: const TextStyle(
                fontSize: 12, color: AppColors.textPrimary),
          ),
          Text(
            DateFormat('hh:mm a').format(b.sentAt!.toLocal()),
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary),
          ),
          if (b.recipientCount > 0)
            Text(
              '${b.recipientCount} recipient${b.recipientCount == 1 ? '' : 's'}',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
        ],
      );
    }
    if (b.status == 'scheduled' && b.scheduledAt != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('dd MMM yyyy').format(b.scheduledAt!.toLocal()),
            style: const TextStyle(
                fontSize: 12, color: AppColors.textPrimary),
          ),
          Text(
            DateFormat('hh:mm a').format(b.scheduledAt!.toLocal()),
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      );
    }
    if (b.createdAt != null) {
      return Text(
        DateFormat('dd MMM yyyy').format(b.createdAt!.toLocal()),
        style: const TextStyle(
            fontSize: 12, color: AppColors.textSecondary),
      );
    }
    return const Text(
      '—',
      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
    );
  }
}

// ── _TabItem ──────────────────────────────────────────────────────────────────

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ── _ErrorCard ────────────────────────────────────────────────────────────────

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.error_outline_rounded,
                size: 24, color: AppColors.error),
          ),
          const SizedBox(height: 16),
          const Text(
            'Failed to load notifications',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            error,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
