import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/widgets/image_upload_field.dart';
import '../../application/providers/payment_config_providers.dart';
import '../../domain/models/payment_gateway_config.dart';

class UpiDodoConfigCard extends ConsumerStatefulWidget {
  const UpiDodoConfigCard({super.key});

  @override
  ConsumerState<UpiDodoConfigCard> createState() => _UpiDodoConfigCardState();
}

class _UpiDodoConfigCardState extends ConsumerState<UpiDodoConfigCard> {
  final _formKey = GlobalKey<FormState>();
  final _upiIdCtrl = TextEditingController();

  bool _isEnabled = false;
  String? _qrImageUrl;
  bool _dirty = false;
  bool _saving = false;

  static const _gateway = 'upi_dodo';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _upiIdCtrl.dispose();
    super.dispose();
  }

  void _init() {
    final notifier = ref.read(paymentGatewayConfigNotifierProvider.notifier);
    final cfg = notifier.configFor(_gateway);
    _applyConfig(cfg);
  }

  void _applyConfig(PaymentGatewayConfig cfg) {
    if (_dirty) return;
    _upiIdCtrl.text = cfg.extraConfig['upi_id'] as String? ?? '';
    setState(() {
      _isEnabled = cfg.isEnabled;
      _qrImageUrl = cfg.extraConfig['qr_image_url'] as String?;
      if (_qrImageUrl?.isEmpty == true) _qrImageUrl = null;
    });
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final notifier = ref.read(paymentGatewayConfigNotifierProvider.notifier);
      final existing = notifier.configFor(_gateway);
      await notifier.saveConfig(
        existing.copyWith(
          isEnabled: _isEnabled,
          extraConfig: {
            'upi_id': _upiIdCtrl.text.trim(),
            'qr_image_url': _qrImageUrl ?? '',
          },
        ),
      );
      if (mounted) {
        setState(() {
          _dirty = false;
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('DODO UPI configuration saved'),
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

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<PaymentGatewayConfig>>>(
      paymentGatewayConfigNotifierProvider,
      (_, next) => next.whenOrNull(
        data: (configs) {
          final cfg = configs.firstWhere(
            (c) => c.gateway == _gateway,
            orElse: () => PaymentGatewayConfig.empty(_gateway),
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
              color: const Color(0xFF0F9D58).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.qr_code_rounded, color: Color(0xFF0F9D58), size: 20),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DODO Booker UPI Payment',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'Customer pays directly to DODO\'s UPI ID — DODO settles with vendor',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (_dirty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
              label: 'Enable DODO UPI Payment',
              hint: 'Show UPI payment option to customers at checkout',
              value: _isEnabled,
              onChanged: (v) => setState(() {
                _isEnabled = v;
                _markDirty();
              }),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _upiIdCtrl,
              decoration: const InputDecoration(
                labelText: 'UPI ID',
                hintText: 'e.g. dodobooker@okaxis',
              ),
              onChanged: (_) => _markDirty(),
              validator: (v) {
                if (!_isEnabled) return null;
                return (v?.trim().isEmpty ?? true) ? 'UPI ID is required when enabled' : null;
              },
            ),
            const SizedBox(height: 16),
            ImageUploadField(
              label: 'QR Code Image',
              value: _qrImageUrl,
              bucket: 'cms-media',
              pathPrefix: 'upi-qr/',
              onChanged: (url) {
                setState(() => _qrImageUrl = url);
                _markDirty();
              },
            ),
          ],
        ),
      ),
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
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save_rounded, size: 16),
            label: const Text('Save Changes'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor: AppColors.border,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
                Text(label,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(hint,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
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
