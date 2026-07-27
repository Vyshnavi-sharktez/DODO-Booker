import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/subscription_providers.dart';
import '../../domain/models/subscription_plan.dart';
import '../../domain/models/vendor_subscription.dart';
import '../widgets/plan_form_dialog.dart';
import '../widgets/vendor_subscription_dialog.dart';

// ── Status colours ────────────────────────────────────────────────────────────

const _subStatusConfig = <String, (String, Color, Color)>{
  'active':           ('Active',           Color(0xFF38A169), Color(0xFFF0FFF4)),
  'pending_payment':  ('Pending Payment',  Color(0xFFD69E2E), Color(0xFFFEFCBF)),
  'pending_approval': ('Pending Approval', Color(0xFFDD6B20), Color(0xFFFEEBC8)),
  'pending':          ('Pending',          Color(0xFFDD6B20), Color(0xFFFEEBC8)),
  'expired':          ('Expired',          Color(0xFF718096), Color(0xFFF7FAFC)),
  'suspended':        ('Suspended',        Color(0xFFE53E3E), Color(0xFFFFF5F5)),
  'cancelled':        ('Cancelled',        Color(0xFF4A5568), Color(0xFFEDF2F7)),
};

class VendorSubscriptionsPage extends ConsumerStatefulWidget {
  const VendorSubscriptionsPage({super.key});

  @override
  ConsumerState<VendorSubscriptionsPage> createState() =>
      _VendorSubscriptionsPageState();
}

