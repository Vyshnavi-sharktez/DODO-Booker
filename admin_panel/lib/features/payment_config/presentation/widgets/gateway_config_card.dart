import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../application/providers/payment_config_providers.dart';
import '../../domain/models/payment_gateway_config.dart';
import 'secret_field_widget.dart';

// ── Gateway definition ────────────────────────────────────────────────────────
// Describes the UI shape for a payment gateway. Adding a new gateway (e.g.
// Stripe) requires only a new GatewayDefinition — no changes to repository
// or database schema.

class GatewaySecretDef {
  final String secretName;
  final String label;
  final String? hint;

  const GatewaySecretDef({
    required this.secretName,
    required this.label,
    this.hint,
  });
}

class GatewayDefinition {
  final String gateway;
  final String title;
  final IconData icon;
  final Color color;
  final String description;
  final List<GatewaySecretDef> secrets;

  const GatewayDefinition({
    required this.gateway,
    required this.title,
    required this.icon,
    required this.color,
    required this.description,
    required this.secrets,
  });
}

// ── Card ──────────────────────────────────────────────────────────────────────

class GatewayConfigCard extends ConsumerStatefulWidget {
  const GatewayConfigCard({super.key, required this.definition});
  final GatewayDefinition definition;

  @override
  ConsumerState<GatewayConfigCard> createState() => _GatewayConfigCardState();
}

class _GatewayConfigCardState extends ConsumerState<GatewayConfigCard> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameCtrl = TextEditingController();
  final _publicKeyCtrl = TextEditingController();

  bool _isEnabled = false;
  String _mode = 'test';
  bool _dirty = false;
  bool _saving = false;

  // Secret status: secretName → isConfigured
  late final Map<String, ValueNotifier<bool>> _secretStatus;

  @override
  void initState() {
    super.initState();
    _secretStatus = {
      for (final s in widget.definition.secrets)
        s.secretName: ValueNotifier(false),
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _publicKeyCtrl.dispose();
    for (final n in _secretStatus.values) {
      n.dispose();
    }
    super.dispose();
  }

  void _init() {
    final notifier = ref.read(paymentGatewayConfigNotifierProvider.notifier);
    final cfg = notifier.configFor(widget.definition.gateway);
    _applyConfig(cfg);
    _loadSecretStatuses();
  }

  void _applyConfig(PaymentGatewayConfig cfg) {
    if (_dirty) return;
    _displayNameCtrl.text = cfg.displayName;
    _publicKeyCtrl.text = cfg.publicKey;
    setState(() {
      _isEnabled = cfg.isEnabled;
      _mode = cfg.mode;
    });
  }

  Future<void> _loadSecretStatuses() async {
    final notifier = ref.read(paymentGatewayConfigNotifierProvider.notifier);
    for (final s in widget.definition.secrets) {
      try {
        final isSet = await notifier.secretIsSet(
          widget.definition.gateway,
          s.secretName,
        );
        if (mounted) _secretStatus[s.secretName]?.value = isSet;
      } catch (e) {
        debugPrint('Secret status check failed for ${s.secretName}: $e');
        // Leaves this secret as "Not set"; does not block subsequent secrets.
      }
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final notifier = ref.read(paymentGatewayConfigNotifierProvider.notifier);
      final existing = notifier.configFor(widget.definition.gateway);
      await notifier.saveConfig(
        existing.copyWith(
          isEnabled: _isEnabled,
          mode: _mode,
          displayName: _displayNameCtrl.text.trim(),
          publicKey: _publicKeyCtrl.text.trim(),
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

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<PaymentGatewayConfig>>>(
      paymentGatewayConfigNotifierProvider,
      (_, next) => next.whenOrNull(
        data: (configs) {
          final cfg = configs.firstWhere(
            (c) => c.gateway == widget.definition.gateway,
            orElse: () => PaymentGatewayConfig.empty(widget.definition.gateway),
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
            // Enable/disable
            _buildToggle(
              label: 'Enable Gateway',
              hint: 'Allow customers to pay using ${widget.definition.title}',
              value: _isEnabled,
              onChanged: (v) => setState(() {
                _isEnabled = v;
                _markDirty();
              }),
            ),
            const SizedBox(height: 14),

            // Test / Live mode
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _mode,
              decoration: const InputDecoration(labelText: 'Mode'),
              items: const [
                DropdownMenuItem(value: 'test', child: Text('Test')),
                DropdownMenuItem(value: 'live', child: Text('Live')),
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _mode = v;
                    _markDirty();
                  });
                }
              },
            ),
            const SizedBox(height: 14),

            // Payment title shown to customers
            TextFormField(
              controller: _displayNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Payment Title',
                hintText: 'e.g. Pay with Razorpay',
              ),
              onChanged: (_) => _markDirty(),
              validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? 'Payment title is required' : null,
            ),
            const SizedBox(height: 14),

            // Public API key
            TextFormField(
              controller: _publicKeyCtrl,
              decoration: const InputDecoration(
                labelText: 'API Key',
                hintText: 'rzp_test_... or rzp_live_...',
              ),
              onChanged: (_) => _markDirty(),
              validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? 'API Key is required' : null,
            ),

            // Secret fields (write-only, independent save per field)
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
              for (int i = 0; i < widget.definition.secrets.length; i++) ...[
                _buildSecretField(widget.definition.secrets[i]),
                if (i < widget.definition.secrets.length - 1)
                  const SizedBox(height: 14),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSecretField(GatewaySecretDef def) {
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
                ref.read(paymentGatewayConfigNotifierProvider.notifier);
            await notifier.setSecret(
              widget.definition.gateway,
              def.secretName,
              value,
            );
            statusNotifier.value = true;
          },
        );
      },
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
