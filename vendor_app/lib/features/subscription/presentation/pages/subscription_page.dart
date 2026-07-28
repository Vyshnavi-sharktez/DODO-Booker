import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/widgets/vendor_scaffold.dart';
import '../../data/subscription_repository.dart';
import '../../domain/models/subscription_plan.dart';
import '../../domain/models/vendor_subscription.dart';
import '../providers/subscription_provider.dart';

class SubscriptionPage extends ConsumerWidget {
  const SubscriptionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subAsync = ref.watch(mySubscriptionProvider);
    final catalogSubsAsync = ref.watch(myCatalogSubscriptionsProvider);
    final settingsAsync = ref.watch(subscriptionSettingsProvider);
    final enabled = settingsAsync.valueOrNull?['subscription_enabled'] == 'true';
    debugPrint('[DODO][SubscriptionPage] settingsAsync=$settingsAsync  '
        'subscription_enabled=${settingsAsync.valueOrNull?['subscription_enabled']}  '
        'enabled=$enabled');

    return VendorScaffold(
      title: 'My Subscription',
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(mySubscriptionProvider);
          ref.invalidate(myCatalogSubscriptionsProvider);
          ref.invalidate(subscriptionSettingsProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (settingsAsync.hasError)
                _InfoBanner(
                  icon: Icons.warning_amber_rounded,
                  message:
                      'Could not load subscription settings. Pull down to retry.',
                  color: AppColors.warning,
                )
              else if (!enabled)
                _InfoBanner(
                  icon: Icons.info_outline_rounded,
                  message:
                      'Subscription module is not active on this platform.',
                  color: AppColors.textSecondary,
                ),
              subAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => _ErrorView(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(mySubscriptionProvider),
                ),
                data: (sub) => sub == null
                    ? _NoSubscription(
                        enabled: enabled,
                        onBrowsePlans: () => _browsePlans(context),
                      )
                    : _SubscriptionBody(
                        sub: sub,
                        onBrowsePlans: () => _browsePlans(context),
                        onCancel: () => _cancelSubscription(context, ref, sub.id),
                      ),
              ),
              // ── Catalog subscriptions ────────────────────────────────────
              catalogSubsAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (catalogSubs) => catalogSubs.isEmpty
                    ? const SizedBox.shrink()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 24),
                          _SectionHeader('Catalog Subscriptions'),
                          const SizedBox(height: 12),
                          ...catalogSubs.map((cs) => Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: _CatalogSubCard(
                                  sub: cs,
                                  onCancel: cs.isActive
                                      ? () => _cancelSubscription(
                                          context, ref, cs.id)
                                      : null,
                                ),
                              )),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _browsePlans(BuildContext context) {
    context.push(RoutePaths.browsePlans);
  }

  Future<void> _cancelSubscription(
      BuildContext context, WidgetRef ref, String subscriptionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Subscription'),
        content: const Text(
          'Are you sure you want to cancel your subscription?\n\n'
          'You will lose access to premium features immediately. '
          'You can purchase a new plan at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Subscription'),
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
          .read(subscriptionRepositoryProvider)
          .cancelSubscription(subscriptionId);
      ref.invalidate(mySubscriptionProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

// ── Subscription body ─────────────────────────────────────────────────────────

class _SubscriptionBody extends StatelessWidget {
  const _SubscriptionBody({
    required this.sub,
    required this.onBrowsePlans,
    required this.onCancel,
  });
  final VendorSubscription sub;
  final VoidCallback onBrowsePlans;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sub.status == 'pending_payment')
          _InfoBanner(
            icon: Icons.payment_rounded,
            message: 'You have a pending payment. Tap "Complete Payment" to activate your subscription.',
            color: AppColors.warning,
          ),
        if (sub.isExpiringSoon)
          _InfoBanner(
            icon: Icons.timer_outlined,
            message:
                'Your subscription expires in ${sub.remainingDays} day${sub.remainingDays == 1 ? '' : 's'}. Renew now to avoid interruptions.',
            color: AppColors.warning,
          ),

        _PlanSummaryCard(
          sub: sub,
          onRenew: onBrowsePlans,
          onCompletePayment: (info) => context.push(RoutePaths.payment, extra: info),
          onCancel: sub.isActive ? onCancel : null,
        ),
        const SizedBox(height: 20),

        if (sub.plan != null) ...[
          _BenefitsCard(plan: sub.plan!),
          const SizedBox(height: 20),
        ],

        if (sub.payments.isNotEmpty) ...[
          _SectionHeader('Payment History'),
          const SizedBox(height: 12),
          _PaymentHistoryList(payments: sub.payments),
        ],

        const SizedBox(height: 28),
        const Divider(height: 1),
        const SizedBox(height: 20),
        _SectionHeader('Explore Plans'),
        const SizedBox(height: 8),
        const Text(
          'Browse all available plans, including catalog-specific subscriptions.',
          style: TextStyle(
              fontSize: 12, color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onBrowsePlans,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.search_rounded, size: 18),
            label: const Text('View All Plans',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}

class _PlanSummaryCard extends StatelessWidget {
  const _PlanSummaryCard({
    required this.sub,
    required this.onRenew,
    required this.onCompletePayment,
    this.onCancel,
  });
  final VendorSubscription sub;
  final VoidCallback onRenew;
  final void Function(PendingPaymentInfo) onCompletePayment;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy');
    final statusColor = _statusColor(sub.status);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.82)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sub.plan?.name ?? 'Subscription',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: statusColor.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          sub.status[0].toUpperCase() + sub.status.substring(1),
                          style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.workspace_premium_rounded,
                      color: Colors.white, size: 30),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 16),
            Row(
              children: [
                _DateItem(label: 'Start Date',
                    value: sub.startDate != null
                        ? fmt.format(sub.startDate!)
                        : '—'),
                _vLine(),
                _DateItem(label: 'Expiry Date',
                    value: sub.expiryDate != null
                        ? fmt.format(sub.expiryDate!)
                        : '—'),
                _vLine(),
                _DateItem(
                  label: 'Remaining',
                  value: sub.isActive
                      ? '${sub.remainingDays}d'
                      : '—',
                  highlight: sub.remainingDays < 7,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (sub.status == 'pending_payment') ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    final pending = sub.pendingPayment;
                    if (pending == null) return;
                    onCompletePayment(PendingPaymentInfo(
                      subscriptionId: sub.id,
                      paymentId: pending.id,
                      amount: pending.amount,
                      planDurationDays: sub.plan?.durationDays ?? 30,
                      planName: sub.plan?.name ?? 'Subscription',
                    ));
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.payment_rounded, size: 18),
                  label: const Text('Complete Payment',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
            if (sub.isActive || sub.isExpiringSoon) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onRenew,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Renew / Upgrade',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
            if (onCancel != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFFC8181),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('Cancel Subscription',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _vLine() => Container(
        width: 1, height: 36, color: Colors.white24,
        margin: const EdgeInsets.symmetric(horizontal: 8));

  Color _statusColor(String status) {
    return switch (status) {
      'active' => const Color(0xFF68D391),
      'expired' => const Color(0xFFFC8181),
      'suspended' => const Color(0xFFFFA94D),
      'pending_payment' || 'pending_approval' || 'pending' =>
        const Color(0xFFECC94B),
      _ => Colors.white70,
    };
  }
}

class _DateItem extends StatelessWidget {
  const _DateItem(
      {required this.label, required this.value, this.highlight = false});
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: highlight ? const Color(0xFFFC8181) : Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(label,
              style: const TextStyle(
                  color: Colors.white60, fontSize: 10)),
        ],
      ),
    );
  }
}

