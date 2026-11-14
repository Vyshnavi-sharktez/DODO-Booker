import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../payment_config/presentation/widgets/secret_field_widget.dart';
import '../../application/providers/bot_config_providers.dart';
import '../../domain/models/bot_config.dart';

// ── Model options ─────────────────────────────────────────────────────────────

class _ModelOption {
  final String value;
  final String label;
  const _ModelOption(this.value, this.label);
}

const _geminiModels = [
  _ModelOption('gemini-2.5-flash', 'Gemini 2.5 Flash — Stable, recommended'),
  _ModelOption('gemini-3.5-flash-lite', 'Gemini 3.5 Flash Lite — Light + Fast'),
  _ModelOption('gemini-3.5-flash', 'Gemini 3.5 Flash — Newer'),
  _ModelOption('gemini-3.8-flash', 'Gemini 3.8 Flash — Latest'),
];

// ── Page ──────────────────────────────────────────────────────────────────────

class BotConfigPage extends ConsumerWidget {
  const BotConfigPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(botConfigNotifierProvider);
    return configAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        error: e.toString(),
        onRetry: () => ref.read(botConfigNotifierProvider.notifier).refresh(),
      ),
      data: (config) => config == null
          ? const Center(
              child: Text(
                'Bot configuration not found. Apply the migration first.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          : _BotConfigBody(config: config),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _BotConfigBody extends ConsumerStatefulWidget {
  const _BotConfigBody({required this.config});
  final BotConfig config;

  @override
  ConsumerState<_BotConfigBody> createState() => _BotConfigBodyState();
}

class _BotConfigBodyState extends ConsumerState<_BotConfigBody> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _systemPromptCtrl;
  late final TextEditingController _maxHistoryCtrl;
  late final TextEditingController _handoffTriggersCtrl;
  late final TextEditingController _closeTriggersCtrl;
  late final TextEditingController _msgRetentionCtrl;
  late final TextEditingController _convRetentionCtrl;
  late final TextEditingController _handoffTimeoutCtrl;
  late final TextEditingController _handoffTimeoutMsgCtrl;

  late String _selectedModel;
  late bool _isEnabled;
  bool _dirty = false;
  bool _saving = false;
  final _apiKeyStatus = ValueNotifier<bool>(false);
  final _anonKeyCtrl = TextEditingController();
  bool _anonKeySaving = false;
  bool _anonKeyObscure = true;

  @override
  void initState() {
    super.initState();
    _isEnabled = widget.config.isEnabled;
    _selectedModel = widget.config.model;
    _systemPromptCtrl =
        TextEditingController(text: widget.config.systemPrompt);
    _maxHistoryCtrl =
        TextEditingController(text: widget.config.maxHistory.toString());
    _handoffTriggersCtrl =
        TextEditingController(text: widget.config.handoffTriggers);
    _closeTriggersCtrl =
        TextEditingController(text: widget.config.closeTriggers);
    _msgRetentionCtrl =
        TextEditingController(text: widget.config.messageRetentionDays.toString());
    _convRetentionCtrl =
        TextEditingController(text: widget.config.conversationRetentionDays.toString());
    _handoffTimeoutCtrl =
        TextEditingController(text: widget.config.handoffTimeoutMinutes.toString());
    _handoffTimeoutMsgCtrl =
        TextEditingController(text: widget.config.handoffTimeoutMessage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSecretStatus();
      _loadAnonKey();
    });
  }

  @override
  void dispose() {
    _systemPromptCtrl.dispose();
    _maxHistoryCtrl.dispose();
    _handoffTriggersCtrl.dispose();
    _closeTriggersCtrl.dispose();
    _msgRetentionCtrl.dispose();
    _convRetentionCtrl.dispose();
    _handoffTimeoutCtrl.dispose();
    _handoffTimeoutMsgCtrl.dispose();
    _anonKeyCtrl.dispose();
    _apiKeyStatus.dispose();
    super.dispose();
  }

  Future<void> _loadSecretStatus() async {
    try {
      final isSet = await ref
          .read(botConfigNotifierProvider.notifier)
          .secretIsSet('gemini_api_key');
      if (mounted) _apiKeyStatus.value = isSet;
    } catch (_) {}
  }

  Future<void> _loadAnonKey() async {
    try {
      final key = await ref
          .read(botConfigNotifierProvider.notifier)
          .fetchAnonKey();
      if (mounted) _anonKeyCtrl.text = key;
    } catch (_) {}
  }

  Future<void> _saveAnonKey() async {
    final value = _anonKeyCtrl.text.trim();
    if (value.isEmpty) return;
    setState(() => _anonKeySaving = true);
    try {
      await ref.read(botConfigNotifierProvider.notifier).saveAnonKey(value);
      if (mounted) {
        setState(() => _anonKeySaving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Supabase Anon Key saved'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          width: 360,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _anonKeySaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save anon key: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          width: 360,
        ));
      }
    }
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final notifier = ref.read(botConfigNotifierProvider.notifier);
      final current = ref.read(botConfigNotifierProvider).valueOrNull;
      if (current == null) return;
      await notifier.saveConfig(current.copyWith(
        isEnabled: _isEnabled,
        model: _selectedModel,
        systemPrompt: _systemPromptCtrl.text.trim(),
        maxHistory:
            int.tryParse(_maxHistoryCtrl.text.trim()) ?? current.maxHistory,
        handoffTriggers: _handoffTriggersCtrl.text.trim(),
        closeTriggers: _closeTriggersCtrl.text.trim(),
        messageRetentionDays:
            int.tryParse(_msgRetentionCtrl.text.trim()) ?? current.messageRetentionDays,
        conversationRetentionDays:
            int.tryParse(_convRetentionCtrl.text.trim()) ?? current.conversationRetentionDays,
        handoffTimeoutMinutes:
            int.tryParse(_handoffTimeoutCtrl.text.trim()) ?? current.handoffTimeoutMinutes,
        handoffTimeoutMessage: _handoffTimeoutMsgCtrl.text.trim().isNotEmpty
            ? _handoffTimeoutMsgCtrl.text.trim()
            : current.handoffTimeoutMessage,
      ));
      if (mounted) {
        setState(() {
          _dirty = false;
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bot configuration saved'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          width: 360,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          width: 360,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPageHeader(),
          const SizedBox(height: 24),
          _buildConfigCard(),
        ],
      ),
    );
  }

  // ── Page header ─────────────────────────────────────────────────────────────

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
                color: const Color(0xFF4285F4).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.smart_toy_rounded,
                color: Color(0xFF4285F4),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Support Bot',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'Gemini-powered auto-replies for customer support chat',
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
            border:
                Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.lock_outline_rounded,
                  size: 16, color: AppColors.warning),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'API Keys are write-only. Values are encrypted server-side via Supabase Vault and are never shown after saving.',
                  style: TextStyle(fontSize: 12, color: AppColors.warning),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Config card ─────────────────────────────────────────────────────────────

  Widget _buildConfigCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCardHeader(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildToggle(
                    label: 'Enable Support Bot',
                    hint:
                        'Bot auto-replies to customer messages until a human admin responds',
                    value: _isEnabled,
                    onChanged: (v) => setState(() {
                      _isEnabled = v;
                      _markDirty();
                    }),
                  ),
                  const SizedBox(height: 20),
                  _buildSectionLabel('Gemini Settings'),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: _geminiModels.any((m) => m.value == _selectedModel)
                        ? _selectedModel
                        : _geminiModels.first.value,
                    decoration:
                        const InputDecoration(labelText: 'Gemini Model'),
                    items: [
                      for (final opt in _geminiModels)
                        DropdownMenuItem(
                          value: opt.value,
                          child: Text(opt.label,
                              style: const TextStyle(fontSize: 13)),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _selectedModel = v;
                          _markDirty();
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  ValueListenableBuilder<bool>(
                    valueListenable: _apiKeyStatus,
                    builder: (context, isSet, _) => SecretFieldWidget(
                      label: 'Gemini API Key',
                      hint: 'From Google AI Studio (aistudio.google.com)',
                      isConfigured: isSet,
                      onSave: (value) async {
                        await ref
                            .read(botConfigNotifierProvider.notifier)
                            .setSecret('gemini_api_key', value);
                        _apiKeyStatus.value = true;
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildAnonKeyField(),
                  const SizedBox(height: 20),
                  _buildSectionLabel('Bot Behaviour'),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _systemPromptCtrl,
                    decoration: const InputDecoration(
                      labelText: 'System Prompt',
                      hintText:
                          'Describe what the bot is, what it can help with, its tone...',
                      alignLabelWithHint: true,
                    ),
                    maxLines: 6,
                    onChanged: (_) => _markDirty(),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _maxHistoryCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Max Conversation History',
                      hintText: '10',
                      suffixText: 'messages',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    onChanged: (_) => _markDirty(),
                    validator: (v) {
                      final n = int.tryParse(v?.trim() ?? '');
                      if (n == null || n < 1 || n > 50) {
                        return 'Enter a number between 1 and 50';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _handoffTriggersCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Human Handoff Triggers',
                      hintText: 'agent, human, talk to person, real person',
                      helperText:
                          'Comma-separated — if customer message contains any, bot sends a handoff reply and stops',
                    ),
                    onChanged: (_) => _markDirty(),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _closeTriggersCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Auto-Close Triggers',
                      hintText: "that's all, bye, goodbye, i'm done",
                      helperText:
                          "Comma-separated — bot sends a farewell and closes the chat",
                    ),
                    onChanged: (_) => _markDirty(),
                  ),
                  const SizedBox(height: 10),
                  _buildWebhookNote(),
                  const SizedBox(height: 20),
                  _buildSectionLabel('Data Retention'),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _msgRetentionCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Message Retention',
                            suffixText: 'days',
                            helperText: '0 = never delete',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          onChanged: (_) => _markDirty(),
                          validator: (v) {
                            final n = int.tryParse(v?.trim() ?? '');
                            if (n == null || n < 0) return 'Enter 0 or more';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _convRetentionCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Conversation Retention',
                            suffixText: 'days',
                            helperText: '0 = never delete',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          onChanged: (_) => _markDirty(),
                          validator: (v) {
                            final n = int.tryParse(v?.trim() ?? '');
                            if (n == null || n < 0) return 'Enter 0 or more';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildSectionLabel('No-Agent Fallback'),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _handoffTimeoutCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Fallback Timeout',
                      suffixText: 'minutes',
                      helperText: '0 = disabled — bot sends no follow-up if no agent replies',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => _markDirty(),
                    validator: (v) {
                      final n = int.tryParse(v?.trim() ?? '');
                      if (n == null || n < 0) return 'Enter 0 or more';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _handoffTimeoutMsgCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Fallback Message',
                      hintText:
                          'Message sent to customer when no agent replies in time',
                      alignLabelWithHint: true,
                    ),
                    maxLines: 3,
                    onChanged: (_) => _markDirty(),
                    validator: (v) {
                      final timeout =
                          int.tryParse(_handoffTimeoutCtrl.text.trim()) ?? 0;
                      if (timeout > 0 && (v == null || v.trim().isEmpty)) {
                        return 'Enter a fallback message or set timeout to 0';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildCardHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configuration',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'Settings are applied immediately — no bot restart needed',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (_dirty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Unsaved',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.warning,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: AppColors.border),
        const SizedBox(height: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildWebhookNote() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF4285F4).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: const Color(0xFF4285F4).withValues(alpha: 0.2)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 14, color: Color(0xFF4285F4)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Supabase Dashboard → Database → Webhooks → Create webhook on support_messages INSERT → URL: https://[your-project].supabase.co/functions/v1/support-bot',
              style:
                  TextStyle(fontSize: 11, color: Color(0xFF4285F4)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnonKeyField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Supabase Anon Key',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextFormField(
                controller: _anonKeyCtrl,
                obscureText: _anonKeyObscure,
                decoration: InputDecoration(
                  hintText: 'Supabase anon public key (Settings → API)',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _anonKeyObscure
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () =>
                        setState(() => _anonKeyObscure = !_anonKeyObscure),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            AnimatedOpacity(
              opacity: _anonKeyCtrl.text.trim().isNotEmpty ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: FilledButton(
                onPressed: (_anonKeyCtrl.text.trim().isNotEmpty && !_anonKeySaving)
                    ? _saveAnonKey
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                child: _anonKeySaving
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Required for the bot trigger to authenticate with Supabase Edge Functions.',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FilledButton.icon(
            onPressed: (_dirty && !_saving) ? _save : null,
            icon: _saving
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded, size: 16),
            label: const Text('Save Changes'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor: AppColors.border,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle({
    required String label,
    required String hint,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.success,
          ),
        ],
      ),
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
              child: const Icon(Icons.error_outline_rounded,
                  size: 32, color: AppColors.error),
            ),
            const SizedBox(height: 20),
            const Text(
              'Failed to load bot configuration',
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
