import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/widgets/admin_search_bar.dart';
import '../../application/providers/amc_plans_providers.dart';
import '../../domain/models/amc_plan.dart';
import '../widgets/amc_plan_form_dialog.dart';

class AmcPlansPage extends ConsumerStatefulWidget {
  const AmcPlansPage({super.key});

  @override
  ConsumerState<AmcPlansPage> createState() => _AmcPlansPageState();
}

class _AmcPlansPageState extends ConsumerState<AmcPlansPage> {
  String _searchQuery = '';
  static final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  List<AmcPlan> _filtered(List<AmcPlan> all) {
    if (_searchQuery.isEmpty) return all;
    return all
        .where((p) =>
            p.planName.toLowerCase().contains(_searchQuery) ||
            p.packageDurationLabel.toLowerCase().contains(_searchQuery) ||
            p.serviceIntervalLabel.toLowerCase().contains(_searchQuery))
        .toList();
  }

  void _openCreate() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AmcPlanFormDialog(
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

  void _openEdit(AmcPlan plan) {
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

  Future<void> _confirmDelete(AmcPlan plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete AMC Plan?'),
        content: Text(
          'Delete "${plan.planName}"? This also removes it from all linked services.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(allAmcPlansNotifierProvider.notifier)
          .delete(plan.id);
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

  @override
  Widget build(BuildContext context) {
    final plansAsync = ref.watch(allAmcPlansNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AMC Plans',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Create reusable maintenance plans. Link them to services from the Catalog.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: _openCreate,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New Plan'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Search ───────────────────────────────────────────────────
            AdminSearchBar(
              hintText: 'Search plans…',
              onChanged: (q) =>
                  setState(() => _searchQuery = q.toLowerCase()),
            ),
            const SizedBox(height: 16),

            // ── Table ────────────────────────────────────────────────────
            Expanded(
              child: plansAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text('Error loading plans: $e')),
                data: (allPlans) {
                  final list = _filtered(allPlans);
                  if (list.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_mode_outlined,
                              size: 56, color: AppColors.textSecondary),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isEmpty
                                ? 'No AMC plans yet'
                                : 'No plans match "$_searchQuery"',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (_searchQuery.isEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Click "New Plan" to create the first one.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ],
                      ),
                    );
                  }

                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: AppColors.border),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowColor: WidgetStatePropertyAll(
                                AppColors.background),
                            columnSpacing: 24,
                            columns: const [
                              DataColumn(label: Text('Plan Name')),
                              DataColumn(label: Text('Duration')),
                              DataColumn(label: Text('Interval')),
                              DataColumn(
                                  label: Text('Visits'), numeric: true),
                              DataColumn(
                                  label: Text('Per Visit'), numeric: true),
                              DataColumn(
                                  label: Text('Discount')),
                              DataColumn(
                                  label: Text('Final Price'), numeric: true),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Actions')),
                            ],
                            rows: list.map((plan) {
                              return DataRow(cells: [
                                DataCell(
                                  Text(
                                    plan.planName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13),
                                  ),
                                ),
                                DataCell(Text(
                                  plan.packageDurationLabel,
                                  style: const TextStyle(fontSize: 12),
                                )),
                                DataCell(Text(
                                  plan.serviceIntervalLabel,
                                  style: const TextStyle(fontSize: 12),
                                )),
                                DataCell(Text(
                                  '${plan.numVisits}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13),
                                )),
                                DataCell(Text(
                                  _currency.format(plan.pricePerVisit),
                                  style: const TextStyle(fontSize: 12),
                                )),
                                DataCell(
                                  plan.discountValue > 0
                                      ? Text(
                                          plan.discountType == 'percentage'
                                              ? '${plan.discountValue.toStringAsFixed(0)}%'
                                              : _currency.format(
                                                  plan.discountValue),
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.error),
                                        )
                                      : const Text('—',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color:
                                                  AppColors.textSecondary)),
                                ),
                                DataCell(Text(
                                  _currency.format(plan.finalPrice),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: AppColors.success),
                                )),
                                DataCell(
                                  Switch(
                                    value: plan.isActive,
                                    onChanged: (val) => ref
                                        .read(allAmcPlansNotifierProvider
                                            .notifier)
                                        .toggleActive(plan.id,
                                            isActive: val),
                                    activeColor: AppColors.success,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                            Icons.edit_outlined,
                                            size: 16),
                                        tooltip: 'Edit',
                                        color: AppColors.textSecondary,
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => _openEdit(plan),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                            Icons.delete_outline,
                                            size: 16),
                                        tooltip: 'Delete',
                                        color: AppColors.error,
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () =>
                                            _confirmDelete(plan),
                                      ),
                                    ],
                                  ),
                                ),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