// ── Benefits card ─────────────────────────────────────────────────────────────

class _BenefitsCard extends StatelessWidget {
  const _BenefitsCard({required this.plan});
  final SubscriptionPlan plan;

  @override
  Widget build(BuildContext context) {
    final benefits = <(IconData, String, bool)>[
      (Icons.local_atm_rounded, 'Cash on Delivery', plan.allowCod),
      (Icons.assignment_ind_rounded, 'Booking Assignment', plan.allowBookingAssignment),
      (Icons.star_rounded, 'Priority Listing', plan.priorityListing),
      if (plan.reducedCommissionPct > 0)
        (Icons.percent_rounded,
            '${plan.reducedCommissionPct.toStringAsFixed(0)}% Reduced Commission',
            true),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Plan Benefits',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 14),
          ...benefits.map((b) {
            final (icon, label, enabled) = b;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: enabled
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : AppColors.border.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 16,
                        color: enabled
                            ? AppColors.primary
                            : AppColors.textHint),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: enabled
                                ? AppColors.textPrimary
                                : AppColors.textHint,
                            decoration: enabled
                                ? null
                                : TextDecoration.lineThrough)),
                  ),
                  Icon(
                    enabled
                        ? Icons.check_circle_rounded
                        : Icons.cancel_outlined,
                    size: 18,
                    color: enabled ? AppColors.success : AppColors.textHint,
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Catalog subscription card ─────────────────────────────────────────────────

class _CatalogSubCard extends StatelessWidget {
  const _CatalogSubCard({required this.sub, this.onCancel});
  final VendorSubscription sub;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy');
    final statusColor = switch (sub.status) {
      'active' => AppColors.success,
      'expired' => AppColors.error,
      'pending_payment' || 'pending_approval' || 'pending' => AppColors.warning,
      _ => AppColors.textHint,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.folder_special_rounded,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sub.displayPlanName,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary),
                    ),
                    if (sub.catalogNodeName != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.folder_outlined,
                              size: 11, color: AppColors.textHint),
                          const SizedBox(width: 3),
                          Text(sub.catalogNodeName!,
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textHint)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  sub.status[0].toUpperCase() + sub.status.substring(1),
                  style: TextStyle(
                      fontSize: 11,
                      color: statusColor,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              _DateChip(
                  label: 'Expires',
                  value: sub.expiryDate != null
                      ? fmt.format(sub.expiryDate!)
                      : '—'),
              const SizedBox(width: 16),
              if (sub.isActive)
                _DateChip(
                    label: 'Remaining',
                    value: '${sub.remainingDays}d'),
            ],
          ),
          if (onCancel != null) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: onCancel,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.error,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
              icon: const Icon(Icons.cancel_outlined, size: 14),
              label: const Text('Cancel',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: AppColors.textHint)),
        Text(value,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
      ],
    );
  }
}

