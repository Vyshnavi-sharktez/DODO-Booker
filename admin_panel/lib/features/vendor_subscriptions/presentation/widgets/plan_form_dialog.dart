import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/subscription_plan.dart';

class PlanFormDialog extends StatefulWidget {
  const PlanFormDialog({super.key, this.existing, required this.onSave});

  final SubscriptionPlan? existing;
  final Future<void> Function({
    required String name,
    String? description,
    required String billingCycle,
    required int durationDays,
    double? joiningFee,
    double? subscriptionFee,
    required Map<String, dynamic> permissions,
    required bool isActive,
    required int sortOrder,
  }) onSave;

  @override
  State<PlanFormDialog> createState() => _PlanFormDialogState();
}

class _PlanFormDialogState extends State<PlanFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _durationCtrl;
  late final TextEditingController _joiningFeeCtrl;
  late final TextEditingController _subFeeCtrl;
  late final TextEditingController _sortCtrl;
  late final TextEditingController _commissionPctCtrl;
  late String _billingCycle;
  late bool _isActive;
  late bool _allowCod;
  late bool _allowBookingAssignment;
  late bool _priorityListing;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _descCtrl = TextEditingController(text: p?.description ?? '');
    _durationCtrl = TextEditingController(text: '${p?.durationDays ?? 30}');
    _joiningFeeCtrl = TextEditingController(
        text: p?.joiningFee != null ? p!.joiningFee!.toStringAsFixed(2) : '');
    _subFeeCtrl = TextEditingController(
        text: p?.subscriptionFee != null ? p!.subscriptionFee!.toStringAsFixed(2) : '');
    _sortCtrl = TextEditingController(text: '${p?.sortOrder ?? 0}');
    _commissionPctCtrl = TextEditingController(
        text: (p != null && p.reducedCommissionPct != 0)
            ? p.reducedCommissionPct.toStringAsFixed(0)
            : '');
    _billingCycle = p?.billingCycle ?? 'monthly';
    _isActive = p?.isActive ?? true;
    _allowCod = p?.allowCod ?? false;
    _allowBookingAssignment = p?.allowBookingAssignment ?? false;
    _priorityListing = p?.priorityListing ?? false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _durationCtrl.dispose();
    _joiningFeeCtrl.dispose();
    _subFeeCtrl.dispose();
    _sortCtrl.dispose();
    _commissionPctCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final perms = <String, dynamic>{
        'allow_cod': _allowCod,
        'allow_booking_assignment': _allowBookingAssignment,
        'priority_listing': _priorityListing,
        if (_commissionPctCtrl.text.trim().isNotEmpty)
          'reduced_commission_pct': double.parse(_commissionPctCtrl.text.trim()),
      };
      await widget.onSave(
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        billingCycle: _billingCycle,
        durationDays: int.parse(_durationCtrl.text.trim()),
        joiningFee: _joiningFeeCtrl.text.trim().isEmpty
            ? null
            : double.parse(_joiningFeeCtrl.text.trim()),
        subscriptionFee: _subFeeCtrl.text.trim().isEmpty
            ? null
            : double.parse(_subFeeCtrl.text.trim()),
        permissions: perms,
        isActive: _isActive,
        sortOrder: int.tryParse(_sortCtrl.text.trim()) ?? 0,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.workspace_premium_rounded,
                            color: AppColors.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isEdit ? 'Edit Plan' : 'New Subscription Plan',
                          style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Name
                  _field('Plan Name', _nameCtrl,
                      hint: 'e.g. Basic, Pro, Premium',
                      validator: (v) => v?.trim().isEmpty == true ? 'Required' : null),
                  const SizedBox(height: 14),

                  // Description
                  _field('Description', _descCtrl,
                      hint: 'Brief description of this plan', maxLines: 2),
                  const SizedBox(height: 14),

                  // Billing cycle + duration row
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Billing Cycle'),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              value: _billingCycle,
                              decoration: _inputDecoration(),
                              items: kBillingCycles
                                  .map((c) => DropdownMenuItem(
                                        value: c,
                                        child: Text(
                                          c[0].toUpperCase() + c.substring(1),
                                        ),
                                      ))
                                  .toList(),
                              onChanged: (v) => setState(() => _billingCycle = v!),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _field('Duration (days)', _durationCtrl,
                            hint: '30',
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            validator: (v) {
                              if (v?.trim().isEmpty == true) return 'Required';
                              if (int.tryParse(v!) == null || int.parse(v) < 1) {
                                return 'Must be ≥ 1';
                              }
                              return null;
                            }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Fees row
                  Row(
                    children: [
                      Expanded(
                        child: _field('Joining Fee', _joiningFeeCtrl,
                            hint: '0.00 (optional)',
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: (v) {
                              if (v?.trim().isEmpty == true) return null;
                              if (double.tryParse(v!) == null) return 'Invalid number';
                              return null;
                            }),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _field('Subscription Fee', _subFeeCtrl,
                            hint: '0.00 (optional)',
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: (v) {
                              if (v?.trim().isEmpty == true) return null;
                              if (double.tryParse(v!) == null) return 'Invalid number';
                              return null;
                            }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Permissions
                  const Text('Permissions',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 10),
                  _permissionTile(
                    'Allow COD',
                    'Vendor can accept Cash on Delivery payments',
                    _allowCod,
                    (v) => setState(() => _allowCod = v),
                  ),
                  _permissionTile(
                    'Allow Booking Assignment',
                    'Admin can manually assign bookings to this vendor',
                    _allowBookingAssignment,
                    (v) => setState(() => _allowBookingAssignment = v),
                  ),
                  _permissionTile(
                    'Priority Listing',
                    'Vendor appears higher in customer search results',
                    _priorityListing,
                    (v) => setState(() => _priorityListing = v),
                  ),
                  const SizedBox(height: 10),
                  _field('Reduced Commission %', _commissionPctCtrl,
                      hint: 'Leave empty for default platform rate',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v?.trim().isEmpty == true) return null;
                        final d = double.tryParse(v!);
                        if (d == null || d < 0 || d > 100) {
                          return 'Must be 0–100';
                        }
                        return null;
                      }),
                  const SizedBox(height: 14),

                  // Sort + Active row
                  Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: _field('Sort Order', _sortCtrl,
                            hint: '0',
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
                      ),
                      const SizedBox(width: 20),
                      Row(
                        children: [
                          Switch(
                            value: _isActive,
                            onChanged: (v) => setState(() => _isActive = v),
                            activeColor: AppColors.success,
                          ),
                          const SizedBox(width: 6),
                          Text(_isActive ? 'Active' : 'Inactive',
                              style: TextStyle(
                                  color: _isActive
                                      ? AppColors.success
                                      : AppColors.textSecondary,
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // Actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: _saving ? null : () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: _saving ? null : _submit,
                        style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                        child: _saving
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2,
                                    color: Colors.white))
                            : Text(isEdit ? 'Update' : 'Create'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary));

  InputDecoration _inputDecoration({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        filled: true,
        fillColor: AppColors.background,
      );

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          decoration: _inputDecoration(hint: hint),
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
        ),
      ],
    );
  }

  Widget _permissionTile(
      String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: value
            ? AppColors.primary.withValues(alpha: 0.04)
            : AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: value
              ? AppColors.primary.withValues(alpha: 0.3)
              : AppColors.border,
        ),
      ),
      child: SwitchListTile(
        dense: true,
        title: Text(title,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        subtitle: Text(subtitle,
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.primary,
      ),
    );
  }
}
