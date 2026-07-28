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

enum _PlanStatus { active, pendingPayment, available, inactive }

class BrowsePlansPage extends ConsumerWidget {
  const BrowsePlansPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(activePlansProvider);
    final catalogAsync = ref.watch(catalogSubscriptionOfferingsProvider);
    final mySubAsync = ref.watch(mySubscriptionProvider);
    final myCatalogSubsAsync = ref.watch(myCatalogSubscriptionsProvider);

    final loading = plansAsync.isLoading || catalogAsync.isLoading;
    final error = plansAsync.error ?? catalogAsync.error;
    final globalPlans = plansAsync.valueOrNull ?? [];
    final catalogPlans = catalogAsync.valueOrNull ?? [];
    final hasAny = globalPlans.isNotEmpty || catalogPlans.isNotEmpty;

    final myGlobalSub = mySubAsync.valueOrNull;
    final myCatalogSubs = myCatalogSubsAsync.valueOrNull ?? [];
    final hasActiveGlobalSub = myGlobalSub?.isActive == true;

    _PlanStatus globalStatus(SubscriptionPlan plan) {
      if (!plan.isActive) return _PlanStatus.inactive;
      if (myGlobalSub?.planId == plan.id) {
        final s = myGlobalSub!.status;
        if (s == 'active') return _PlanStatus.active;
        if (s == 'pending_payment') return _PlanStatus.pendingPayment;
      }
      return _PlanStatus.available;
    }

    _PlanStatus catalogStatus(SubscriptionPlan plan) {
      if (!plan.isActive) return _PlanStatus.inactive;
      final match = myCatalogSubs
          .where((s) => s.catalogNodeId == plan.catalogNodeId)
          .firstOrNull;
      if (match == null) return _PlanStatus.available;
      if (match.status == 'active') return _PlanStatus.active;
      if (match.status == 'pending_payment') return _PlanStatus.pendingPayment;
      return _PlanStatus.available;
    }

    VendorSubscription? catalogSub(SubscriptionPlan plan) => myCatalogSubs
        .where((s) => s.catalogNodeId == plan.catalogNodeId)
        .firstOrNull;

    return VendorScaffold(
      title: 'Browse Plans',
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(activePlansProvider);
          ref.invalidate(catalogSubscriptionOfferingsProvider);
          ref.invalidate(mySubscriptionProvider);
          ref.invalidate(myCatalogSubscriptionsProvider);
        },
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null && !hasAny
                ? _ErrorView(
                    message: error.toString(),
                    onRetry: () {
                      ref.invalidate(activePlansProvider);
                      ref.invalidate(catalogSubscriptionOfferingsProvider);
                    },
                  )
                : !hasAny
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.workspace_premium_outlined,
                                  size: 48, color: AppColors.textHint),
                              SizedBox(height: 14),
                              Text(
                                'No plans available at this time.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: AppColors.textSecondary, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                        children: [
                          if (globalPlans.isNotEmpty) ...[
                            _SectionHeader('Global Plans'),
                            const SizedBox(height: 4),
                            const Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: Text(
                                'A Global Subscription gives access to all catalog categories.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    height: 1.4),
                              ),
                            ),
                            ...globalPlans.map((p) {
                              final st = globalStatus(p);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: _PlanCard(
                                  plan: p,
                                  status: st,
                                  activeSub: myGlobalSub?.planId == p.id
                                      ? myGlobalSub
                                      : null,
                                ),
                              );
                            }),
                          ],
                          if (catalogPlans.isNotEmpty) ...[
                            if (globalPlans.isNotEmpty) const SizedBox(height: 8),
                            _SectionHeader('Catalog Plans'),
                            const SizedBox(height: 4),
                            const Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: Text(
                                'Access tied to a specific service category and its subcategories.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    height: 1.4),
                              ),
                            ),
                            if (hasActiveGlobalSub) ...[
                              _InfoNote(
                                icon: Icons.info_outline_rounded,
                                message:
                                    'Your Global Subscription already includes access to all catalog categories.',
                                color: AppColors.primary,
                              ),
                              const SizedBox(height: 12),
                            ],
                            ...catalogPlans.map((p) {
                              final st = catalogStatus(p);
                              final cs = catalogSub(p);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: _PlanCard(
                                  plan: p,
                                  status: st,
                                  activeSub: cs,
                                  coveredByGlobalSub: hasActiveGlobalSub &&
                                      st != _PlanStatus.active,
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
      ),
    );
  }
}

