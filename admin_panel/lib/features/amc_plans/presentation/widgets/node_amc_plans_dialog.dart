import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../application/providers/amc_plans_providers.dart';
import '../../domain/models/amc_plan.dart';
import 'amc_plan_form_dialog.dart';

/// Shows AMC plans that belong to this specific catalog node.
/// Create immediately links the new plan to this node.
/// Delete unlinks (and removes the plan if it has no other node links).
class NodeAmcPlansDialog extends ConsumerWidget {
  const NodeAmcPlansDialog({
    super.key,
    required this.nodeId,
    required this.nodeName,
    this.nodeBasePrice,
  });

  final String nodeId;
  final String nodeName;

  /// The service's base price. When provided, the "Create AMC Plan" form uses
  /// it as the read-only price per visit.
  final double? nodeBasePrice;

  static final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(nodeAmcPlansListNotifierProvider(nodeId));

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 520,
        height: 640,
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_mode_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AMC Plans',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700),
                        ),
                        Text(
                          nodeName,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // ── Service price banner ─────────────────────────────────────
            if (nodeBasePrice != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: AppColors.primary.withValues(alpha: 0.04),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 14, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Service price: ${_currency.format(nodeBasePrice)} per visit',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.primary),
                    ),
                  ],
                ),
              ),

            // ── Body ────────────────────────────────────────────────────
            Flexible(
              child: plansAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (plans) {
                  if (plans.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_mode_outlined,
                              size: 48, color: AppColors.textSecondary),
                          SizedBox(height: 12),
                          Text(
                            'No AMC plans available for this service.',
                            style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Use the button below to create one.',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: plans.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (_, i) => _PlanTile(
                      plan: plans[i],
                      currency: _currency,
                      onEdit: () => _openEditPlan(context, ref, plans[i]),
                      onDelete: () =>
                          _confirmDelete(context, ref, plans[i]),
                      onToggleActive: () => ref
                          .read(nodeAmcPlansListNotifierProvider(nodeId)
                              .notifier)
                          .toggleActive(plans[i].id,
                              isActive: !plans[i].isActive),
                    ),
                  );
                },
              ),
            ),

            // ── Footer ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openCreatePlan(context, ref),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Create AMC Plan'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding:
                            const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 11),
                    ),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCreatePlan(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AmcPlanFormDialog(
        servicePrice: nodeBasePrice,
        onSave: ({
          required planName,
          required packageDuration,
          packageDurationValue,
          required serviceInterval,
          serviceIntervalValue,
          required pricePerVisit,
          required discountType,
          required discountValue,
          required isActive,
        }) =>
            ref.read(nodeAmcPlansListNotifierProvider(nodeId).notifier).createAndLink(
                  planName: planName,
                  packageDuration: packageDuration,
                  packageDurationValue: packageDurationValue,
                  serviceInterval: serviceInterval,
                  serviceIntervalValue: serviceIntervalValue,
                  pricePerVisit: pricePerVisit,
                  discountType: discountType,
                  discountValue: discountValue,
                  isActive: isActive,
                ),
      ),
    );
  }

  void _openEditPlan(BuildContext context, WidgetRef ref, AmcPlan plan) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AmcPlanFormDialog(
        existing: plan,
        onSave: ({
          required planName,
          required packageDuration,
          packageDurationValue,
          required serviceInterval,
          serviceIntervalValue,
          required pricePerVisit,
          required discountType,
          required discountValue,
          required isActive,
        }) =>
            ref.read(nodeAmcPlansListNotifierProvider(nodeId).notifier).update(
                  plan.id,
                  planName: planName,
                  packageDuration: packageDuration,
                  packageDurationValue: packageDurationValue,
                  serviceInterval: serviceInterval,
                  serviceIntervalValue: serviceIntervalValue,
                  pricePerVisit: pricePerVisit,
                  discountType: discountType,
                  discountValue: discountValue,
                  isActive: isActive,
                ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, AmcPlan plan) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Remove AMC Plan'),
        content: Text(
            'Remove "${plan.planName}" from this service? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(nodeAmcPlansListNotifierProvider(nodeId).notifier)
          .remove(plan.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }
}

// ── Plan tile ──────────────────────────────────────────────────────────────────

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.plan,
    required this.currency,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
  });

  final AmcPlan plan;
  final NumberFormat currency;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Plan details ─────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          plan.planName,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: plan.isActive
                              ? AppColors.success.withValues(alpha: 0.12)
                              : AppColors.textSecondary
                                  .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          plan.isActive ? 'Active' : 'Inactive',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: plan.isActive
                                ? AppColors.success
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      _meta(Icons.date_range_rounded,
                          plan.packageDurationLabel),
                      _meta(Icons.repeat_rounded,
                          plan.serviceIntervalLabel),
                      _meta(Icons.confirmation_number_outlined,
                          '${plan.numVisits} visits'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (plan.discountAmount > 0) ...[
                        Text(
                          currency.format(plan.originalTotal),
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              decoration: TextDecoration.lineThrough),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        currency.format(plan.finalPrice),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.success),
                      ),
                      if (plan.discountAmount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            plan.discountType == 'percentage'
                                ? '${plan.discountValue.toStringAsFixed(0)}% off'
                                : '${currency.format(plan.discountValue)} off',
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.error),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // ── Action buttons ───────────────────────────────────────────
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: plan.isActive ? 'Set inactive' : 'Set active',
                  child: Transform.scale(
                    scale: 0.78,
                    child: Switch(
                      value: plan.isActive,
                      onChanged: (_) => onToggleActive(),
                      activeTrackColor: AppColors.success,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Edit plan',
                  visualDensity: VisualDensity.compact,
                  color: AppColors.textSecondary,
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: 'Remove plan',
                  visualDensity: VisualDensity.compact,
                  color: AppColors.error,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 3),
          Text(text,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
        ],
      );
}
