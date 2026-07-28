import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/widgets/vendor_scaffold.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../domain/models/subscription_plan.dart';
import '../providers/subscription_provider.dart';

class PlanConfirmationPage extends ConsumerStatefulWidget {
  const PlanConfirmationPage({super.key, required this.plan});
  final SubscriptionPlan plan;

  @override
  ConsumerState<PlanConfirmationPage> createState() =>
      _PlanConfirmationPageState();
}

class _PlanConfirmationPageState
    extends ConsumerState<PlanConfirmationPage> {
  bool _loading = false;
  String? _error;

  SubscriptionPlan get plan => widget.plan;

  double get _joiningFee => plan.joiningFee ?? 0;
  double get _subscriptionFee => plan.subscriptionFee ?? 0;
  double get _total => _joiningFee + _subscriptionFee;

  Future<void> _proceed() async {
    final vendor = ref.read(currentVendorUserProvider);
    if (vendor == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final info = await ref
          .read(subscriptionRepositoryProvider)
          .purchasePlan(vendorId: vendor.id, plan: plan);

      if (!mounted) return;
      context.push(RoutePaths.payment, extra: info);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return VendorScaffold(
      title: 'Confirm Plan',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Plan card
            _PlanSummary(plan: plan),
            const SizedBox(height: 20),

            // Fee breakdown
            _SectionLabel('Payment Summary'),
            const SizedBox(height: 10),
            _BreakdownCard(
              joiningFee: _joiningFee,
              subscriptionFee: _subscriptionFee,
              total: _total,
            ),
            const SizedBox(height: 20),

            // Benefits
            _SectionLabel('What\'s Included'),
            const SizedBox(height: 10),
            _BenefitsList(plan: plan),
            const SizedBox(height: 28),

            // Error
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        size: 18, color: AppColors.error),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_error!,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.error)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // CTA
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _proceed,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.payment_rounded, size: 20),
                label: Text(
                  _loading ? 'Creating order…' : 'Continue to Payment',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                'You will be asked to complete payment on the next screen.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textHint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3, height: 16,
          decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Text(text,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
      ],
    );
  }
}

class _PlanSummary extends StatelessWidget {
  const _PlanSummary({required this.plan});
  final SubscriptionPlan plan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.82)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.workspace_premium_rounded,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                if (plan.isCatalogPlan && plan.catalogNodeName != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.folder_outlined,
                          size: 12, color: Colors.white60),
                      const SizedBox(width: 4),
                      Text(plan.catalogNodeName!,
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  '${plan.billingCycle[0].toUpperCase() + plan.billingCycle.substring(1)}  ·  ${plan.durationDays} days',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({
    required this.joiningFee,
    required this.subscriptionFee,
    required this.total,
  });
  final double joiningFee;
  final double subscriptionFee;
  final double total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
      ),
      child: Column(
        children: [
          if (joiningFee > 0) ...[
            _Row('Joining Fee', '₹${joiningFee.toStringAsFixed(2)}',
                bold: false),
            const SizedBox(height: 10),
          ],
          _Row('Subscription Fee', '₹${subscriptionFee.toStringAsFixed(2)}',
              bold: false),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          _Row('Total Payable', '₹${total.toStringAsFixed(2)}', bold: true),
        ],
      ),
    );
  }

  Widget _Row(String label, String value, {required bool bold}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 13,
                color: bold
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontWeight:
                    bold ? FontWeight.w700 : FontWeight.w400)),
        Text(value,
            style: TextStyle(
                fontSize: bold ? 16 : 13,
                fontWeight:
                    bold ? FontWeight.w800 : FontWeight.w600,
                color:
                    bold ? AppColors.primary : AppColors.textPrimary)),
      ],
    );
  }
}

class _BenefitsList extends StatelessWidget {
  const _BenefitsList({required this.plan});
  final SubscriptionPlan plan;

  @override
  Widget build(BuildContext context) {
    final benefits = <(IconData, String, bool)>[
      (Icons.local_atm_rounded, 'Cash on Delivery', plan.allowCod),
      (Icons.assignment_ind_rounded, 'Booking Assignment',
          plan.allowBookingAssignment),
      (Icons.star_rounded, 'Priority Listing', plan.priorityListing),
      if (plan.reducedCommissionPct > 0)
        (Icons.percent_rounded,
            '${plan.reducedCommissionPct.toStringAsFixed(0)}% Reduced Commission',
            true),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
      ),
      child: Column(
        children: benefits.map((b) {
          final (icon, label, enabled) = b;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Icon(icon,
                    size: 18,
                    color: enabled ? AppColors.primary : AppColors.textHint),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 13,
                          color: enabled
                              ? AppColors.textPrimary
                              : AppColors.textHint,
                          decoration:
                              enabled ? null : TextDecoration.lineThrough)),
                ),
                Icon(
                  enabled
                      ? Icons.check_circle_rounded
                      : Icons.cancel_outlined,
                  size: 18,
                  color:
                      enabled ? AppColors.success : AppColors.textHint,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
