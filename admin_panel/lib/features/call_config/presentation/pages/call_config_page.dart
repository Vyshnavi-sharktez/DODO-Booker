import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/call_config_providers.dart';
import '../../domain/models/call_provider_config.dart';

class CallConfigPage extends ConsumerWidget {
  const CallConfigPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(callConfigProvider);

    return configAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        error: e.toString(),
        onRetry: () => ref.invalidate(callConfigProvider),
      ),
      data: (config) => _CallConfigBody(config: config),
    );
  }
}

class _CallConfigBody extends ConsumerStatefulWidget {
  final CallProviderConfig config;
  const _CallConfigBody({required this.config});

  @override
  ConsumerState<_CallConfigBody> createState() => _CallConfigBodyState();
}

class _CallConfigBodyState extends ConsumerState<_CallConfigBody> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _accountSidCtrl;
  late final TextEditingController _exophoneCtrl;
  late final TextEditingController _apiKeyCtrl;
  late final TextEditingController _apiTokenCtrl;
  late final TextEditingController _webhookTokenCtrl;
  late final TextEditingController _timeoutCtrl;
  late bool _isEnabled;
  late bool _recordCalls;

  bool _apiKeySet = false;
  bool _apiTokenSet = false;
  bool _webhookTokenSet = false;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _accountSidCtrl = TextEditingController(text: widget.config.accountSid ?? '');
    _exophoneCtrl = TextEditingController(text: widget.config.exophone ?? '');
    _apiKeyCtrl = TextEditingController();
    _apiTokenCtrl = TextEditingController();
    _webhookTokenCtrl = TextEditingController();
    _timeoutCtrl = TextEditingController(
        text: widget.config.callTimeoutSeconds.toString());
    _isEnabled = widget.config.isEnabled;
    _recordCalls = widget.config.recordCalls;
    _checkSecretStatus();
  }

  Future<void> _checkSecretStatus() async {
    final repo = ref.read(callConfigRepositoryProvider);
    final results = await Future.wait([
      repo.secretIsSet('api_key'),
      repo.secretIsSet('api_token'),
      repo.secretIsSet('webhook_token'),
    ]);
    if (mounted) {
      setState(() {
        _apiKeySet = results[0];
        _apiTokenSet = results[1];
        _webhookTokenSet = results[2];
      });
    }
  }

  void _markDirty() => setState(() => _dirty = true);

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      final repo = ref.read(callConfigRepositoryProvider);

      // Save non-secret config
      await repo.saveConfig(
        isEnabled: _isEnabled,
        accountSid: _accountSidCtrl.text.trim(),
        exophone: _exophoneCtrl.text.trim(),
        recordCalls: _recordCalls,
        callTimeoutSeconds: int.tryParse(_timeoutCtrl.text.trim()) ?? 30,
      );

      // Save secrets if provided
      if (_apiKeyCtrl.text.trim().isNotEmpty) {
        await repo.saveSecret(secretName: 'api_key', value: _apiKeyCtrl.text.trim());
        _apiKeyCtrl.clear();
        _apiKeySet = true;
      }
      if (_apiTokenCtrl.text.trim().isNotEmpty) {
        await repo.saveSecret(secretName: 'api_token', value: _apiTokenCtrl.text.trim());
        _apiTokenCtrl.clear();
        _apiTokenSet = true;
      }
      if (_webhookTokenCtrl.text.trim().isNotEmpty) {
        await repo.saveSecret(
            secretName: 'webhook_token', value: _webhookTokenCtrl.text.trim());
        _webhookTokenCtrl.clear();
        _webhookTokenSet = true;
      }

      ref.invalidate(callConfigProvider);

      if (mounted) {
        setState(() => _dirty = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Call configuration saved.'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _accountSidCtrl.dispose();
    _exophoneCtrl.dispose();
    _apiKeyCtrl.dispose();
    _apiTokenCtrl.dispose();
    _webhookTokenCtrl.dispose();
    _timeoutCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            _buildStatusCard(),
            const SizedBox(height: 16),
            _buildConfigCard(),
            const SizedBox(height: 16),
            _buildSecretsCard(),
            const SizedBox(height: 16),
            _buildCallSettingsCard(),
            const SizedBox(height: 24),
            _buildPrerequisitesCard(),
            const SizedBox(height: 24),
            _buildSaveButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF1A73E8).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.phone_in_talk_rounded,
              color: Color(0xFF1A73E8), size: 22),
        ),
        const SizedBox(width: 14),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Call Provider — Exotel',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
            Text(
              'Secure number-masked voice calls between customers and vendors',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusCard() {
    final isConfigured = widget.config.isConfigured && _apiKeySet && _apiTokenSet;
    final statusColor = _isEnabled && isConfigured
        ? AppColors.success
        : (_isEnabled && !isConfigured ? AppColors.warning : AppColors.textSecondary);
    final statusLabel = _isEnabled && isConfigured
        ? 'Active'
        : (_isEnabled && !isConfigured ? 'Enabled — Credentials Incomplete' : 'Disabled');

    return _ConfigCard(
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Status: $statusLabel',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: statusColor),
            ),
          ),
          Switch(
            value: _isEnabled,
            activeColor: AppColors.success,
            onChanged: (v) {
              setState(() {
                _isEnabled = v;
                _dirty = true;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildConfigCard() {
    return _ConfigCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel(label: 'Exotel Account'),
          const SizedBox(height: 16),
          TextFormField(
            controller: _accountSidCtrl,
            onChanged: (_) => _markDirty(),
            decoration: const InputDecoration(
              labelText: 'Account SID *',
              hintText: 'e.g. exoteldemo1',
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Account SID is required' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _exophoneCtrl,
            onChanged: (_) => _markDirty(),
            decoration: const InputDecoration(
              labelText: 'ExoPhone (Virtual Number) *',
              hintText: 'e.g. +918040123456',
              helperText:
                  'The virtual number shown to both parties. Must be in E.164 format.',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'ExoPhone is required';
              if (!RegExp(r'^\+\d{7,15}$').hasMatch(v.trim())) {
                return 'Must be E.164 format (e.g. +918040123456)';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A73E8).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF1A73E8)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'The Account SID is visible in your Exotel Dashboard under '
                    'Settings → API. The ExoPhone is the virtual number purchased '
                    'from Exotel.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF1A73E8)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecretsCard() {
    return _ConfigCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel(label: 'API Credentials (Vault-Encrypted)'),
          const SizedBox(height: 16),
          _SecretField(
            label: 'API Key',
            controller: _apiKeyCtrl,
            isSet: _apiKeySet,
            hint: 'Exotel API Key (from API Settings)',
            onChanged: (_) => _markDirty(),
          ),
          const SizedBox(height: 12),
          _SecretField(
            label: 'API Token',
            controller: _apiTokenCtrl,
            isSet: _apiTokenSet,
            hint: 'Exotel API Token (from API Settings)',
            onChanged: (_) => _markDirty(),
          ),
          const SizedBox(height: 12),
          _SecretField(
            label: 'Webhook Token',
            controller: _webhookTokenCtrl,
            isSet: _webhookTokenSet,
            hint: 'Random secret appended to the StatusCallback URL',
            onChanged: (_) => _markDirty(),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.warning),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'All three secrets are stored encrypted in Supabase Vault. '
                    'They are never sent to the browser and only accessed by Edge Functions. '
                    'Generate a strong Webhook Token with: openssl rand -hex 32',
                    style: TextStyle(fontSize: 12, color: AppColors.warning),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallSettingsCard() {
    return _ConfigCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel(label: 'Call Settings'),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Record Calls',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      'Automatically record all calls via Exotel. Requires recording to be enabled on your Exotel account.',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _recordCalls,
                onChanged: (v) {
                  setState(() {
                    _recordCalls = v;
                    _dirty = true;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _timeoutCtrl,
            onChanged: (_) => _markDirty(),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Ring Timeout (seconds)',
              hintText: '30',
              helperText:
                  'How long Exotel will ring before marking as no-answer. Default: 30.',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              final n = int.tryParse(v.trim());
              if (n == null || n < 5 || n > 120) {
                return 'Must be between 5 and 120 seconds';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPrerequisitesCard() {
    return _ConfigCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel(label: 'Setup Prerequisites'),
          const SizedBox(height: 12),
          ..._prerequisites.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(p,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 16, color: AppColors.error),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Calling will not work until these prerequisites are met on '
                    'your Exotel account. Do not enable calling until end-to-end '
                    'testing confirms calls are connecting.',
                    style: TextStyle(fontSize: 12, color: AppColors.error),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _prerequisites = [
    'Active Exotel account with API access enabled.',
    'At least one ExoPhone (virtual number) purchased and active.',
    'API Key and API Token generated from Exotel Dashboard → Settings → API.',
    'Webhook Token set above (generate with: openssl rand -hex 32). '
        'Exotel callbacks are rejected until this is configured.',
    'Recording enabled on your Exotel account (if Record Calls is on).',
    'StatusCallback URL registered in your Exotel app or set per-call: '
        '{YOUR_SUPABASE_URL}/functions/v1/exotel-webhook?token=<WEBHOOK_TOKEN>',
    'All customer and vendor accounts must have verified phone numbers stored '
        'in E.164 format in Supabase Auth.',
    'India DLT/TRAI: voice calls are not subject to DLT registration, '
        'but ensure your use case complies with TRAI guidelines.',
  ];

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _dirty && !_saving ? _save : null,
        icon: _saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.save_rounded, size: 18),
        label: Text(_saving ? 'Saving…' : 'Save Configuration'),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _ConfigCard extends StatelessWidget {
  final Widget child;
  const _ConfigCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _CardLabel extends StatelessWidget {
  final String label;
  const _CardLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary),
    );
  }
}

class _SecretField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final bool isSet;
  final String hint;
  final ValueChanged<String> onChanged;

  const _SecretField({
    required this.label,
    required this.controller,
    required this.isSet,
    required this.hint,
    required this.onChanged,
  });

  @override
  State<_SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<_SecretField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(widget.label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: widget.isSet
                    ? AppColors.success.withValues(alpha: 0.1)
                    : AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                widget.isSet ? 'Saved' : 'Not set',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: widget.isSet ? AppColors.success : AppColors.warning),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: widget.controller,
          obscureText: _obscure,
          onChanged: widget.onChanged,
          decoration: InputDecoration(
            hintText: widget.isSet
                ? '••••••••••••  (leave blank to keep current)'
                : widget.hint,
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                  size: 18),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(error,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}
