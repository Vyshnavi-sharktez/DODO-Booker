import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/sms_config_providers.dart';
import '../widgets/sms_provider_card.dart';

// ── Provider definitions ──────────────────────────────────────────────────────
// To add a new primary provider: replace _msg91 or promote from _genericHttp.
// To add another advanced provider: add to the _AdvancedSection child list.

const _msg91 = SmsProviderDefinition(
  provider: 'msg91',
  title: 'MSG91',
  icon: Icons.sms_rounded,
  color: Color(0xFF1A73E8),
  description: 'Transactional OTP via MSG91 — India-first SMS gateway',
  apiUrlHint: 'https://api.msg91.com/api/v5/otp',
  secrets: [
    SmsSecretDef(
      secretName: 'api_key',
      label: 'Auth Key',
      hint: 'MSG91 Auth Key from the MSG91 Dashboard',
    ),
  ],
  extraFields: [
    SmsExtraFieldDef(
      key: 'template_id',
      label: 'OTP Template ID',
      hint: 'MSG91 template ID for OTP delivery',
      required: true,
    ),
    SmsExtraFieldDef(
      key: 'sender_id',
      label: 'Sender ID',
      hint: 'e.g. DODOOK — 6-char approved sender',
    ),
    SmsExtraFieldDef(
      key: 'test_phone',
      label: 'Test Phone (Campaigns)',
      hint: 'E.164 format, e.g. +919876543210 — used by SMS Campaigns in test mode',
    ),
  ],
);

const _genericHttp = SmsProviderDefinition(
  provider: 'generic_http',
  title: 'Generic HTTP',
  icon: Icons.http_rounded,
  color: Color(0xFF7B61FF),
  description: 'Configurable HTTP adapter — use with any REST-based SMS provider',
  apiUrlHint: 'https://your-sms-provider.example.com/api/send',
  secrets: [
    SmsSecretDef(
      secretName: 'api_key',
      label: 'API Key / Secret',
      hint: 'Provider API key — stored encrypted in Vault',
    ),
  ],
  extraFields: [
    SmsExtraFieldDef(
      key: 'method',
      label: 'HTTP Method',
      hint: 'POST (default) or GET',
    ),
    SmsExtraFieldDef(
      key: 'auth_header',
      label: 'Authorization Header',
      hint: 'e.g. Bearer {{api_key}} or Token {{api_key}}',
    ),
    SmsExtraFieldDef(
      key: 'body_template',
      label: 'Request Body Template',
      hint: '{"phone":"{{phone}}","otp":"{{otp}}"} — use {{phone}}, {{otp}}, {{api_key}}',
    ),
  ],
);

// ── Page ──────────────────────────────────────────────────────────────────────

class SmsConfigPage extends ConsumerWidget {
  const SmsConfigPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configsAsync = ref.watch(smsConfigNotifierProvider);

    return configsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        error: e.toString(),
        onRetry: () => ref.read(smsConfigNotifierProvider.notifier).refresh(),
      ),
      data: (_) => const _SmsConfigBody(),
    );
  }
}

class _SmsConfigBody extends StatelessWidget {
  const _SmsConfigBody();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPageHeader(),
          const SizedBox(height: 24),
          const SmsProviderCard(key: ValueKey('msg91'), definition: _msg91),
          const SizedBox(height: 16),
          const _AdvancedSection(),
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
                color: const Color(0xFF1A73E8).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.sms_rounded,
                color: Color(0xFF1A73E8),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SMS / OTP Configuration',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'Configure SMS providers for customer and vendor OTP authentication',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.warning),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'API Keys are write-only. '
                  'Values are encrypted server-side via Supabase Vault and are never shown after saving. '
                  'Enabling a provider here does not activate the Auth hook — '
                  'that must also be configured in the Supabase Dashboard.',
                  style: TextStyle(fontSize: 12, color: AppColors.warning),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Advanced / Other Providers collapsible ────────────────────────────────────

class _AdvancedSection extends StatefulWidget {
  const _AdvancedSection();

  @override
  State<_AdvancedSection> createState() => _AdvancedSectionState();
}

class _AdvancedSectionState extends State<_AdvancedSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.textSecondary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Advanced / Other Providers',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Generic HTTP adapter for any REST-based SMS provider',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _expanded
                ? const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: SmsProviderCard(
                      key: ValueKey('generic_http'),
                      definition: _genericHttp,
                    ),
                  )
                : const SizedBox.shrink(),
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
              'Failed to load SMS configuration',
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
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