// ── Payment history ───────────────────────────────────────────────────────────

class _PaymentHistoryList extends StatelessWidget {
  const _PaymentHistoryList({required this.payments});
  final List<SubscriptionPayment> payments;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy');
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: payments.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, indent: 56, endIndent: 16),
          itemBuilder: (_, i) {
            final p = payments[i];
            final statusColor = p.status == 'paid'
                ? AppColors.success
                : p.status == 'failed'
                    ? AppColors.error
                    : AppColors.warning;
            return ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.receipt_outlined, size: 18, color: statusColor),
              ),
              title: Text(
                p.paymentType.replaceAll('_', ' ').toUpperCase(),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                p.paidAt != null ? fmt.format(p.paidAt!) : 'Not paid',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('₹${p.amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                  Text(p.status,
                      style: TextStyle(
                          fontSize: 10, color: statusColor)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── No subscription ───────────────────────────────────────────────────────────

class _NoSubscription extends StatelessWidget {
  const _NoSubscription({required this.enabled, required this.onBrowsePlans});
  final bool enabled;
  final VoidCallback onBrowsePlans;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.workspace_premium_outlined,
                  size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            const Text('No Active Subscription',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            const Text(
              'Subscribe to unlock premium features like\nCOD payments, booking assignment and\npriority listing.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 13, height: 1.5),
            ),
            if (enabled) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onBrowsePlans,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.search_rounded, size: 18),
                label: const Text('Browse Plans',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3, height: 16,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
      ],
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner(
      {required this.icon, required this.message, required this.color});
  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    fontSize: 13, color: color, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 40, color: AppColors.error),
          const SizedBox(height: 10),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
