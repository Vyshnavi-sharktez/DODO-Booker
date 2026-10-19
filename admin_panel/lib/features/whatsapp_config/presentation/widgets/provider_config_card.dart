import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../payment_config/presentation/widgets/secret_field_widget.dart';
import '../../application/providers/whatsapp_config_providers.dart';
import '../../domain/models/whatsapp_provider_config.dart';

// ── Provider definition ───────────────────────────────────────────────────────
// Describes the UI shape for a WhatsApp provider adapter.
// Adding a second provider (e.g. Twilio) requires only a new ProviderDefinition
// in whatsapp_config_page.dart — no changes to repository, table, or RPCs.

class ProviderSecretDef {
  final String secretName;
  final String label;
  final String? hint;

  const ProviderSecretDef({
    required this.secretName,
    required this.label,
    this.hint,
  });
}

class ExtraFieldDef {
  final String key;
  final String label;
  final String? hint;
  final bool required;

  const ExtraFieldDef({
    required this.key,
    required this.label,
    this.hint,
    this.required = false,
  });
}

class ProviderDefinition {
  final String provider;
  final String title;
  final IconData icon;
  final Color color;
  final String description;
  final String? apiUrlHint;
  final List<ProviderSecretDef> secrets;
  final List<ExtraFieldDef> extraFields;

  const ProviderDefinition({
    required this.provider,
    required this.title,
    required this.icon,
    required this.color,
    required this.description,
    this.apiUrlHint,
    this.secrets = const [],
    this.extraFields = const [],
  });
}

// ── Card ──────────────────────────────────────────────────────────────────────

class ProviderConfigCard extends ConsumerStatefulWidget {
  const ProviderConfigCard({super.key, required this.definition});
  final ProviderDefinition definition;

  @override
  ConsumerState<ProviderConfigCard> createState() => _ProviderConfigCardState();
}

class _ProviderConfigCardState extends ConsumerState<ProviderConfigCard> {
  final _formKey = GlobalKey<FormState>();
  final _providerNameCtrl = TextEditingController();
  final _apiUrlCtrl = TextEditingController();
  late final Map<String, TextEditingController> _extraCtrl;

  bool _isEnabled = false;
  bool _dirty = false;
  bool _saving = false;

  late final Map<String, ValueNotifier<bool>> _secretStatus;

  // Test message state
  final _testPhoneCtrl = TextEditingController();
  bool _testing = false;
  String? _testMessage;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    _extraCtrl = {
      for (final f in widget.definition.extraFields)
        f.key: TextEditingController(),
    };
    _secretStatus = {
      for (final s in widget.definition.secrets)
        s.secretName: ValueNotifier(false),
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _providerNameCtrl.dispose();
    _apiUrlCtrl.dispose();
    _testPhoneCtrl.dispose();
    for (final c in _extraCtrl.values) {
      c.dispose();
    }
    for (final n in _secretStatus.values) {
      n.dispose();
    }
    super.dispose();
  }

  void _init() {
    final cfg = ref
        .read(whatsappConfigNotifierProvider.notifier)
        .configFor(widget.definition.provider);
    _applyConfig(cfg);
    _loadSecretStatuses();
  }

  void _applyConfig(WhatsappProviderConfig cfg) {
    if (_dirty) return;
    _providerNameCtrl.text = cfg.providerName;
    _apiUrlCtrl.text = cfg.apiUrl;
    for (final f in widget.definition.extraFields) {
      _extraCtrl[f.key]?.text =
          (cfg.extraConfig[f.key] as String?) ?? '';
    }
    setState(() {
      _isEnabled = cfg.isEnabled;
    });
  }