class _VendorSubscriptionsPageState
    extends ConsumerState<VendorSubscriptionsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  String? _subStatusFilter;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ── Plans tab ─────────────────────────────────────────────────────────────

  void _openPlanForm([SubscriptionPlan? existing]) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PlanFormDialog(
        existing: existing,
        onSave: ({
          required name,
          description,
          required billingCycle,
          required durationDays,
          joiningFee,
          subscriptionFee,
          required permissions,
          required isActive,
          required sortOrder,
        }) async {
          final notifier = ref.read(plansNotifierProvider.notifier);
          if (existing == null) {
            await notifier.createPlan(
              name: name,
              description: description,
              billingCycle: billingCycle,
              durationDays: durationDays,
              joiningFee: joiningFee,
              subscriptionFee: subscriptionFee,
              permissions: permissions,
              isActive: isActive,
              sortOrder: sortOrder,
            );
          } else {
            await notifier.updatePlan(
              existing.id,
              name: name,
              description: description,
              billingCycle: billingCycle,
              durationDays: durationDays,
              joiningFee: joiningFee,
              subscriptionFee: subscriptionFee,
              permissions: permissions,
              isActive: isActive,
              sortOrder: sortOrder,
            );
          }
        },
      ),
    );
  }

  Future<void> _deletePlan(SubscriptionPlan plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Plan'),
        content: Text('Delete "${plan.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(plansNotifierProvider.notifier).deletePlan(plan.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is Exception
                ? e.toString().replaceFirst('Exception: ', '')
                : 'Delete failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ── Subscriptions tab ─────────────────────────────────────────────────────

  // Opens the subscription dialog for an EXISTING subscription (edit/manage).
  void _openSubDialog({
    required VendorSubscription existing,
    required List<SubscriptionPlan> plans,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => VendorSubscriptionDialog(
        existing: existing,
        plans: plans,
        vendorId: existing.vendorId,
        vendorName: existing.vendorBusinessName ?? 'Vendor',
        onSave: ({
          required planId,
          required status,
          startDate,
          expiryDate,
          notes,
        }) async {
          await ref.read(vendorSubscriptionsNotifierProvider.notifier)
              .updateSubscription(
                existing.id,
                planId: planId,
                status: status,
                startDate: startDate,
                expiryDate: expiryDate,
                notes: notes,
              );
        },
        onAddPayment: ({
          required paymentType,
          required amount,
          required status,
          paymentReference,
          paidAt,
          notes,
        }) async {
          await ref.read(vendorSubscriptionsNotifierProvider.notifier).addPayment(
                subscriptionId: existing.id,
                vendorId: existing.vendorId,
                paymentType: paymentType,
                amount: amount,
                status: status,
                paymentReference: paymentReference,
                paidAt: paidAt,
                notes: notes,
              );
        },
        onRenew: (newExpiry) async {
          await ref.read(vendorSubscriptionsNotifierProvider.notifier).renew(
                existing.id,
                newExpiryDate: newExpiry,
                currentRenewalCount: existing.renewalCount,
              );
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Page header
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.workspace_premium_rounded,
                          color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 14),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Vendor Subscriptions',
                            style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary)),
                        Text('Manage plans, subscriber records, and revenue',
                            style: TextStyle(
                                fontSize: 13, color: AppColors.textSecondary)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TabBar(
                  controller: _tab,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primary,
                  tabs: const [
                    Tab(text: 'Plans'),
                    Tab(text: 'Subscribers'),
                    Tab(text: 'Dashboard'),
                    Tab(text: 'Settings'),
                  ],
                ),
              ],
            ),
          ),

          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _PlansTab(onAdd: _openPlanForm, onEdit: _openPlanForm, onDelete: _deletePlan),
                _SubscribersTab(
                  statusFilter: _subStatusFilter,
                  onFilterChanged: (v) => setState(() => _subStatusFilter = v),
                  onOpenDialog: _openSubDialog,
                ),
                const _DashboardTab(),
                const _SettingsPlaceholderTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Plans Tab ─────────────────────────────────────────────────────────────────

class _PlansTab extends ConsumerWidget {
  const _PlansTab({
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final VoidCallback onAdd;
  final void Function(SubscriptionPlan) onEdit;
  final void Function(SubscriptionPlan) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(plansNotifierProvider);
    return plansAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorRetry(
          error: e.toString(),
          onRetry: () => ref.read(plansNotifierProvider.notifier).refresh()),
      data: (plans) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${plans.length} plan${plans.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
                FilledButton.icon(
                  onPressed: onAdd,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New Plan'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: plans.isEmpty
                  ? const _Empty(
                      icon: Icons.workspace_premium_outlined,
                      message: 'No subscription plans yet. Create one to get started.',
                    )
                  : ListView.separated(
                      itemCount: plans.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _PlanCard(
                        plan: plans[i],
                        onEdit: () => onEdit(plans[i]),
                        onDelete: () => onDelete(plans[i]),
                        onToggle: () => ref
                            .read(plansNotifierProvider.notifier)
                            .toggleActive(plans[i].id,
                                currentIsActive: plans[i].isActive),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  final SubscriptionPlan plan;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plan.name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    if (plan.description?.isNotEmpty == true) ...[
                      const SizedBox(height: 3),
                      Text(plan.description!,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ],
                ),
              ),
              _StatusChip(isActive: plan.isActive),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Edit',
                onPressed: onEdit,
              ),
              IconButton(
                icon: Icon(
                  plan.isActive
                      ? Icons.toggle_on_rounded
                      : Icons.toggle_off_rounded,
                  size: 22,
                  color: plan.isActive ? AppColors.success : AppColors.textSecondary,
                ),
                tooltip: plan.isActive ? 'Deactivate' : 'Activate',
                onPressed: onToggle,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 18, color: AppColors.error),
                tooltip: 'Delete',
                onPressed: onDelete,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _InfoChip(
                  label: plan.billingCycle[0].toUpperCase() +
                      plan.billingCycle.substring(1),
                  icon: Icons.refresh_rounded),
              _InfoChip(label: '${plan.durationDays} days',
                  icon: Icons.calendar_today_outlined),
              if (plan.joiningFee != null)
                _InfoChip(
                    label: 'Joining: ₹${plan.joiningFee!.toStringAsFixed(2)}',
                    icon: Icons.payment_rounded),
              if (plan.subscriptionFee != null)
                _InfoChip(
                    label: 'Fee: ₹${plan.subscriptionFee!.toStringAsFixed(2)}',
                    icon: Icons.currency_rupee_rounded),
              if (plan.allowCod)
                _InfoChip(label: 'COD', icon: Icons.local_atm_rounded,
                    color: AppColors.success),
              if (plan.allowBookingAssignment)
                _InfoChip(label: 'Assignment', icon: Icons.assignment_ind_outlined,
                    color: const Color(0xFF3182CE)),
              if (plan.priorityListing)
                _InfoChip(label: 'Priority', icon: Icons.star_rounded,
                    color: const Color(0xFFDD6B20)),
              if (plan.reducedCommissionPct > 0)
                _InfoChip(
                    label: '-${plan.reducedCommissionPct.toStringAsFixed(0)}% commission',
                    icon: Icons.percent_rounded,
                    color: AppColors.primary),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Subscribers Tab ───────────────────────────────────────────────────────────

class _SubscribersTab extends ConsumerWidget {
  const _SubscribersTab({
    required this.statusFilter,
    required this.onFilterChanged,
    required this.onOpenDialog,
  });

  final String? statusFilter;
  final ValueChanged<String?> onFilterChanged;
  final void Function({
    required VendorSubscription existing,
    required List<SubscriptionPlan> plans,
  }) onOpenDialog;

  Future<void> _confirmCancel(
      BuildContext context, WidgetRef ref, VendorSubscription sub) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Subscription'),
        content: Text(
          'Cancel ${sub.vendorBusinessName ?? 'this vendor'}\'s '
          '"${sub.planName ?? 'subscription'}"?\n\n'
          'The vendor will lose access to premium features immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Subscription'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(vendorSubscriptionsNotifierProvider.notifier)
          .cancel(sub.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is Exception
                ? e.toString().replaceFirst('Exception: ', '')
                : 'Cancel failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subAsync = ref.watch(vendorSubscriptionsNotifierProvider);
    final plansAsync = ref.watch(plansNotifierProvider);
    final plans = plansAsync.valueOrNull ?? [];

    return subAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorRetry(
          error: e.toString(),
          onRetry: () =>
              ref.read(vendorSubscriptionsNotifierProvider.notifier).refresh()),
      data: (subs) {
        final filtered = statusFilter == null
            ? subs
            : subs.where((s) => s.status == statusFilter).toList();

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Filter chips
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _FilterChip(
                        label: 'All',
                        selected: statusFilter == null,
                        onTap: () => onFilterChanged(null)),
                    ...kSubscriptionStatuses.map((s) => _FilterChip(
                          label: s[0].toUpperCase() + s.substring(1),
                          selected: statusFilter == s,
                          onTap: () => onFilterChanged(
                              statusFilter == s ? null : s),
                        )),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('${filtered.length} record${filtered.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 8),
              Expanded(
                child: filtered.isEmpty
                    ? const _Empty(
                        icon: Icons.card_membership_outlined,
                        message: 'No subscriptions match the current filter.',
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _SubscriptionCard(
                          sub: filtered[i],
                          onTap: () => onOpenDialog(
                              existing: filtered[i], plans: plans),
                          onUpdateStatus: (newStatus) => ref
                              .read(vendorSubscriptionsNotifierProvider.notifier)
                              .updateStatus(filtered[i].id, newStatus),
                          onCancel: filtered[i].status == 'active'
                              ? () => _confirmCancel(context, ref, filtered[i])
                              : null,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({
    required this.sub,
    required this.onTap,
    required this.onUpdateStatus,
    this.onCancel,
  });

  final VendorSubscription sub;
  final VoidCallback onTap;
  final void Function(String) onUpdateStatus;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy');
    final cfg = _subStatusConfig[sub.status] ??
        (sub.status, AppColors.textSecondary, AppColors.background);
    final (label, textColor, bgColor) = cfg;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.storefront_rounded, color: textColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sub.vendorBusinessName ?? 'Vendor',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub.planName ?? 'Unknown Plan',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  if (sub.expiryDate != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Expires ${fmt.format(sub.expiryDate!)}  ·  ${sub.remainingDays}d left',
                      style: TextStyle(
                          fontSize: 11,
                          color: sub.remainingDays < 7
                              ? AppColors.error
                              : AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          color: textColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 6),
                Text('×${sub.renewalCount} renewals',
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textSecondary)),
                if (onCancel != null) ...[
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: onCancel,
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                          fontSize: 10,
                          color: AppColors.error,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Dashboard Tab ─────────────────────────────────────────────────────────────

class _DashboardTab extends ConsumerWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(subscriptionDashboardProvider);
    return statsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorRetry(
          error: e.toString(),
          onRetry: () => ref.invalidate(subscriptionDashboardProvider)),
      data: (stats) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Subscription Overview',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (context, constraints) {
              final twoCol = constraints.maxWidth > 600;
              final cards = [
                _StatCard(
                    label: 'Active',
                    value: '${stats['active']}',
                    icon: Icons.check_circle_outline_rounded,
                    color: AppColors.success),
                _StatCard(
                    label: 'Expiring Soon',
                    value: '${stats['expiring_soon']}',
                    icon: Icons.timer_outlined,
                    color: AppColors.warning),
                _StatCard(
                    label: 'Expired',
                    value: '${stats['expired']}',
                    icon: Icons.cancel_outlined,
                    color: AppColors.error),
                _StatCard(
                    label: 'Revenue',
                    value: '₹${(stats['total_revenue'] as double).toStringAsFixed(2)}',
                    icon: Icons.currency_rupee_rounded,
                    color: AppColors.primary),
              ];

              if (twoCol) {
                return GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 3.2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: cards,
                );
              }
              return Column(
                children: cards
                    .map((c) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: c,
                        ))
                    .toList(),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800, color: color)),
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Settings Placeholder Tab ──────────────────────────────────────────────────

class _SettingsPlaceholderTab extends StatelessWidget {
  const _SettingsPlaceholderTab();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.settings_rounded, size: 48, color: AppColors.textSecondary),
            SizedBox(height: 14),
            Text(
              'Subscription settings are managed in\nSettings → Subscription Settings',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.isActive});
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.success.withValues(alpha: 0.1)
            : AppColors.textSecondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
        style: TextStyle(
            color: isActive ? AppColors.success : AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.icon, this.color});
  final String label;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
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
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.white : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 40, color: AppColors.error),
            const SizedBox(height: 12),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

