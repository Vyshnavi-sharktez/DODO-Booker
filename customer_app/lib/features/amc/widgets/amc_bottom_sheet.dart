import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../models/amc_plan_model.dart';

typedef AmcPlanSelection = ({AmcPlanModel plan});

/// Opens the AMC plans sheet.
/// Returns the selected plan and quantity, or null if dismissed.
/// [regularPrice] is the service's standard price — used to derive discount
/// and savings display. Omit when the value is unavailable.
Future<AmcPlanSelection?> showAmcPlansSheet(
  BuildContext context,
  List<AmcPlanModel> plans,
  AmcPlanModel? currentSelection, {
  double? regularPrice,
}) {
  return showModalBottomSheet<AmcPlanSelection>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AmcPlansSheet(
      plans: plans,
      currentSelection: currentSelection,
      regularPrice: regularPrice,
    ),
  );
}

// ── Sheet ─────────────────────────────────────────────────────────────────────

class _AmcPlansSheet extends StatefulWidget {
  final List<AmcPlanModel> plans;
  final AmcPlanModel? currentSelection;
  final double? regularPrice;

  const _AmcPlansSheet({
    required this.plans,
    this.currentSelection,
    this.regularPrice,
  });

  @override
  State<_AmcPlansSheet> createState() => _AmcPlansSheetState();
}

class _AmcPlansSheetState extends State<_AmcPlansSheet> {
  AmcPlanModel? _selectedPlan;

  @override
  void initState() {
    super.initState();
    _selectedPlan = widget.currentSelection;
  }

  void _onPlanTap(AmcPlanModel plan) {
    setState(() => _selectedPlan = plan);
  }

  void _confirm() {
    final plan = _selectedPlan;
    if (plan == null) return;
    Navigator.of(context).pop((plan: plan));
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedPlan;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Handle ───────────────────────────────────────────────────
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Header ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AMC Plans',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Save more with recurring maintenance',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.build_circle_rounded,
                      size: 22,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Info banner ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Maintain your service regularly & save more in the long run!',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),

            // ── Plan list ────────────────────────────────────────────────
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                itemCount: widget.plans.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final plan = widget.plans[i];
                  return _PlanCard(
                    plan: plan,
                    isSelected: selected == plan,
                    regularPrice: widget.regularPrice,
                    isMostPopular: i == 0,
                    onTap: () => _onPlanTap(plan),
                  );
                },
              ),
            ),

            // ── Trust row ────────────────────────────────────────────────
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.verified_rounded,
                    size: 12,
                    color: AppColors.textHint,
                  ),
                  SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      '100% Genuine Service  •  Expert Technicians  •  Hassle Free',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textHint,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Fixed footer ─────────────────────────────────────────────
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Buttons
                    Row(
                      children: [
                        if (selected != null) ...[
                          // OutlinedButton(
                          //   onPressed: () => Navigator.of(context).pop(null),
                          //   style: OutlinedButton.styleFrom(
                          //     padding: const EdgeInsets.symmetric(
                          //         horizontal: 22, vertical: 14),
                          //     side: const BorderSide(color: AppColors.border),
                          //     shape: RoundedRectangleBorder(
                          //         borderRadius: BorderRadius.circular(12)),
                          //   ),
                          //   child: const Text(
                          //     'Cancel',
                          //     style: TextStyle(
                          //       color: AppColors.textSecondary,
                          //       fontWeight: FontWeight.w600,
                          //     ),
                          //   ),
                          // ),
                          SizedBox(
                            width: 110,
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(null),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                side: const BorderSide(color: AppColors.border),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: FilledButton(
                            onPressed: selected != null ? _confirm : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              disabledBackgroundColor: AppColors.primary
                                  .withValues(alpha: 0.35),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              selected != null
                                  ? 'Select Plan'
                                  : 'Select a Plan',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Plan card ─────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final AmcPlanModel plan;
  final bool isSelected;
  final double? regularPrice;
  final bool isMostPopular;
  final VoidCallback onTap;

  const _PlanCard({
    required this.plan,
    required this.isSelected,
    required this.onTap,
    this.regularPrice,
    this.isMostPopular = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasDiscount = plan.discountAmount > 0;
    final discountLabel = plan.discountType == 'percentage'
        ? '${plan.discountValue.toStringAsFixed(0)}% OFF'
        : '₹${plan.discountValue.toInt()} OFF';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.04)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2.0 : 0.9,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: isSelected ? 18 : 8,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, isMostPopular ? 22 : 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Name + price row ──────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.border,
                                    width: isSelected ? 5.5 : 1.5,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    plan.planName,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.textPrimary,
                                      height: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.repeat_rounded,
                                        size: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${plan.serviceIntervalLabel} · ${plan.packageDurationLabel}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Price column
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (hasDiscount) ...[
                            Row(
                              children: [
                                Text(
                                  '₹${plan.originalTotal % 1 == 0 ? plan.originalTotal.toInt() : plan.originalTotal.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textHint,
                                    decoration: TextDecoration.lineThrough,
                                    decorationColor: AppColors.textHint,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFFE53935,
                                    ).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    discountLabel,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFE53935),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                          ],
                          Text(
                            '₹${plan.finalPrice % 1 == 0 ? plan.finalPrice.toInt() : plan.finalPrice.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                              height: 1.0,
                            ),
                          ),
                          const Text(
                            'total',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // ── Info chips ────────────────────────────────────
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _InfoChip(
                        icon: Icons.confirmation_number_outlined,
                        label: '${plan.numVisits} visits',
                        color: AppColors.primary,
                      ),
                      _InfoChip(
                        icon: Icons.calendar_month_outlined,
                        label: plan.packageDurationLabel,
                        color: AppColors.primary,
                      ),
                      if (hasDiscount)
                        _InfoChip(
                          icon: Icons.savings_outlined,
                          label:
                              'Save ₹${plan.discountAmount % 1 == 0 ? plan.discountAmount.toInt() : plan.discountAmount.toStringAsFixed(2)}',
                          color: const Color(0xFF2E7D32),
                        ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // ── Best Value footer ─────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.goldLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.star_rounded,
                          size: 12,
                          color: AppColors.gold,
                        ),
                        SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'Best Value — Regular maintenance for long-lasting performance',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.gold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Most Popular badge ────────────────────────────────
            if (isMostPopular)
              Positioned(
                top: -1,
                right: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.gold,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.gold.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Text(
                    'Most Popular',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.2,
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

// ── Info chip ─────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
