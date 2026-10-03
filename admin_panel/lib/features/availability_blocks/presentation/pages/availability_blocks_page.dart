import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/availability_block_providers.dart';
import '../../domain/models/availability_block.dart';
import '../widgets/availability_block_dialog.dart';

class AvailabilityBlocksPage extends ConsumerWidget {
  const AvailabilityBlocksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(availabilityBlocksNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Error: $e',
              style: const TextStyle(color: AppColors.error)),
        ),
        data: (blocks) => _BlocksBody(blocks: blocks),
      ),
    );
  }
}

class _BlocksBody extends ConsumerWidget {
  const _BlocksBody({required this.blocks});
  final List<AvailabilityBlock> blocks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(availabilityBlocksNotifierProvider.notifier);

    Future<void> openDialog([AvailabilityBlock? existing]) async {
      final result = await showDialog<AvailabilityBlock>(
        context: context,
        builder: (_) => AvailabilityBlockDialog(existing: existing),
      );
      if (result == null) return;
      try {
        if (existing == null) {
          await notifier.create(result);
        } else {
          await notifier.update(result);
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(existing == null ? 'Block created.' : 'Block updated.'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    }

    Future<void> confirmDelete(AvailabilityBlock block) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete Block?'),
          content: const Text(
              'This availability block will be permanently removed.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      try {
        await notifier.delete(block.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Block deleted.'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Availability Blocks',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Temporarily pause slots for specific dates without modifying schedules.',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => openDialog(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New Block'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size(0, 40),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Info banner ──────────────────────────────────────────────────
            _InfoBanner(),
            const SizedBox(height: 20),

            // ── List ─────────────────────────────────────────────────────────
            if (blocks.isEmpty)
              _EmptyState(onAdd: () => openDialog())
            else
              ...blocks.map(
                (b) => _BlockTile(
                  block: b,
                  onEdit: () => openDialog(b),
                  onDelete: () => confirmDelete(b),
                  onToggle: (enabled) => notifier.setEnabled(b.id,
                      enabled: enabled),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  color: AppColors.primary, size: 15),
              SizedBox(width: 8),
              Text(
                'How availability blocks work',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
              ),
            ],
          ),
          SizedBox(height: 8),
          _Bullet(
              'Blocks are a temporary overlay — existing schedules are never modified.'),
          SizedBox(height: 4),
          _Bullet(
              'Full-day blocks hide all slots for the covered dates.'),
          SizedBox(height: 4),
          _Bullet(
              'Partial-day blocks hide only the listed slots; other slots remain visible.'),
          SizedBox(height: 4),
          _Bullet(
              'Category blocks apply to every service that is a descendant of that category.'),
          SizedBox(height: 4),
          _Bullet(
              'Disabling a block keeps it saved but stops it from affecting slots immediately.'),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Icon(Icons.circle, size: 5, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.5),
            ),
          ),
        ],
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 48),
        alignment: Alignment.center,
        child: Column(
          children: [
            const Icon(Icons.block_rounded,
                size: 40, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            const Text(
              'No availability blocks',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            const Text(
              'Create a block to pause slots for a date range.',
              style:
                  TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('New Block'),
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size(0, 38)),
            ),
          ],
        ),
      );
}

class _BlockTile extends ConsumerWidget {
  const _BlockTile({
    required this.block,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  final AvailabilityBlock block;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;

  static const _scopeColors = {
    'global': Color(0xFF7C3AED),
    'category': Color(0xFF2563EB),
    'service': Color(0xFF0891B2),
    'vendor': Color(0xFFD97706),
  };

  static const _scopeIcons = {
    'global': Icons.public_rounded,
    'category': Icons.folder_rounded,
    'service': Icons.miscellaneous_services_rounded,
    'vendor': Icons.person_rounded,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _scopeColors[block.scope] ?? AppColors.textSecondary;
    final icon = _scopeIcons[block.scope] ?? Icons.block_rounded;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isActive = block.isEnabled &&
        !block.startDate.isAfter(today) &&
        !block.endDate.isBefore(today);
    final isPast = block.endDate.isBefore(today);

    final startStr = _fmtDate(block.startDate);
    final endStr = _fmtDate(block.endDate);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? AppColors.error.withValues(alpha: 0.4)
              : AppColors.border,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Scope icon ───────────────────────────────────────────────────
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 14),

          // ── Info ─────────────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _ScopeChip(scope: block.scope, color: color),
                    const SizedBox(width: 8),
                    if (isActive)
                      _StatusChip(
                          label: 'Active Now',
                          color: AppColors.error)
                    else if (isPast)
                      _StatusChip(
                          label: 'Expired',
                          color: AppColors.textSecondary)
                    else if (!block.isEnabled)
                      _StatusChip(
                          label: 'Disabled',
                          color: AppColors.textSecondary),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '$startStr → $endStr',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  block.isFullDay
                      ? 'Full-day block'
                      : 'Partial-day: ${block.blockedSlots!.join(', ')}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                if (block.reason != null && block.reason!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    block.reason!,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),

          // ── Actions ──────────────────────────────────────────────────────
          Column(
            children: [
              Switch(
                value: block.isEnabled,
                onChanged: onToggle,
                activeThumbColor: AppColors.success,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_rounded,
                        size: 16, color: AppColors.textSecondary),
                    tooltip: 'Edit',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: onDelete,
                    icon: Icon(Icons.delete_rounded,
                        size: 16, color: AppColors.error.withValues(alpha: 0.7)),
                    tooltip: 'Delete',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({required this.scope, required this.color});
  final String scope;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          scope.toUpperCase(),
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.5),
        ),
      );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color),
        ),
      );
}
