import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../application/providers/amc_plans_providers.dart';
import '../../domain/models/amc_plan.dart';
import 'amc_plan_form_dialog.dart';

/// Dialog for linking / unlinking AMC Plans to a specific catalog node.
/// Also lets the admin create a new plan inline via [AmcPlanFormDialog].
class NodeAmcPlansDialog extends ConsumerStatefulWidget {
  const NodeAmcPlansDialog({
    super.key,
    required this.nodeId,
    required this.nodeName,
    this.nodeBasePrice,
  });

  final String nodeId;
  final String nodeName;

  /// The service's base price from the catalog. When provided, the inline
  /// "Create AMC Plan" form uses it as the read-only price per visit.
  final double? nodeBasePrice;

  @override
  ConsumerState<NodeAmcPlansDialog> createState() =>
      _NodeAmcPlansDialogState();
}

class _NodeAmcPlansDialogState extends ConsumerState<NodeAmcPlansDialog> {
  static final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  Set<String> _selected = {};
  bool _saving = false;
  bool _initialised = false;

  void _openCreatePlan() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AmcPlanFormDialog(
        servicePrice: widget.nodeBasePrice,
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
            ref.read(allAmcPlansNotifierProvider.notifier).create(
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

  void _openEditPlan(AmcPlan plan) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AmcPlanFormDialog(
        existing: plan,
        // No servicePrice: price per visit field is visible and pre-filled
        // from the existing plan so the admin can update it if needed.
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
            ref.read(allAmcPlansNotifierProvider.notifier).update(
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

  @override
  Widget build(BuildContext context) {
    final allAsync = ref.watch(allAmcPlansNotifierProvider);
    final linkedAsync =
        ref.watch(nodeAmcPlansNotifierProvider(widget.nodeId));

    // Seed selection from DB once both loads complete
    if (!_initialised) {
      final linked = linkedAsync.valueOrNull;
      if (linked != null) {
        _selected = linked.toSet();
        _initialised = true;
      }
    }

    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                          widget.nodeName,
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

            // ── Service price banner (when set) ──────────────────────────
            if (widget.nodeBasePrice != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                color: AppColors.primary.withValues(alpha: 0.04),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 14, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Service price: ${_currency.format(widget.nodeBasePrice)} per visit',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.primary),
                    ),
                  ],
                ),
              ),

            // ── Body ────────────────────────────────────────────────────
            Flexible(
              child: allAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (allPlans) {
                  final active =
                      allPlans.where((p) => p.isActive).toList();

                  if (active.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_mode_outlined,
                              size: 48, color: AppColors.textSecondary),
                          const SizedBox(height: 12),
                          const Text(
                            'No active AMC plans yet.',
                            style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          const Text(
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
                    itemCount: active.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 8),
                    itemBuilder: (_, i) => _PlanTile(
                      plan: active[i],
                      selected: _selected.contains(active[i].id),
                      currency: _currency,
                      onToggle: (val) => setState(() {
                        if (val) {
                          _selected.add(active[i].id);
                        } else {
                          _selected.remove(active[i].id);
                        }
                      }),
                      onEdit: () => _openEditPlan(active[i]),
                    ),
                  );
                },
              ),
            ),

            // ── Footer ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                border:
                    Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Create plan inline
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openCreatePlan,
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Create AMC Plan'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(
                            vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        '${_selected.length} plan${_selected.length == 1 ? '' : 's'} selected',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary),
                      ),
                      const Spacer(),
                      OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 11),
                        ),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 11),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white),
                              )
                            : const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(nodeAmcPlansNotifierProvider(widget.nodeId).notifier)
          .sync(_selected.toList());
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AMC plans updated.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Save failed: $e'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.plan,
    required this.selected,
    required this.currency,
    required this.onToggle,
    required this.onEdit,
  });

  final AmcPlan plan;
  final bool selected;
  final NumberFormat currency;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.05)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.4)
              : AppColors.border,
          width: selected ? 1.5 : 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Selectable area ──────────────────────────────────────────
          Expanded(
            child: GestureDetector(
              onTap: () => onToggle(!selected),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: selected,
                      onChanged: (v) => onToggle(v ?? false),
                      activeColor: AppColors.primary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan.planName,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary),
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
                                    color:
                                        AppColors.error.withValues(alpha: 0.1),
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
                  ],
                ),
              ),
            ),
          ),

          // ── Edit button ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              tooltip: 'Edit plan',
              visualDensity: VisualDensity.compact,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 3),
          Text(
            text,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      );
}
