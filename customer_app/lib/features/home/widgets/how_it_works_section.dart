import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/icon_resolver.dart';

// ── Public data model (used by CMS renderer) ──────────────────────────────────

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

// ── Default steps (approved Phase 1 content) ──────────────────────────────────

const _kDefaultSteps = [
  HowItWorksStep(
    icon: Icons.grid_view_rounded,
    title: 'Choose a Service',
    description: 'Browse and select the service you need from our catalogue.',
  ),
  HowItWorksStep(
    icon: Icons.schedule_rounded,
    title: 'Pick a Time',
    description: 'Select your preferred date and time slot.',
  ),
  HowItWorksStep(
    icon: Icons.person_rounded,
    title: 'Book a Professional',
    description: 'We match you with a trusted, verified professional.',
  ),
  HowItWorksStep(
    icon: Icons.check_circle_outline_rounded,
    title: 'Get It Done',
    description: 'Sit back while we take care of it, every time.',
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
    final effectiveSteps =
        (steps?.isNotEmpty == true) ? steps! : _kDefaultSteps;

    // Convert public CMS steps to internal _WorkStep with auto-assigned
    // numbered labels and cycling step colors from the approved palette.
    const stepColors = [
      AppColors.stepGold,
      AppColors.stepTeal,
      AppColors.stepCoral,
      AppColors.stepBrown,
    ];
    final workSteps = [
      for (int i = 0; i < effectiveSteps.length; i++)
        _WorkStep(
          number: (i + 1).toString().padLeft(2, '0'),
          color: stepColors[i % stepColors.length],
          icon: effectiveSteps[i].icon,
          title: effectiveSteps[i].title,
          description: effectiveSteps[i].description,
        ),
    ];

    final isDesktop = MediaQuery.of(context).size.width >= 768;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 24 : 20,
        vertical: 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            effectiveTitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: isDesktop ? 32 : 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          SizedBox(height: isDesktop ? 36 : 24),
          isDesktop
              ? _DesktopRow(steps: workSteps)
              : _MobileRow(steps: workSteps),
        ],
      ),
    );
  }
}

// ── Desktop: horizontal row with CustomPaint connectors ──────────────────────

class _DesktopRow extends StatelessWidget {
  final List<_WorkStep> steps;
  const _DesktopRow({required this.steps});

  // icon center y from step-item top: number(~30px) + gap(12) + half-circle(32) = 74
  static const double _connectorY = 74.0;
  static const double _iconR = 32.0; // half of 64px circle

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _StepConnectorPainter(
              stepCount: steps.length,
              iconCenterY: _connectorY,
              iconRadius: _iconR,
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final step in steps) Expanded(child: _DesktopStepItem(step: step)),
          ],
        ),
      ],
    );
  }
}

class _DesktopStepItem extends StatelessWidget {
  final _WorkStep step;
  const _DesktopStepItem({required this.step});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          step.number,
          style: GoogleFonts.poppins(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: step.color,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: Color(0xFFF2EFE9),
            shape: BoxShape.circle,
          ),
          child: Icon(step.icon, size: 26, color: AppColors.primary),
        ),
        const SizedBox(height: 16),
        Text(
          step.title,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          step.description,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: const Color(0xFF9A948C),
            height: 1.55,
          ),
        ),
      ],
    );
  }
}

// ── Mobile: compact horizontal row with CustomPaint connectors ───────────────

class _MobileRow extends StatelessWidget {
  final List<_WorkStep> steps;
  const _MobileRow({required this.steps});

  // icon center y: number(~14px) + gap(5) + half-circle(17) = 36
  static const double _connectorY = 36.0;
  static const double _iconR = 17.0; // half of 34px circle

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _StepConnectorPainter(
              stepCount: steps.length,
              iconCenterY: _connectorY,
              iconRadius: _iconR,
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final step in steps) Expanded(child: _MobileStepItem(step: step)),
          ],
        ),
      ],
    );
  }
}

class _MobileStepItem extends StatelessWidget {
  final _WorkStep step;
  const _MobileStepItem({required this.step});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          step.number,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: step.color,
          ),
        ),
        const SizedBox(height: 5),
        Container(
          width: 34,
          height: 34,
          decoration: const BoxDecoration(
            color: Color(0xFFF2EFE9),
            shape: BoxShape.circle,
          ),
          child: Icon(step.icon, size: 14, color: AppColors.primary),
        ),
        const SizedBox(height: 8),
        Text(
          step.title,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

// ── Connector painter ─────────────────────────────────────────────────────────

class _StepConnectorPainter extends CustomPainter {
  final int stepCount;
  final double iconCenterY;
  final double iconRadius;

  const _StepConnectorPainter({
    required this.stepCount,
    required this.iconCenterY,
    required this.iconRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFECE7DE)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final stepW = size.width / stepCount;
    for (int i = 0; i < stepCount - 1; i++) {
      final cx1 = (i + 0.5) * stepW;
      final cx2 = (i + 1.5) * stepW;
      final x1 = cx1 + iconRadius + 6;
      final x2 = cx2 - iconRadius - 6;
      if (x2 > x1) {
        canvas.drawLine(
          Offset(x1, iconCenterY),
          Offset(x2, iconCenterY),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_StepConnectorPainter old) =>
      old.stepCount != stepCount ||
      old.iconCenterY != iconCenterY ||
      old.iconRadius != iconRadius;
}

// ── Internal data model ───────────────────────────────────────────────────────

class _WorkStep {
  final String number;
  final Color color;
  final IconData icon;
  final String title;
  final String description;

  const _WorkStep({
    required this.number,
    required this.color,
    required this.icon,
    required this.title,
    required this.description,
  });
}
