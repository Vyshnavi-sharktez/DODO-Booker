import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_modal_dialog.dart';
import '../providers/loyalty_providers.dart';

class LoyaltyModal extends ConsumerWidget {
  const LoyaltyModal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loyaltyAsync = ref.watch(customerLoyaltyProvider);

    return AppModalDialog(
      title: 'DODO Points',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          loyaltyAsync.when(
            loading: () => const _BalanceShimmer(),
            error: (_, __) => const SizedBox.shrink(),
            data: (loyalty) => _BalanceCard(
              availablePoints: loyalty.availablePoints,
              lifetimeEarned: loyalty.lifetimeEarned,
            ),
          ),
          const SizedBox(height: 20),
          const _HowItWorksSection(),
        ],
      ),
    );
  }
}

// ── Balance card ──────────────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  final int availablePoints;
  final int lifetimeEarned;

  const _BalanceCard({
    required this.availablePoints,
    required this.lifetimeEarned,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withAlpha(40),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.stars_rounded,
                  color: Color(0xFFFFD700), size: 18),
              const SizedBox(width: 6),
              Text(
                'Available Points',
                style: tt.labelSmall?.copyWith(
                  color: Colors.white.withAlpha(180),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$availablePoints',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 52,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 14),
          Container(height: 0.5, color: Colors.white.withAlpha(40)),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.trending_up_rounded,
                  color: Color(0xFF66BB6A), size: 15),
              const SizedBox(width: 6),
              Text(
                '$lifetimeEarned pts earned lifetime',
                style: tt.labelSmall
                    ?.copyWith(color: Colors.white.withAlpha(153)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalanceShimmer extends StatelessWidget {
  const _BalanceShimmer();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

// ── How it works ──────────────────────────────────────────────────────────────

class _HowItWorksSection extends StatelessWidget {
  const _HowItWorksSection();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How it works',
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        const _InfoRow(
          icon: Icons.add_circle_outline_rounded,
          color: Color(0xFF66BB6A),
          text: 'Earn 10 points for every ₹100 spent on completed bookings.',
        ),
        const SizedBox(height: 10),
        const _InfoRow(
          icon: Icons.currency_rupee_rounded,
          color: Color(0xFFFFD700),
          text: '1 Point = ₹1.',
        ),
        const SizedBox(height: 10),
        const _InfoRow(
          icon: Icons.lock_outline_rounded,
          color: AppColors.textHint,
          text: 'Minimum 100 points required to redeem.',
        ),
        const SizedBox(height: 10),
        const _InfoRow(
          icon: Icons.percent_rounded,
          color: AppColors.textHint,
          text:
              'Maximum 20% of the booking amount can be paid using points.',
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _InfoRow(
      {required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
          ),
        ),
      ],
    );
  }
}
