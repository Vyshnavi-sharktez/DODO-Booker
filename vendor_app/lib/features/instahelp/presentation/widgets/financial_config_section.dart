import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../domain/models/instahelp_financial_config.dart';
import '../providers/instahelp_vendor_providers.dart';

class VendorFinancialConfigSection extends ConsumerWidget {
  final String modeId;
  const VendorFinancialConfigSection({super.key, required this.modeId});

  void _openEdit(BuildContext context, WidgetRef ref, InstaHelpFinancialConfig? existing) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FinancialConfigDialog(
        existing: existing,
        onSave: ({
          required gstPercent,
          required surgeFeeEnabled,
          required surgeFeeType,
          required surgeFeeValue,
          required serviceChargeEnabled,
          required serviceChargeType,
          required serviceChargeValue,
        }) =>
            ref.read(vendorFinancialConfigProvider(modeId).notifier).save(
              gstPercent: gstPercent,
              surgeFeeEnabled: surgeFeeEnabled,
              surgeFeeType: surgeFeeType,
              surgeFeeValue: surgeFeeValue,
              serviceChargeEnabled: serviceChargeEnabled,
              serviceChargeType: serviceChargeType,
              serviceChargeValue: serviceChargeValue,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(vendorFinancialConfigProvider(modeId));
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
            child: Row(children: [
              const Icon(Icons.account_balance_wallet_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('Financial Config',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const Spacer(),
              configAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                data: (config) => FilledButton.icon(
                  onPressed: () => _openEdit(context, ref, config),
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: Text(config == null ? 'Configure' : 'Edit'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size(0, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ]),
          ),
          const Divider(height: 1),
          configAsync.when(
            loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error: $e', style: const TextStyle(color: AppColors.error)),
            ),
            data: (config) {
              if (config == null) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text('No financial config. Click Configure.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Wrap(spacing: 16, runSpacing: 10, children: [
                  _Chip(
                    icon: Icons.percent_rounded,
                    label: 'GST',
                    value: config.gstPercent > 0 ? '${config.gstPercent.toStringAsFixed(1)}%' : 'None',
                    valueColor: config.gstPercent > 0 ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                  _Chip(
                    icon: Icons.trending_up_rounded,
                    label: 'Surge Fee',
                    value: config.surgeFeeLabel,
                    valueColor: config.surgeFeeEnabled ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                  _Chip(
                    icon: Icons.receipt_long_rounded,
                    label: 'Service Charge',
                    value: config.serviceChargeLabel,
                    valueColor: config.serviceChargeEnabled ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                ]),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _Chip({required this.icon, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: AppColors.primary),
        const SizedBox(width: 6),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? AppColors.textPrimary)),
        ]),
      ]),
    );
  }
}

// ── Dialog ────────────────────────────────────────────────────────────────────

typedef _FinancialConfigSaveCallback = Future<void> Function({
  required double gstPercent,
  required bool surgeFeeEnabled,
  required String surgeFeeType,
  required double surgeFeeValue,
  required bool serviceChargeEnabled,
  required String serviceChargeType,
  required double serviceChargeValue,
});

class _FinancialConfigDialog extends StatefulWidget {
  final InstaHelpFinancialConfig? existing;
  final _FinancialConfigSaveCallback onSave;
  const _FinancialConfigDialog({this.existing, required this.onSave});

  @override
  State<_FinancialConfigDialog> createState() => _FinancialConfigDialogState();
}

String _fmt(double v) => v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

class _FinancialConfigDialogState extends State<_FinancialConfigDialog> {
  final _gstCtrl = TextEditingController();
  final _surgeValueCtrl = TextEditingController();
  final _scValueCtrl = TextEditingController();

  late bool _surgeFeeEnabled;
  late String _surgeFeeType;
  late bool _scEnabled;
  late String _scType;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _gstCtrl.text = _fmt(e?.gstPercent ?? 0);
    _surgeFeeEnabled = e?.surgeFeeEnabled ?? false;
    _surgeFeeType = e?.surgeFeeType ?? 'percentage';
    _surgeValueCtrl.text = _fmt(e?.surgeFeeValue ?? 0);
    _scEnabled = e?.serviceChargeEnabled ?? false;
    _scType = e?.serviceChargeType ?? 'fixed';
    _scValueCtrl.text = _fmt(e?.serviceChargeValue ?? 0);
  }

  @override
  void dispose() {
    _gstCtrl.dispose();
    _surgeValueCtrl.dispose();
    _scValueCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final gst = double.tryParse(_gstCtrl.text.trim()) ?? 0;
    final surgeVal = double.tryParse(_surgeValueCtrl.text.trim()) ?? 0;
    final scVal = double.tryParse(_scValueCtrl.text.trim()) ?? 0;

    if (gst < 0 || gst > 100) {
      setState(() => _error = 'GST must be between 0 and 100.');
      return;
    }
    if (_surgeFeeEnabled && surgeVal <= 0) {
      setState(() => _error = 'Enter a surge fee value > 0.');
      return;
    }
    if (_scEnabled && scVal <= 0) {
      setState(() => _error = 'Enter a service charge value > 0.');
      return;
    }

    setState(() { _saving = true; _error = null; });
    try {
      await widget.onSave(
        gstPercent: gst,
        surgeFeeEnabled: _surgeFeeEnabled,
        surgeFeeType: _surgeFeeType,
        surgeFeeValue: surgeVal,
        serviceChargeEnabled: _scEnabled,
        serviceChargeType: _scType,
        serviceChargeValue: scVal,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Financial Config',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // GST
              TextField(
                controller: _gstCtrl,
                decoration: const InputDecoration(
                  labelText: 'GST %',
                  hintText: '0',
                  border: OutlineInputBorder(),
                  isDense: true,
                  suffixText: '%',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
              ),
              const SizedBox(height: 20),

              // Surge fee
              const Text('Surge Fee',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable Surge Fee', style: TextStyle(fontSize: 14)),
                value: _surgeFeeEnabled,
                onChanged: (v) => setState(() => _surgeFeeEnabled = v),
                activeThumbColor: AppColors.success,
              ),
              if (_surgeFeeEnabled) ...[
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _surgeFeeType,
                      decoration: const InputDecoration(
                        labelText: 'Type',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'percentage', child: Text('Percentage')),
                        DropdownMenuItem(value: 'fixed', child: Text('Fixed (₹)')),
                      ],
                      onChanged: (v) => setState(() => _surgeFeeType = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _surgeValueCtrl,
                      decoration: InputDecoration(
                        labelText: _surgeFeeType == 'percentage' ? 'Value (%)' : 'Value (₹)',
                        hintText: '0',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: 20),

              // Service charge
              const Text('Service Charge',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable Service Charge', style: TextStyle(fontSize: 14)),
                value: _scEnabled,
                onChanged: (v) => setState(() => _scEnabled = v),
                activeThumbColor: AppColors.success,
              ),
              if (_scEnabled) ...[
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _scType,
                      decoration: const InputDecoration(
                        labelText: 'Type',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'fixed', child: Text('Fixed (₹)')),
                        DropdownMenuItem(value: 'percentage', child: Text('Percentage')),
                      ],
                      onChanged: (v) => setState(() => _scType = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _scValueCtrl,
                      decoration: InputDecoration(
                        labelText: _scType == 'percentage' ? 'Value (%)' : 'Value (₹)',
                        hintText: '0',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                    ),
                  ),
                ]),
              ],

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          ),
          child: _saving
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
