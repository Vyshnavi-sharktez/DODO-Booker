import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/payment_config_providers.dart';
import '../widgets/gateway_config_card.dart';

// ── Gateway registry ──────────────────────────────────────────────────────────
// To add a new gateway (e.g. Stripe): append one GatewayDefinition here.
// No repository, table, or RPC changes required.

const _gateways = <GatewayDefinition>[
  GatewayDefinition(
    gateway: 'razorpay',
    title: 'Razorpay',
    icon: Icons.payment_rounded,
    color: Color(0xFF2D5282),
    description: 'Accept UPI, cards, wallets and net banking via Razorpay',
    secrets: [
      GatewaySecretDef(
        secretName: 'key_secret',
        label: 'API Secret',
        hint: 'Razorpay API Secret key',
      ),
      GatewaySecretDef(
        secretName: 'webhook_secret',
        label: 'Webhook Secret',
        hint: 'Razorpay Webhook Secret from the Razorpay Dashboard',
      ),
    ],
  ),
];

// ── Page ──────────────────────────────────────────────────────────────────────

class PaymentConfigPage extends ConsumerWidget {
  const PaymentConfigPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configsAsync = ref.watch(paymentGatewayConfigNotifierProvider);

    return configsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        error: e.toString(),
        onRetry: () => ref
            .read(paymentGatewayConfigNotifierProvider.notifier)
            .refresh(),
      ),
      data: (_) => _PaymentConfigBody(),
    );
  }
}

class _PaymentConfigBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPageHeader(),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoCol = constraints.maxWidth >= 860;
              if (!twoCol) {
                return Column(
                  children: [
                    for (int i = 0; i < _gateways.length; i++) ...[
                      GatewayConfigCard(
                        key: ValueKey(_gateways[i].gateway),
                        definition: _gateways[i],
                      ),
                      if (i < _gateways.length - 1)
                        const SizedBox(height: 20),
                    ],
                  ],
                );
              }

              // Two-column layout matching the Settings page grid
              final left = <GatewayDefinition>[];
              final right = <GatewayDefinition>[];
              for (int i = 0; i < _gateways.length; i++) {
                if (i.isEven) {
                  left.add(_gateways[i]);
                } else {
                  right.add(_gateways[i]);
                }
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        for (int i = 0; i < left.length; i++) ...[
                          GatewayConfigCard(
                            key: ValueKey(left[i].gateway),
                            definition: left[i],
                          ),
                          if (i < left.length - 1) const SizedBox(height: 20),
                        ],
                      ],
                    ),
                  ),
                  if (right.isNotEmpty) ...[
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        children: [
                          for (int i = 0; i < right.length; i++) ...[
                            GatewayConfigCard(
                              key: ValueKey(right[i].gateway),
                              definition: right[i],
                            ),
                            if (i < right.length - 1)
                              const SizedBox(height: 20),
                          ],
                        ],
                      ),
                    ),
                  ] else
                    const Expanded(child: SizedBox()),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPageHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.payment_rounded,
                color: AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Online Payment Configuration',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'Configure payment gateways for online transactions',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.warning.withValues(alpha: 0.3),
            ),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: AppColors.warning,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'API Secret and Webhook Secret are write-only. '
                  'Values are encrypted server-side and are never shown after saving.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Error view ────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 32,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Failed to load payment configuration',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
