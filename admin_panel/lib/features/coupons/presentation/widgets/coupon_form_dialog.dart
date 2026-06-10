import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/coupon.dart';

const _discountTypeOptions = [
  ('percentage', 'Percentage (%)'),
  ('flat', 'Flat Amount (₹)'),
];

final _dateFmt = DateFormat('dd MMM yyyy');

class CouponFormDialog extends StatefulWidget {
  final Coupon? existing;
  final Future<void> Function({
    required String code,
    String? description,
    required String discountType,
    required double discountValue,
    double? minOrderAmount,
    double? minDiscountAmount,
    int? usageLimit,
    DateTime? validFrom,
    DateTime? validTo,
    required bool isActive,
  }) onSave;

  const CouponFormDialog({super.key, this.existing, required this.onSave});

  @override
  State<CouponFormDialog> createState() => _CouponFormDialogState();
}

class _CouponFormDialogState extends State<CouponFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _description;
  late final TextEditingController _discountValue;
  late final TextEditingController _minOrderAmount;
  late final TextEditingController _minDiscountAmount;
  late final TextEditingController _usageLimit;
  late String _discountType;
  late DateTime? _validFrom;
  late DateTime? _validTo;
  late bool _isActive;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _code = TextEditingController(text: e?.code ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _discountValue = TextEditingController(
      text: e != null ? e.discountValue.toStringAsFixed(2) : '',
    );
    _minOrderAmount = TextEditingController(
      text: e?.minOrderAmount != null
          ? e!.minOrderAmount!.toStringAsFixed(2)
          : '',
    );
    _minDiscountAmount = TextEditingController(
      text: e?.minDiscountAmount != null
          ? e!.minDiscountAmount!.toStringAsFixed(2)
          : '',
    );
    _usageLimit = TextEditingController(
      text: e?.usageLimit != null ? e!.usageLimit.toString() : '',
    );
    _discountType = e?.discountType ?? 'percentage';
    _validFrom = e?.validFrom ?? DateTime.now();
    _validTo = e?.validTo;
    _isActive = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _code.dispose();
    _description.dispose();
    _discountValue.dispose();
    _minOrderAmount.dispose();
    _minDiscountAmount.dispose();
    _usageLimit.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom
        ? (_validFrom ?? DateTime.now())
        : (_validTo ?? (_validFrom ?? DateTime.now()).add(const Duration(days: 30)));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _validFrom = picked;
          if (_validTo != null && _validTo!.isBefore(picked)) {
            _validTo = null;
          }
        } else {
          _validTo = picked;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final limitText = _usageLimit.text.trim();
      await widget.onSave(
        code: _code.text.trim(),
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        discountType: _discountType,
        discountValue: double.parse(_discountValue.text.trim()),
        minOrderAmount: _minOrderAmount.text.trim().isEmpty
            ? null
            : double.tryParse(_minOrderAmount.text.trim()),
        minDiscountAmount: _minDiscountAmount.text.trim().isEmpty
            ? null
            : double.tryParse(_minDiscountAmount.text.trim()),
        usageLimit: limitText.isEmpty ? null : int.tryParse(limitText),
        validFrom: _validFrom,
        validTo: _validTo,
        isActive: _isActive,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(
                    isEdit
                        ? Icons.edit_rounded
                        : Icons.add_circle_outline_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isEdit ? 'Edit Coupon' : 'New Coupon',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // ── Form ────────────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Code + Discount Type
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _code,
                              decoration: const InputDecoration(
                                labelText: 'Coupon Code *',
                                hintText: 'Coupon Code',
                                prefixIcon:
                                    Icon(Icons.local_offer_rounded),
                              ),
                              textCapitalization:
                                  TextCapitalization.characters,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[A-Za-z0-9_\-]')),
                                TextInputFormatter.withFunction(
                                  (old, newVal) => newVal.copyWith(
                                    text: newVal.text.toUpperCase(),
                                  ),
                                ),
                              ],
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Required'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              // ignore: deprecated_member_use
                              value: _discountType,
                              decoration: const InputDecoration(
                                labelText: 'Discount Type *',
                                prefixIcon: Icon(Icons.percent_rounded),
                              ),
                              items: _discountTypeOptions
                                  .map((t) => DropdownMenuItem(
                                        value: t.$1,
                                        child: Text(t.$2),
                                      ))
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _discountType = v);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Description
                      TextFormField(
                        controller: _description,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          hintText: 'Description',
                          prefixIcon: Icon(Icons.notes_rounded),
                        ),
                        textCapitalization: TextCapitalization.sentences,
                      ),
                      const SizedBox(height: 16),

                      // Discount Value + Min Order Amount
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _discountValue,
                              decoration: InputDecoration(
                                labelText: 'Discount Value *',
                                hintText: 'Discount Value',
                                prefixIcon: Icon(
                                  _discountType == 'percentage'
                                      ? Icons.percent_rounded
                                      : Icons.currency_rupee_rounded,
                                ),
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d{0,2}')),
                              ],
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Required';
                                }
                                final n = double.tryParse(v.trim());
                                if (n == null || n <= 0) {
                                  return 'Must be > 0';
                                }
                                if (_discountType == 'percentage' && n > 100) {
                                  return 'Max 100%';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _minOrderAmount,
                              decoration: const InputDecoration(
                                labelText: 'Min Order Amount',
                                hintText: 'Min Order Amount',
                                prefixIcon:
                                    Icon(Icons.shopping_cart_rounded),
                                helperText: 'Optional',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d{0,2}')),
                              ],
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return null;
                                }
                                if (double.tryParse(v.trim()) == null) {
                                  return 'Invalid amount';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Min Discount Amount + Usage Limit
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _minDiscountAmount,
                              decoration: const InputDecoration(
                                labelText: 'Min Discount Amount',
                                hintText: 'Min Discount Amount',
                                prefixIcon:
                                    Icon(Icons.price_check_rounded),
                                helperText: 'Optional',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d{0,2}')),
                              ],
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return null;
                                }
                                if (double.tryParse(v.trim()) == null) {
                                  return 'Invalid amount';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _usageLimit,
                              decoration: const InputDecoration(
                                labelText: 'Usage Limit',
                                hintText: 'Usage Limit',
                                prefixIcon: Icon(Icons.people_rounded),
                                helperText: 'Optional, leave blank for unlimited',
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return null;
                                }
                                final n = int.tryParse(v.trim());
                                if (n == null || n < 0) {
                                  return 'Must be ≥ 0';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Valid From + Valid To
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _DatePickerField(
                              label: 'Valid From',
                              value: _validFrom,
                              onTap: () => _pickDate(isFrom: true),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _DatePickerField(
                              label: 'Valid To',
                              value: _validTo,
                              onTap: () => _pickDate(isFrom: false),
                              validator: (_) {
                                if (_validTo == null) return null;
                                if (_validFrom != null &&
                                    !_validTo!.isAfter(_validFrom!)) {
                                  return 'Must be after Valid From';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Active toggle
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Active',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                        subtitle: const Text(
                          'Make this coupon available for use',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                        dense: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Footer ──────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 12),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(isEdit ? 'Save Changes' : 'Create Coupon'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Date picker field ──────────────────────────────────────────────────────────

class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final String? Function(DateTime?)? validator;

  const _DatePickerField({
    required this.label,
    required this.value,
    required this.onTap,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return FormField<DateTime>(
      initialValue: value,
      validator: (_) => validator?.call(value),
      builder: (state) {
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: const Icon(Icons.calendar_today_rounded),
              errorText: state.errorText,
            ),
            child: Text(
              value != null ? _dateFmt.format(value!) : 'Select date',
              style: TextStyle(
                fontSize: 14,
                color: value != null
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ),
        );
      },
    );
  }
}
