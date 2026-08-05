import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/vendor_tiers_providers.dart';
import '../../domain/models/vendor_tier.dart';
import '../widgets/vendor_tier_form_dialog.dart';
import '../../../bookings/presentation/widgets/dispatch_settings_dialog.dart';

class VendorTiersPage extends ConsumerStatefulWidget {
  const VendorTiersPage({super.key});

  @override
  ConsumerState<VendorTiersPage> createState() => _VendorTiersPageState();
}

class _VendorTiersPageState extends ConsumerState<VendorTiersPage> {
  bool _evaluatingBatch = false;

  void _openDispatchSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => const DispatchSettingsDialog(),
    );
  }

  void _openFormDialog([VendorTier? existing, int defaultPriority = 1]) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => VendorTierFormDialog(
        existing: existing,
        defaultPriority: defaultPriority,
        onSave: (tier) async {
          final notifier = ref.read(vendorTiersNotifierProvider.notifier);
          if (existing == null) {
            await notifier.createTier(tier);
          } else {
            await notifier.updateTier(tier);
          }
        },
      ),
    );
  }

  Future<void> _runBatchEvaluation() async {
    setState(() => _evaluatingBatch = true);
    try {
      final count = await ref
          .read(vendorTiersNotifierProvider.notifier)
          .evaluateAllVendors();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Performance evaluation completed for $count vendor${count == 1 ? '' : 's'}.',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to evaluate vendors: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _evaluatingBatch = false);
    }
  }

  Future<void> _confirmDelete(VendorTier tier) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Vendor Tier'),
        content: Text(
          'Are you sure you want to delete "${tier.name}"? Vendors currently in this tier will be re-evaluated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await ref
            .read(vendorTiersNotifierProvider.notifier)
            .deleteTier(tier.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Tier "${tier.name}" deleted.'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete tier: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vendorTiersNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vendor Tier Management',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Configure dynamic vendor tiers and performance qualification thresholds',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _openDispatchSettingsDialog,
                  icon: const Icon(Icons.settings_suggest_rounded, size: 20),
                  label: const Text('Dispatch Settings'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _evaluatingBatch ? null : _runBatchEvaluation,
                  icon: _evaluatingBatch
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded, size: 20),
                  label: const Text('Evaluate All Vendors'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onPressed: () {
                    final currentTiers = state.value ?? [];
                    final nextPriority = currentTiers.isEmpty
                        ? 1
                        : currentTiers
                                .map((t) => t.priority)
                                .reduce((a, b) => a > b ? a : b) +
                            1;
                    _openFormDialog(null, nextPriority);
                  },
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('Add Vendor Tier'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Statistics Summary Cards
            state.when(
              data: (tiers) => _buildStatsRow(tiers),
              loading: () => const SizedBox.shrink(),
              error: (err, st) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 20),

            // Priority Dispatch Explanation Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Automatic Promotion & Demotion Engine',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Vendors are automatically evaluated from Priority #1 downwards. The highest tier matching ALL qualification thresholds is assigned automatically.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Tiers List Content (Expanded bounded constraints)
            Expanded(
              child: state.when(
                data: (tiers) {
                  if (tiers.isEmpty) {
                    return _buildEmptyState();
                  }
                  return _buildReorderableTierList(tiers);
                },
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(48.0),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (err, st) => Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppColors.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Error loading vendor tiers: $err'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                        ),
                        onPressed: () => ref
                            .read(vendorTiersNotifierProvider.notifier)
                            .fetchTiers(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(List<VendorTier> tiers) {
    final total = tiers.length;
    final activeCount = tiers.where((t) => t.isActive).length;
    final disabledCount = total - activeCount;

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            title: 'Configured Tiers',
            value: '$total',
            icon: Icons.layers_rounded,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _StatCard(
            title: 'Active Tiers',
            value: '$activeCount',
            icon: Icons.check_circle_rounded,
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _StatCard(
            title: 'Disabled Tiers',
            value: '$disabledCount',
            icon: Icons.pause_circle_rounded,
            color: AppColors.warning,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: constraints.maxWidth,
          padding: const EdgeInsets.all(48),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  size: 48,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'No Vendor Tiers Configured',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Create your first dynamic vendor tier to manage automatic vendor promotions.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () => _openFormDialog(null, 1),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Create First Tier'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReorderableTierList(List<VendorTier> tiers) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ReorderableListView.builder(
          padding: EdgeInsets.zero,
          buildDefaultDragHandles: false,
          itemCount: tiers.length,
          onReorder: (oldIndex, newIndex) {
            ref
                .read(vendorTiersNotifierProvider.notifier)
                .reorderTiers(oldIndex, newIndex);
          },
          itemBuilder: (context, index) {
            final tier = tiers[index];
            final rankDisplay = index + 1;

            return SizedBox(
              key: ValueKey(tier.id),
              width: constraints.maxWidth,
              child: Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 0,
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      // Drag handle
                      ReorderableDragStartListener(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Icon(
                            Icons.drag_indicator_rounded,
                            color: AppColors.textSecondary.withValues(alpha: 0.6),
                            size: 22,
                          ),
                        ),
                      ),

                      // Rank Badge (#1, #2, etc.)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          '#$rankDisplay',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Badge Icon & Color Box
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: tier.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: tier.color.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Icon(
                          tier.iconData,
                          color: tier.color,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Tier Details (Name, Description & Criteria Chips)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    tier.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimary,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: tier.isActive
                                        ? AppColors.success
                                            .withValues(alpha: 0.12)
                                        : AppColors.textSecondary
                                            .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    tier.isActive ? 'Active' : 'Disabled',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: tier.isActive
                                          ? AppColors.success
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (tier.description != null &&
                                tier.description!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                tier.description!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                              ),
                            ],
                            const SizedBox(height: 8),

                            // Qualification Threshold Chips
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                _CriterionChip(
                                  label: 'Min ${tier.minCompletedBookings} Orders',
                                  icon: Icons.check_circle_outline_rounded,
                                ),
                                _CriterionChip(
                                  label: 'Rating ≥ ${tier.minRating.toStringAsFixed(1)}',
                                  icon: Icons.star_outline_rounded,
                                ),
                                _CriterionChip(
                                  label: 'Max Cancel ${tier.maxCancellationRate.toStringAsFixed(1)}%',
                                  icon: Icons.cancel_outlined,
                                ),
                                _CriterionChip(
                                  label: 'Min Complete ${tier.minCompletionRate.toStringAsFixed(1)}%',
                                  icon: Icons.task_alt_rounded,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Inline Active Switch
                      Switch(
                        value: tier.isActive,
                        onChanged: (val) {
                          ref
                              .read(vendorTiersNotifierProvider.notifier)
                              .toggleActiveStatus(tier);
                        },
                        activeTrackColor: AppColors.primary,
                      ),
                      const SizedBox(width: 8),

                      // Actions (Edit & Delete)
                      IconButton(
                        onPressed: () => _openFormDialog(tier, tier.priority),
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        tooltip: 'Edit Tier',
                      ),
                      IconButton(
                        onPressed: () => _confirmDelete(tier),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 20,
                          color: AppColors.error,
                        ),
                        tooltip: 'Delete Tier',
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CriterionChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _CriterionChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
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
