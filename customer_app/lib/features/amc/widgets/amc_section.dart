import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../models/amc_plan_model.dart';
import '../providers/amc_provider.dart';
import 'amc_bottom_sheet.dart';

export '../models/amc_plan_model.dart';
export '../providers/amc_provider.dart';

/// Conditionally shown section on the service details page.
/// Hidden when AMC is not configured or disabled for this service.
///
/// [regularPrice] — the service's standard per-visit price. When provided,
/// the plan sheet shows a strikethrough original price, discount badge, and
/// savings chip. Omit when the value is unavailable — those elements are
/// suppressed rather than fabricated.
class AmcSection extends ConsumerWidget {
  final String serviceId;
  final AmcPlanModel? selectedPlan;
  final void Function(AmcPlanModel? plan) onPlanSelected;
  final double? regularPrice;

  const AmcSection({
    super.key,
    required this.serviceId,
    required this.selectedPlan,
    required this.onPlanSelected,
    this.regularPrice,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amcAsync = ref.watch(amcPlansProvider(serviceId));

    return amcAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (plans) {
        if (plans.isEmpty) return const SizedBox.shrink();

        return _AmcSectionBody(
          plans: plans,
          selectedPlan: selectedPlan,
          onPlanSelected: onPlanSelected,
          regularPrice: regularPrice,
        );
      },
    );
  }
}

// ── Section body (compact entry card on the service detail page) ──────────────

class _AmcSectionBody extends StatefulWidget {
  final List<AmcPlanModel> plans;
  final AmcPlanModel? selectedPlan;
  final void Function(AmcPlanModel? plan) onPlanSelected;
  final double? regularPrice;

  const _AmcSectionBody({
    required this.plans,
    required this.selectedPlan,
    required this.onPlanSelected,
    this.regularPrice,
  });

  @override
  State<_AmcSectionBody> createState() => _AmcSectionBodyState();
}

class _AmcSectionBodyState extends State<_AmcSectionBody> {
  bool _sheetOpen = false;

  Future<void> _openSheet() async {
    if (_sheetOpen) return;
    setState(() => _sheetOpen = true);

    try {
      final result = await showAmcPlansSheet(
        context,
        widget.plans,
        widget.selectedPlan,
        regularPrice: widget.regularPrice,
      );

      if (!mounted) return;

      if (result != null) {
        widget.onPlanSelected(result.plan);
      }
    } finally {
      if (mounted) setState(() => _sheetOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedPlan = widget.selectedPlan;
    final hasPlan = selectedPlan != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withValues(alpha: 0.07),
              AppColors.primary.withValues(alpha: 0.02),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasPlan
                ? AppColors.primary.withValues(alpha: 0.5)
                : AppColors.primary.withValues(alpha: 0.22),
            width: hasPlan ? 1.5 : 1.0,
          ),
          boxShadow: hasPlan
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.build_circle_outlined,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AMC Plans Available',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 1),
                        const Text(
                          'Save more with recurring maintenance',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Selected plan summary ─────────────────────────────────────
            if (hasPlan)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          size: 15, color: AppColors.success),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selectedPlan.planName,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.success,
                              ),
                            ),
                            Text(
                              '₹${selectedPlan.finalPrice % 1 == 0 ? selectedPlan.finalPrice.toInt() : selectedPlan.finalPrice.toStringAsFixed(2)} · ${selectedPlan.numVisits} visits',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.success
                                    .withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => widget.onPlanSelected(null),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded,
                              size: 12, color: AppColors.success),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const Divider(height: 1),

            // ── CTA ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _sheetOpen ? null : _openSheet,
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        AppColors.primary.withValues(alpha: 0.1),
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  icon: Icon(
                    hasPlan
                        ? Icons.swap_horiz_rounded
                        : Icons.list_alt_rounded,
                    size: 18,
                  ),
                  label: Text(
                    hasPlan ? 'Change AMC Plan' : 'View AMC Plans',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