// ── Plan card ─────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.status,
    this.activeSub,
    this.coveredByGlobalSub = false,
  });
  final SubscriptionPlan plan;
  final _PlanStatus status;
  final VendorSubscription? activeSub;
  final bool coveredByGlobalSub;

  @override
  Widget build(BuildContext context) {
    final total = (plan.joiningFee ?? 0) + (plan.subscriptionFee ?? 0);
    final fmt = DateFormat('d MMM yyyy');
    final isActive = status == _PlanStatus.active;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? AppColors.success.withValues(alpha: 0.5)
              : AppColors.border.withValues(alpha: 0.8),
          width: isActive ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.workspace_premium_rounded,
                    color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            plan.name,
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary),
                          ),
                        ),
                        if (status != _PlanStatus.available ||
                            coveredByGlobalSub) ...[
                          const SizedBox(width: 8),
                          _StatusChip(status,
                              isIncluded: coveredByGlobalSub &&
                                  status == _PlanStatus.available),
                        ],
                      ],
                    ),
                    if (plan.isCatalogPlan && plan.catalogNodeName != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.folder_outlined,
                              size: 11, color: AppColors.textHint),
                          const SizedBox(width: 3),
                          Text(plan.catalogNodeName!,
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textHint)),
                        ],
                      ),
                    ],
                    if (plan.description?.isNotEmpty == true) ...[
                      const SizedBox(height: 3),
                      Text(plan.description!,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              height: 1.4)),
                    ],
                  ],
                ),
              ),
            ],
          ),

          // ── Active details ───────────────────────────────────────────────
          if (status == _PlanStatus.active && activeSub != null) ...[
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 14, color: AppColors.success),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      activeSub!.expiryDate != null
                          ? 'Active · Expires ${fmt.format(activeSub!.expiryDate!)}'
                              ' (${activeSub!.remainingDays}d remaining)'
                          : 'Currently active',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.success,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Pending payment details ──────────────────────────────────────
          if (status == _PlanStatus.pendingPayment) ...[
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.payment_rounded,
                      size: 14, color: AppColors.warning),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Payment pending — complete it to activate this plan.',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.warning,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Covered by global note ───────────────────────────────────────
          if (coveredByGlobalSub) ...[
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 13, color: AppColors.primary),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Covered by your Global Subscription.',
                      style: TextStyle(fontSize: 11, color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // ── Billing meta ─────────────────────────────────────────────────
          Row(
            children: [
              _MetaChip(
                icon: Icons.refresh_rounded,
                label: plan.billingCycle[0].toUpperCase() +
                    plan.billingCycle.substring(1),
              ),
              const SizedBox(width: 8),
              _MetaChip(
                icon: Icons.calendar_today_outlined,
                label: '${plan.durationDays} days',
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Benefits ─────────────────────────────────────────────────────
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (plan.allowCod) _BenefitChip('COD', AppColors.success),
              if (plan.allowBookingAssignment)
                _BenefitChip(
                    'Booking Assignment', const Color(0xFF3182CE)),
              if (plan.priorityListing)
                _BenefitChip('Priority Listing', const Color(0xFFDD6B20)),
              if (plan.reducedCommissionPct > 0)
                _BenefitChip(
                    '-${plan.reducedCommissionPct.toStringAsFixed(0)}% Commission',
                    AppColors.primary),
            ],
          ),
          const SizedBox(height: 14),

          // ── Fee breakdown ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                if (plan.joiningFee != null && plan.joiningFee! > 0) ...[
                  _FeeRow('Joining Fee',
                      '₹${plan.joiningFee!.toStringAsFixed(2)}'),
                  const SizedBox(height: 6),
                ],
                if (plan.subscriptionFee != null) ...[
                  _FeeRow('Subscription Fee',
                      '₹${plan.subscriptionFee!.toStringAsFixed(2)}'),
                  const SizedBox(height: 6),
                ],
                const Divider(height: 1),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Payable',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    Text('₹${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── CTA ──────────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: _buildCta(context),
          ),
        ],
      ),
    );
  }

  Widget _buildCta(BuildContext context) {
    switch (status) {
      case _PlanStatus.active:
        return OutlinedButton.icon(
          onPressed: null,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.success,
            side: const BorderSide(color: AppColors.success),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.check_circle_rounded, size: 18),
          label: const Text('Currently Subscribed',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        );
      case _PlanStatus.pendingPayment:
        return FilledButton.icon(
          onPressed: () => _completePendingPayment(context),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.warning,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.payment_rounded, size: 18),
          label: const Text('Complete Payment',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        );
      case _PlanStatus.inactive:
        return OutlinedButton(
          onPressed: null,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textHint,
            side: const BorderSide(color: AppColors.border),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Not Available',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        );
      case _PlanStatus.available:
        if (coveredByGlobalSub) {
          return OutlinedButton.icon(
            onPressed: null,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Already Included',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          );
        }
        return FilledButton(
          onPressed: () =>
              context.push(RoutePaths.planConfirmation, extra: plan),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Select Plan',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        );
    }
  }

  void _completePendingPayment(BuildContext context) {
    final sub = activeSub;
    if (sub == null) return;
    final pending = sub.pendingPayment;
    if (pending == null) return;
    context.push(
      RoutePaths.payment,
      extra: PendingPaymentInfo(
        subscriptionId: sub.id,
        paymentId: pending.id,
        amount: pending.amount,
        planDurationDays: plan.durationDays,
        planName: plan.name,
      ),
    );
  }
}

// ── Status chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status, {this.isIncluded = false});
  final _PlanStatus status;
  final bool isIncluded;

  @override
  Widget build(BuildContext context) {
    if (isIncluded) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
        ),
        child: Text('Included',
            style: TextStyle(
                fontSize: 10,
                color: AppColors.primary,
                fontWeight: FontWeight.w700)),
      );
    }
    final Color color;
    final String label;
    switch (status) {
      case _PlanStatus.active:
        color = AppColors.success;
        label = 'Active';
      case _PlanStatus.pendingPayment:
        color = AppColors.warning;
        label = 'Pending';
      case _PlanStatus.inactive:
        color = AppColors.textHint;
        label = 'Unavailable';
      case _PlanStatus.available:
        return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w700)),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
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

// ── Info note ─────────────────────────────────────────────────────────────────

class _InfoNote extends StatelessWidget {
  const _InfoNote(
      {required this.icon, required this.message, required this.color});
  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(fontSize: 12, color: color, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textHint),
        const SizedBox(width: 4),
        Text(label,
            style:
                const TextStyle(fontSize: 12, color: AppColors.textHint)),
      ],
    );
  }
}

class _BenefitChip extends StatelessWidget {
  const _BenefitChip(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600)),
    );
  }
}

class _FeeRow extends StatelessWidget {
  const _FeeRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary)),
        Text(value,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
      ],
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
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 40, color: AppColors.error),
            const SizedBox(height: 12),
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
      ),
    );
  }
}