  Future<void> _loadSecretStatuses() async {
    final notifier =
        ref.read(whatsappConfigNotifierProvider.notifier);
    for (final s in widget.definition.secrets) {
      try {
        final isSet = await notifier.secretIsSet(
          widget.definition.provider,
          s.secretName,
        );
        if (mounted) _secretStatus[s.secretName]?.value = isSet;
      } catch (e) {
        debugPrint(
            'WhatsApp secret status check failed for ${s.secretName}: $e');
      }
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final notifier =
          ref.read(whatsappConfigNotifierProvider.notifier);
      final existing = notifier.configFor(widget.definition.provider);
      final newExtraConfig = {
        ...existing.extraConfig,
        for (final entry in _extraCtrl.entries)
          entry.key: entry.value.text.trim(),
      };
      await notifier.saveConfig(
        existing.copyWith(
          isEnabled: _isEnabled,
          providerName: _providerNameCtrl.text.trim(),
          apiUrl: _apiUrlCtrl.text.trim(),
          extraConfig: newExtraConfig,
        ),
      );
      if (mounted) {
        setState(() {
          _dirty = false;
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.definition.title} configuration saved'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            width: 360,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            width: 360,
          ),
        );
      }
    }
  }

  Future<void> _sendTest() async {
    final phone = _testPhoneCtrl.text.trim();
    if (phone.isEmpty) return;
    setState(() {
      _testing = true;
      _testMessage = null;
    });
    try {
      final notifier =
          ref.read(whatsappConfigNotifierProvider.notifier);
      final result = await notifier.sendTestMessage(
        widget.definition.provider,
        phone,
      );
      if (mounted) {
        final success = result['success'] == true;
        setState(() {
          _testing = false;
          _testSuccess = success;
          _testMessage = success
              ? 'Test message sent successfully. Check your WhatsApp.'
              : 'Provider returned an error: ${result['provider_response'] ?? result['error'] ?? 'Unknown error'}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testing = false;
          _testSuccess = false;
          _testMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  String? _validateApiUrl(String? value) {
    // Empty is allowed — configuration can be saved for future use before
    // provider credentials are available.
    if (value == null || value.trim().isEmpty) return null;

    final v = value.trim();
    if (!v.startsWith('https://')) return 'URL must use HTTPS (https://)';
    final uri = Uri.tryParse(v);
    if (uri == null || uri.host.isEmpty) return 'Invalid URL format';
    final host = uri.host.toLowerCase();

    // Reject wa.me — that is a chat redirect link, not a messaging API endpoint.
    if (host == 'wa.me' || host.endsWith('.wa.me')) {
      return 'wa.me is a chat redirect link, not an API endpoint. '
          'Enter your WhatsApp provider\'s API URL '
          '(e.g. https://api.interakt.ai/v1/public/message/).';
    }

    // Block private/reserved IP ranges (SSRF prevention).
    if (host == 'localhost' || host == '127.0.0.1' || host == '0.0.0.0') {
      return 'Private or local addresses are not allowed';
    }
    final ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');
    final match = ipv4.firstMatch(host);
    if (match != null) {
      final a = int.parse(match.group(1)!);
      final b = int.parse(match.group(2)!);
      if (a == 10 ||
          a == 127 ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 168) ||
          (a == 169 && b == 254)) {
        return 'Private or reserved IP addresses are not allowed';
      }
    }
    return null;
  }

  bool get _apiKeySet =>
      _secretStatus[widget.definition.secrets.isNotEmpty
          ? widget.definition.secrets.first.secretName
          : '']
          ?.value ??
      false;

  bool get _canTest =>
      !_dirty &&
      _isEnabled &&
      _apiUrlCtrl.text.isNotEmpty &&
      _apiKeySet &&
      _testPhoneCtrl.text.trim().isNotEmpty &&
      !_testing;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<WhatsappProviderConfig>>>(
      whatsappConfigNotifierProvider,
      (_, next) => next.whenOrNull(
        data: (configs) {
          final cfg = configs.firstWhere(
            (c) => c.provider == widget.definition.provider,
            orElse: () =>
                WhatsappProviderConfig.empty(widget.definition.provider),
          );
          _applyConfig(cfg);
        },
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          _buildBody(),
          _buildActions(),
          _buildTestSection(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: widget.definition.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              widget.definition.icon,
              color: widget.definition.color,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.definition.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  widget.definition.description,
                  style: const TextStyle(
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

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildToggle(
              label: 'Enable Provider',
              hint:
                  'Allow sending WhatsApp messages via ${widget.definition.title}',
              value: _isEnabled,
              onChanged: (v) => setState(() {
                _isEnabled = v;
                _markDirty();
              }),
            ),
            const SizedBox(height: 14),

            // Provider display name
            TextFormField(
              controller: _providerNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Provider Name',
                hintText: 'e.g. Interakt',
              ),
              onChanged: (_) => _markDirty(),
              validator: (v) => (v?.trim().isEmpty ?? true)
                  ? 'Provider name is required'
                  : null,
            ),
            const SizedBox(height: 14),

            // API endpoint URL
            TextFormField(
              controller: _apiUrlCtrl,
              decoration: InputDecoration(
                labelText: 'API Endpoint URL',
                hintText: widget.definition.apiUrlHint ?? 'https://',
              ),
              onChanged: (_) {
                _markDirty();
                setState(() {}); // refresh _canTest
              },
              validator: _validateApiUrl,
              keyboardType: TextInputType.url,
            ),

            // Secrets section
            if (widget.definition.secrets.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Divider(color: AppColors.border),
              const SizedBox(height: 4),
              const Text(
                'Secrets — write-only. Values are never displayed after saving.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              for (int i = 0;
                  i < widget.definition.secrets.length;
                  i++) ...[
                _buildSecretField(widget.definition.secrets[i]),
                if (i < widget.definition.secrets.length - 1)
                  const SizedBox(height: 14),
              ],
            ],

            // Extra config fields (template name, language code, etc.)
            if (widget.definition.extraFields.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Divider(color: AppColors.border),
              const SizedBox(height: 4),
              const Text(
                'Provider Settings',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              for (int i = 0;
                  i < widget.definition.extraFields.length;
                  i++) ...[
                _buildExtraField(widget.definition.extraFields[i]),
                if (i < widget.definition.extraFields.length - 1)
                  const SizedBox(height: 14),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSecretField(ProviderSecretDef def) {
    final statusNotifier = _secretStatus[def.secretName]!;
    return ValueListenableBuilder<bool>(
      valueListenable: statusNotifier,
      builder: (context, isConfigured, _) {
        return SecretFieldWidget(
          label: def.label,
          hint: def.hint,
          isConfigured: isConfigured,
          onSave: (value) async {
            final notifier =
                ref.read(whatsappConfigNotifierProvider.notifier);
            await notifier.setSecret(
              widget.definition.provider,
              def.secretName,
              value,
            );
            statusNotifier.value = true;
            if (mounted) setState(() {}); // refresh _canTest
          },
        );
      },
    );
  }

  Widget _buildExtraField(ExtraFieldDef def) {
    return TextFormField(
      controller: _extraCtrl[def.key],
      decoration: InputDecoration(
        labelText: def.label,
        hintText: def.hint,
      ),
      onChanged: (_) => _markDirty(),
      validator: def.required
          ? (v) =>
              (v?.trim().isEmpty ?? true) ? '${def.label} is required' : null
          : null,
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

  Widget _buildTestSection() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.science_rounded,
                size: 15,
                color: AppColors.textSecondary,
              ),
              SizedBox(width: 6),
              Text(
                'Send Test Message',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildTestPrerequisites(),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _testPhoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Test Phone Number',
                    hintText: 'Country code + number, e.g. 919876543210',
                  ),
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: FilledButton.icon(
                  onPressed: _canTest ? _sendTest : null,
                  icon: _testing
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Send Test'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    disabledBackgroundColor: AppColors.border,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_testMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: _testSuccess
                    ? AppColors.success.withValues(alpha: 0.08)
                    : AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _testSuccess
                      ? AppColors.success.withValues(alpha: 0.3)
                      : AppColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _testSuccess
                        ? Icons.check_circle_outline_rounded
                        : Icons.error_outline_rounded,
                    size: 15,
                    color: _testSuccess
                        ? AppColors.success
                        : AppColors.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _testMessage!,
                      style: TextStyle(
                        fontSize: 12,
                        color: _testSuccess
                            ? AppColors.success
                            : AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTestPrerequisites() {
    final checks = [
      (
        met: _isEnabled,
        label: 'Provider enabled',
        fix: 'flip the toggle and save',
      ),
      (
        met: _apiUrlCtrl.text.isNotEmpty,
        label: 'API Endpoint URL set',
        fix: 'enter the URL above and save',
      ),
      (
        met: _apiKeySet,
        label: 'API Key configured',
        fix: 'enter the API Key and click Update',
      ),
      (
        met: !_dirty,
        label: 'No unsaved changes',
        fix: 'click Save Changes',
      ),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: checks.map((c) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              c.met
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 13,
              color: c.met ? AppColors.success : AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              c.met ? c.label : '${c.label} — ${c.fix}',
              style: TextStyle(
                fontSize: 11,
                color: c.met ? AppColors.success : AppColors.textSecondary,
              ),
            ),
          ],
        );
      }).toList(),
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
