import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/whatsapp_config_providers.dart';
import '../widgets/provider_config_card.dart';

// ── Provider registry ─────────────────────────────────────────────────────────
// To add a second provider (e.g. Twilio): append a ProviderDefinition here.
// No repository, table, or RPC changes required.

const _providers = <ProviderDefinition>[
  ProviderDefinition(
    provider: 'interakt',
    title: 'Interakt',
    icon: Icons.chat_rounded,
    color: Color(0xFF25D366),
    description:
        'WhatsApp Business API via Interakt — save now, activate when ready',
    apiUrlHint: 'https://api.interakt.ai/v1/public/message/',
    secrets: [
      ProviderSecretDef(
        secretName: 'api_key',
        label: 'API Key',
        hint: 'Interakt API Key from the Interakt Dashboard (optional)',
      ),
    ],
    // extraFields intentionally empty: template configuration belongs in the
    // provider dashboard, not here. Add ExtraFieldDef entries here when
    // per-booking template routing is implemented.
  ),
];

// ── Page ──────────────────────────────────────────────────────────────────────

class WhatsappConfigPage extends ConsumerWidget {
  const WhatsappConfigPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configsAsync = ref.watch(whatsappConfigNotifierProvider);

    return configsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        error: e.toString(),
        onRetry: () =>
            ref.read(whatsappConfigNotifierProvider.notifier).refresh(),
      ),
      data: (_) => const _WhatsappConfigBody(),
    );
  }
}

class _WhatsappConfigBody extends StatelessWidget {
  const _WhatsappConfigBody();

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
                    for (int i = 0; i < _providers.length; i++) ...[
                      ProviderConfigCard(
                        key: ValueKey(_providers[i].provider),
                        definition: _providers[i],
                      ),
                      if (i < _providers.length - 1)
                        const SizedBox(height: 20),
                    ],
                  ],
                );
              }

              final left = <ProviderDefinition>[];
              final right = <ProviderDefinition>[];
              for (int i = 0; i < _providers.length; i++) {
                if (i.isEven) {
                  left.add(_providers[i]);
                } else {
                  right.add(_providers[i]);
                }
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        for (int i = 0; i < left.length; i++) ...[
                          ProviderConfigCard(
                            key: ValueKey(left[i].provider),
                            definition: left[i],
                          ),
                          if (i < left.length - 1)
                            const SizedBox(height: 20),
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
                            ProviderConfigCard(
                              key: ValueKey(right[i].provider),
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
                color: const Color(0xFF25D366).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.chat_rounded,
                color: Color(0xFF25D366),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WhatsApp Configuration',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'Configure WhatsApp messaging providers for customer notifications',
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
                  'API Keys are write-only. '
                  'Values are encrypted server-side via Supabase Vault and are never shown after saving.',
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
              'Failed to load WhatsApp configuration',
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
