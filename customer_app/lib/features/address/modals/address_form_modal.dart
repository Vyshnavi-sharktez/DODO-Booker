import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_modal_dialog.dart';
import '../../../models/address_model.dart';
import '../services/address_providers.dart';

/// Add or edit an address. Pops with the saved [AddressModel] on success.
/// Pass [initialAddress] to enter edit mode.
class AddressFormModal extends ConsumerStatefulWidget {
  final AddressModel? initialAddress;

  const AddressFormModal({super.key, this.initialAddress});

  @override
  ConsumerState<AddressFormModal> createState() => _AddressFormModalState();
}

class _AddressFormModalState extends ConsumerState<AddressFormModal> {
  final _formKey = GlobalKey<FormState>();

  late String _label;
  final _line1Ctrl = TextEditingController();
  final _line2Ctrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _pincodeCtrl = TextEditingController();

  bool _isLoading = false;
  String? _error;

  static const _types = ['Home', 'Office', 'Other'];

  bool get _isEditing => widget.initialAddress != null;

  @override
  void initState() {
    super.initState();
    final a = widget.initialAddress;
    _label = a?.label ?? 'Home';
    _line1Ctrl.text = a?.line1 ?? '';
    _line2Ctrl.text = a?.line2 ?? '';
    _cityCtrl.text = a?.city ?? '';
    _stateCtrl.text = a?.state ?? '';
    _pincodeCtrl.text = a?.pincode ?? '';
  }

  @override
  void dispose() {
    _line1Ctrl.dispose();
    _line2Ctrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _pincodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _isLoading = true; _error = null; });

    try {
      final AddressModel saved;
      if (_isEditing) {
        saved = await ref.read(addressNotifierProvider.notifier).update(
          widget.initialAddress!.id,
          addressType: _label,
          addressLine1: _line1Ctrl.text.trim(),
          addressLine2: _line2Ctrl.text.trim().isEmpty ? null : _line2Ctrl.text.trim(),
          city: _cityCtrl.text.trim(),
          province: _stateCtrl.text.trim(),
          pincode: _pincodeCtrl.text.trim(),
        );
      } else {
        saved = await ref.read(addressNotifierProvider.notifier).create(
          addressType: _label,
          addressLine1: _line1Ctrl.text.trim(),
          addressLine2: _line2Ctrl.text.trim().isEmpty ? null : _line2Ctrl.text.trim(),
          city: _cityCtrl.text.trim(),
          province: _stateCtrl.text.trim(),
          pincode: _pincodeCtrl.text.trim(),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      setState(() { _isLoading = false; _error = message; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return AppModalDialog(
      title: _isEditing ? 'Edit Address' : 'Add Address',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),

            // ── Address type ─────────────────────────────────────────────────
            Text('Address Type', style: _labelStyle(tt)),
            const SizedBox(height: 8),
            Row(
              children: _types.map((type) {
                final selected = _label == type;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(type),
                    selected: selected,
                    onSelected: (_) => setState(() => _label = type),
                    selectedColor: AppColors.primary.withAlpha(25),
                    labelStyle: TextStyle(
                      color: selected ? AppColors.primary : AppColors.textSecondary,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    side: BorderSide(
                      color: selected ? AppColors.primary : AppColors.border,
                      width: selected ? 1.5 : 1,
                    ),
                    backgroundColor: AppColors.surface,
                    showCheckmark: false,
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // ── House / Flat No., Street & Area ──────────────────────────────
            Text('House / Flat No., Street & Area', style: _labelStyle(tt)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _line1Ctrl,
              decoration: _inputDecoration('e.g. 204, Sunrise Apartments, MG Road'),
              validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
            ),

            const SizedBox(height: 14),

            // ── Landmark ─────────────────────────────────────────────────────
            Text('Landmark (Optional)', style: _labelStyle(tt)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _line2Ctrl,
              decoration: _inputDecoration('e.g. Near City Mall'),
            ),

            const SizedBox(height: 14),

            // ── City & State row ─────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('City', style: _labelStyle(tt)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _cityCtrl,
                        decoration: _inputDecoration('e.g. Bengaluru'),
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('State', style: _labelStyle(tt)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _stateCtrl,
                        decoration: _inputDecoration('e.g. Karnataka'),
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // ── Pincode ──────────────────────────────────────────────────────
            Text('Pincode', style: _labelStyle(tt)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _pincodeCtrl,
              decoration: _inputDecoration('e.g. 560001'),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (v.trim().length != 6) return '6 digits required';
                return null;
              },
            ),

            // ── Error ────────────────────────────────────────────────────────
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.error.withAlpha(18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(fontSize: 13, color: AppColors.error),
                  textAlign: TextAlign.center,
                ),
              ),
            ],

            const SizedBox(height: 24),

            FilledButton(
              onPressed: _isLoading ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _isLoading
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : Text(
                      _isEditing ? 'Update Address' : 'Save Address',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle? _labelStyle(TextTheme tt) => tt.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        isDense: true,
      );
}
