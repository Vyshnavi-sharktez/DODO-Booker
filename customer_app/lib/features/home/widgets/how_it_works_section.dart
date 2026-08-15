import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/icon_resolver.dart';

// ── Public data model ─────────────────────────────────────────────────────────

class HowItWorksStep {
  final IconData icon;
  final String title;
  final String description;

  const HowItWorksStep({
    required this.icon,
    required this.title,
    required this.description,
  });

  factory HowItWorksStep.fromMap(Map<String, dynamic> map) {
    return HowItWorksStep(
      icon: resolveIconData(map['icon'] as String?),
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
    );
  }
}

// ── Approved default steps ────────────────────────────────────────────────────

const _kDefaultSteps = [
  HowItWorksStep(
    icon: Icons.search_rounded,
    title: 'Choose a Service',
    description: 'Browse our wide range of professional home services and find exactly what you need.',
  ),
  HowItWorksStep(
    icon: Icons.access_time_rounded,
    title: 'Pick a Time',
    description: 'Select a date and time slot that works best for your schedule.',
  ),
  HowItWorksStep(
    icon: Icons.verified_user_rounded,
    title: 'Book a Professional',
    description: 'Get matched with a verified, background-checked professional near you.',
  ),
  HowItWorksStep(
    icon: Icons.check_circle_rounded,
    title: 'Get It Done',
    description: 'Relax while our expert handles the job to your complete satisfaction.',
  ),
];

// ── Widget ────────────────────────────────────────────────────────────────────

class HowItWorksSection extends StatelessWidget {
  const HowItWorksSection({
    super.key,
    this.title,
    this.steps,
  });

  /// Section heading. Defaults to 'How DODO Booker Works'.
  final String? title;

  /// Step list driven by CMS config. Falls back to [_kDefaultSteps] when null.
  final List<HowItWorksStep>? steps;

  @override
  Widget build(BuildContext context) {
    final effectiveTitle = title ?? 'How DODO Booker Works';
    final effectiveSteps = (steps?.isNotEmpty == true) ? steps! : _kDefaultSteps;
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 768;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isDesktop ? 24 : 16),
      padding: EdgeInsets.all(isDesktop ? 40 : 24),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            effectiveTitle,
            style: TextStyle(
              fontSize: isDesktop ? 22 : 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.2,
              letterSpacing: -0.3,
            ),
          ),
          SizedBox(height: isDesktop ? 36 : 28),
          // Steps
          isDesktop
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = 0; i < effectiveSteps.length; i++) ...[
                      if (i > 0) _Connector(),
                      Expanded(
                        child: _StepCard(
                          step: effectiveSteps[i],
                          stepNumber: i + 1,
                        ),
                      ),
                    ],
                  ],
                )
              : Column(
                  children: [
                    for (int i = 0; i < effectiveSteps.length; i++) ...[
                      if (i > 0) const SizedBox(height: 20),
                      _StepRow(
                        step: effectiveSteps[i],
                        stepNumber: i + 1,
                      ),
                    ],
                  ],
                ),
        ],
      ),
    );
  }
}

// ── Desktop step card ─────────────────────────────────────────────────────────

class _StepCard extends StatelessWidget {
  const _StepCard({required this.step, required this.stepNumber});
  final HowItWorksStep step;
  final int stepNumber;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Step number badge + icon
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(18),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.gold.withAlpha(100),
                  width: 1.5,
                ),
              ),
              child: Icon(step.icon, size: 28, color: AppColors.gold),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: AppColors.gold,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$stepNumber',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          step.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          step.description,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withAlpha(178),
            height: 1.55,
          ),
        ),
      ],
    );
  }
}

// ── Mobile step row ────────────────────────────────────────────────────────────

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.stepNumber});
  final HowItWorksStep step;
  final int stepNumber;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(18),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.gold.withAlpha(100),
                  width: 1.5,
                ),
              ),
              child: Icon(step.icon, size: 22, color: AppColors.gold),
            ),
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  color: AppColors.gold,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$stepNumber',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                step.description,
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.white.withAlpha(178),
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Horizontal connector line between desktop step cards ──────────────────────

class _Connector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: SizedBox(
        width: 24,
        height: 1,
        child: Container(
          color: AppColors.gold.withAlpha(80),
        ),
      ),
    );
  }
}
