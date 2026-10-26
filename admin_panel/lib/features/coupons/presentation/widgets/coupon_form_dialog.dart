import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../catalog_v2/application/providers/catalog_node_providers.dart';
import '../../../catalog_v2/domain/models/catalog_node.dart';
import '../../../customers/application/providers/customers_providers.dart';
import '../../../customers/domain/models/customer.dart';
import '../../../customers/application/providers/customer_profile_providers.dart';
import '../../../customers/domain/models/customer_address.dart';
import '../../../customers/domain/models/customer_profile.dart';
import '../../domain/models/coupon.dart';

const _discountTypeOptions = [
  ('percentage', 'Percentage (%)'),
  ('flat', 'Flat Amount (₹)'),
];

final _dateFmt = DateFormat('dd MMM yyyy');

class CouponFormDialog extends ConsumerStatefulWidget {
  final Coupon? existing;
  final Future<void> Function({
    required String code,
    String? description,
    required String discountType,
    required double discountValue,
    double? minOrderAmount,
    double? maxDiscountAmount,
    int? usageLimit,
    DateTime? validFrom,
    DateTime? validTo,
    required bool isActive,
    required String applicabilityType,
    required List<String> applicableNodeIds,
    required String customerEligibility,
    required List<String> selectedCustomerIds,
    int? maxOrderWiseLimit,
  }) onSave;

  const CouponFormDialog({super.key, this.existing, required this.onSave});

  @override
  ConsumerState<CouponFormDialog> createState() => _CouponFormDialogState();
}

class _CouponFormDialogState extends ConsumerState<CouponFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _description;
  late final TextEditingController _discountValue;
  late final TextEditingController _minOrderAmount;
  late final TextEditingController _maxDiscountAmount;
  late final TextEditingController _usageLimit;
  late final TextEditingController _maxOrderWiseLimit;
  late String _discountType;
  late DateTime? _validFrom;
  late DateTime? _validTo;
  late bool _isActive;
  late String _applicabilityType;
  late List<String> _applicableNodeIds;
  late String _customerEligibility;
  late List<String> _selectedCustomerIds;
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
    _maxDiscountAmount = TextEditingController(
      text: e?.maxDiscountAmount != null
          ? e!.maxDiscountAmount!.toStringAsFixed(2)
          : '',
    );
    _usageLimit = TextEditingController(
      text: e?.usageLimit != null ? e!.usageLimit.toString() : '',
    );
    _maxOrderWiseLimit = TextEditingController(
      text: e?.maxOrderWiseLimit != null ? e!.maxOrderWiseLimit.toString() : '',
    );
    _discountType = e?.discountType ?? 'percentage';
    _validFrom = e?.validFrom ?? DateTime.now();
    _validTo = e?.validTo;
    _isActive = e?.isActive ?? true;
    _applicabilityType = e?.applicabilityType ?? 'all';
    _applicableNodeIds = List<String>.from(e?.applicableNodeIds ?? []);
    _customerEligibility = e?.customerEligibility ?? 'all';
    _selectedCustomerIds = List<String>.from(e?.selectedCustomerIds ?? []);
  }

  @override
  void dispose() {
    _code.dispose();
    _description.dispose();
    _discountValue.dispose();
    _minOrderAmount.dispose();
    _maxDiscountAmount.dispose();
    _usageLimit.dispose();
    _maxOrderWiseLimit.dispose();
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
      final mowText = _maxOrderWiseLimit.text.trim();
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
        maxDiscountAmount: _maxDiscountAmount.text.trim().isEmpty
            ? null
            : double.tryParse(_maxDiscountAmount.text.trim()),
        usageLimit: limitText.isEmpty ? null : int.tryParse(limitText),
        validFrom: _validFrom,
        validTo: _validTo,
        isActive: _isActive,
        applicabilityType: _applicabilityType,
        applicableNodeIds: _applicabilityType == 'all' ? [] : _applicableNodeIds,
        customerEligibility: _customerEligibility,
        selectedCustomerIds:
            _customerEligibility == 'all' ? [] : _selectedCustomerIds,
        maxOrderWiseLimit: (_customerEligibility == 'all' && mowText.isNotEmpty)
            ? int.tryParse(mowText)
            : null,
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

  Future<void> _openNodePicker(List<CatalogNode> nodes) async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => _NodePickerDialog(
        nodes: nodes,
        selectedIds: _applicableNodeIds,
      ),
    );
    if (result != null) setState(() => _applicableNodeIds = result);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final allNodes = ref.watch(catalogNodeNotifierProvider).valueOrNull ?? [];

    // Categories = nodes that have children (non-leaf); services = bookable leaves
    final categoryNodes = allNodes.where((n) => n.childrenCount > 0).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final serviceNodes = allNodes.where((n) => n.isBookable).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final pickerNodes = _applicabilityType == 'categories'
        ? categoryNodes
        : _applicabilityType == 'services'
            ? serviceNodes
            : <CatalogNode>[];

    // Names of currently selected nodes for display
    final selectedNames = allNodes
        .where((n) => _applicableNodeIds.contains(n.id))
        .map((n) => n.name)
        .toList()
      ..sort();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
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
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
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
                                prefixIcon: Icon(Icons.local_offer_rounded),
                              ),
                              textCapitalization: TextCapitalization.characters,
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
                              keyboardType: const TextInputType.numberWithOptions(
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
                                if (n == null || n <= 0) return 'Must be > 0';
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
                                prefixIcon: Icon(Icons.shopping_cart_rounded),
                                helperText: 'Optional',
                              ),
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d{0,2}')),
                              ],
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return null;
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

                      // Max Discount Amount + Usage Limit
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _maxDiscountAmount,
                              decoration: const InputDecoration(
                                labelText: 'Max Discount Amount',
                                hintText: 'Max Discount Amount',
                                prefixIcon: Icon(Icons.currency_rupee_rounded),
                                helperText: 'Optional',
                              ),
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d{0,2}')),
                              ],
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return null;
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
                                if (v == null || v.trim().isEmpty) return null;
                                final n = int.tryParse(v.trim());
                                if (n == null || n < 0) return 'Must be ≥ 0';
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

                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 12),

                      // ── Applicability section ──────────────────────────────
                      Row(
                        children: [
                          const Icon(Icons.filter_alt_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Applicability',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Define which services or categories this coupon applies to.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),

                      RadioGroup<String>(
                        groupValue: _applicabilityType,
                        onChanged: (v) {
                          if (v != null) {
                            setState(() {
                              _applicabilityType = v;
                              _applicableNodeIds = [];
                            });
                          }
                        },
                        child: Column(
                          children: [
                            _ApplicabilityRadio(
                              value: 'all',
                              label: 'All Services / Products',
                              subtitle: 'Applies to any cart item.',
                            ),
                            _ApplicabilityRadio(
                              value: 'categories',
                              label: 'Specific Categories',
                              subtitle:
                                  'Applies when cart has a service under the selected categories.',
                            ),
                            _ApplicabilityRadio(
                              value: 'services',
                              label: 'Specific Services / Products',
                              subtitle:
                                  'Applies only when the exact service is in the cart.',
                            ),
                          ],
                        ),
                      ),

                      // ── Node selector (shown when not 'all') ───────────────
                      if (_applicabilityType != 'all') ...[
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: pickerNodes.isEmpty
                              ? null
                              : () => _openNodePicker(pickerNodes),
                          borderRadius: BorderRadius.circular(8),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: _applicabilityType == 'categories'
                                  ? 'Select Categories *'
                                  : 'Select Services / Products *',
                              prefixIcon: Icon(
                                _applicabilityType == 'categories'
                                    ? Icons.folder_outlined
                                    : Icons.miscellaneous_services_outlined,
                              ),
                              suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
                              errorText: _saving &&
                                      _applicabilityType != 'all' &&
                                      _applicableNodeIds.isEmpty
                                  ? 'Select at least one'
                                  : null,
                            ),
                            child: pickerNodes.isEmpty
                                ? Text(
                                    'Loading…',
                                    style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 14),
                                  )
                                : selectedNames.isEmpty
                                    ? Text(
                                        _applicabilityType == 'categories'
                                            ? 'Tap to select categories'
                                            : 'Tap to select services',
                                        style: TextStyle(
                                            color: AppColors.textSecondary
                                                .withValues(alpha: 0.6),
                                            fontSize: 14),
                                      )
                                    : Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: selectedNames
                                            .map((name) => Chip(
                                                  label: Text(name,
                                                      style: const TextStyle(
                                                          fontSize: 12)),
                                                  materialTapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                  padding: EdgeInsets.zero,
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  deleteIcon: const Icon(
                                                      Icons.close_rounded,
                                                      size: 14),
                                                  onDeleted: () {
                                                    final nodeId = allNodes
                                                        .firstWhere((n) =>
                                                            n.name == name)
                                                        .id;
                                                    setState(() =>
                                                        _applicableNodeIds
                                                            .remove(nodeId));
                                                  },
                                                ))
                                            .toList(),
                                      ),
                          ),
                        ),
                      ],

                      // ── Customer Eligibility section ───────────────────────
                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.person_search_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Customer Eligibility',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Choose how coupon eligibility is determined.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),

                      RadioListTile<String>(
                        value: 'all',
                        groupValue: _customerEligibility,
                        onChanged: (v) {
                          if (v != null) {
                            setState(() {
                              _customerEligibility = v;
                              _selectedCustomerIds = [];
                            });
                          }
                        },
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        title: const Text('Max Order Wise',
                            style: TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w500)),
                        subtitle: Text(
                            'Open to all customers; min-order and applicability rules still apply.',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      ),

                      // Maximum Orders Allowed — shown only for Max Order Wise
                      if (_customerEligibility == 'all') ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _maxOrderWiseLimit,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Minimum Orders Required *',
                            hintText: 'e.g. 5',
                            prefixIcon:
                                Icon(Icons.history_rounded),
                            helperText:
                                'Customers must have at least this many qualifying (non-cancelled) orders to use this coupon.',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Required for Max Order Wise';
                            }
                            final n = int.tryParse(v.trim());
                            if (n == null || n <= 0) {
                              return 'Enter a positive whole number';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                      ],

                      RadioListTile<String>(
                        value: 'selected',
                        groupValue: _customerEligibility,
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _customerEligibility = v);
                          }
                        },
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        title: const Text('Customer ID Based',
                            style: TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w500)),
                        subtitle: Text(
                            'Only customers assigned by their Customer ID can redeem this coupon.',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      ),

                      // Customer picker (shown when 'selected')
                      if (_customerEligibility == 'selected') ...[
                        const SizedBox(height: 12),
                        _CustomerPickerField(
                          selectedIds: _selectedCustomerIds,
                          saving: _saving,
                          onChanged: (ids) =>
                              setState(() => _selectedCustomerIds = ids),
                        ),
                      ],
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

// ── Applicability radio tile ───────────────────────────────────────────────────

class _ApplicabilityRadio extends StatelessWidget {
  final String value;
  final String label;
  final String subtitle;

  const _ApplicabilityRadio({
    required this.value,
    required this.label,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return RadioListTile<String>(
      value: value,
      contentPadding: EdgeInsets.zero,
      dense: true,
      visualDensity: VisualDensity.compact,
      title: Text(label,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
    );
  }
}

// ── Node picker dialog ─────────────────────────────────────────────────────────

class _NodePickerDialog extends StatefulWidget {
  final List<CatalogNode> nodes;
  final List<String> selectedIds;

  const _NodePickerDialog({required this.nodes, required this.selectedIds});

  @override
  State<_NodePickerDialog> createState() => _NodePickerDialogState();
}

class _NodePickerDialogState extends State<_NodePickerDialog> {
  late final Set<String> _selected;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.selectedIds);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _search.isEmpty
        ? widget.nodes
        : widget.nodes
            .where((n) =>
                n.name.toLowerCase().contains(_search.toLowerCase()))
            .toList();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.checklist_rounded,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Select Items',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // Search
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search…',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),

            // List
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text('No items found.',
                          style: TextStyle(color: AppColors.textSecondary)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final node = filtered[i];
                        return CheckboxListTile(
                          value: _selected.contains(node.id),
                          onChanged: (checked) {
                            setState(() {
                              if (checked == true) {
                                _selected.add(node.id);
                              } else {
                                _selected.remove(node.id);
                              }
                            });
                          },
                          title: Text(node.name,
                              style: const TextStyle(fontSize: 13.5)),
                          subtitle: node.parentName != null
                              ? Text(node.parentName!,
                                  style: const TextStyle(fontSize: 11))
                              : null,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12),
                        );
                      },
                    ),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Text(
                    '${_selected.length} selected',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_selected.toList()),
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary),
                    child: const Text('Confirm'),
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

// ── Customer picker field (inline widget, opens dialog) ───────────────────────

class _CustomerPickerField extends ConsumerWidget {
  final List<String> selectedIds;
  final bool saving;
  final void Function(List<String>) onChanged;

  const _CustomerPickerField({
    required this.selectedIds,
    required this.saving,
    required this.onChanged,
  });

  Future<void> _open(BuildContext context, List<Customer> allCustomers) async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => _CustomerPickerDialog(
        customers: allCustomers,
        selectedIds: selectedIds,
      ),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allCustomers =
        ref.watch(customersNotifierProvider).valueOrNull ?? [];
    final selectedCustomers = allCustomers
        .where((c) => selectedIds.contains(c.id))
        .toList()
      ..sort((a, b) =>
          (a.customerNumber ?? a.id).compareTo(b.customerNumber ?? b.id));

    return InkWell(
      onTap: allCustomers.isEmpty
          ? null
          : () => _open(context, allCustomers),
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Select Customers *',
          prefixIcon: const Icon(Icons.group_outlined),
          suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
          errorText: saving && selectedIds.isEmpty
              ? 'Select at least one customer'
              : null,
        ),
        child: allCustomers.isEmpty
            ? Text('Loading…',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 14))
            : selectedCustomers.isEmpty
                ? Text('Tap to select customers',
                    style: TextStyle(
                        color:
                            AppColors.textSecondary.withValues(alpha: 0.6),
                        fontSize: 14))
                : Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: selectedCustomers
                        .map((c) => InputChip(
                              label: Text(
                                c.customerNumber != null
                                    ? '${c.customerNumber} · ${c.fullName.isEmpty ? '(no name)' : c.fullName}'
                                    : (c.fullName.isEmpty
                                        ? '(no name)'
                                        : c.fullName),
                                style: const TextStyle(fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                              onPressed: () =>
                                  _showCustomerProfile(context, c.id),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              deleteIcon: const Icon(
                                  Icons.close_rounded, size: 14),
                              onDeleted: () => onChanged(
                                selectedIds
                                    .where((s) => s != c.id)
                                    .toList(),
                              ),
                            ))
                        .toList(),
                  ),
      ),
    );
  }
}

// ── Customer picker dialog ─────────────────────────────────────────────────────

class _CustomerPickerDialog extends StatefulWidget {
  final List<Customer> customers;
  final List<String> selectedIds;

  const _CustomerPickerDialog(
      {required this.customers, required this.selectedIds});

  @override
  State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog> {
  late final Set<String> _selected;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.selectedIds);
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.toLowerCase();
    final filtered = _search.isEmpty
        ? widget.customers
        : widget.customers
            .where((c) =>
                (c.customerNumber?.toLowerCase().contains(q) ?? false) ||
                c.fullName.toLowerCase().contains(q) ||
                c.phone.toLowerCase().contains(q) ||
                c.email.toLowerCase().contains(q))
            .toList();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.people_rounded,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Select Customers',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search by Customer ID, name, phone or email…',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text('No customers found.',
                          style:
                              TextStyle(color: AppColors.textSecondary)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final c = filtered[i];
                        final contact = [
                          if (c.phone.isNotEmpty) c.phone,
                          if (c.email.isNotEmpty) c.email,
                        ].join(' · ');
                        return InkWell(
                          onTap: () => _toggleSelection(c.id),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: Checkbox(
                                    value: _selected.contains(c.id),
                                    onChanged: (checked) => setState(() {
                                      if (checked == true) {
                                        _selected.add(c.id);
                                      } else {
                                        _selected.remove(c.id);
                                      }
                                    }),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Customer ID badge — tapping opens full profile
                                GestureDetector(
                                  onTap: () =>
                                      _showCustomerProfile(context, c.id),
                                  behavior: HitTestBehavior.opaque,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      c.customerNumber ?? '—',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        c.fullName.isEmpty
                                            ? '(No name)'
                                            : c.fullName,
                                        style: const TextStyle(
                                            fontSize: 13.5),
                                      ),
                                      if (contact.isNotEmpty)
                                        Text(
                                          contact,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Text(
                    '${_selected.length} selected',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_selected.toList()),
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary),
                    child: const Text('Confirm'),
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

// ── Customer profile modal ─────────────────────────────────────────────────────

void _showCustomerProfile(BuildContext context, String customerId) {
  showDialog<void>(
    context: context,
    builder: (ctx) => _CustomerProfileModal(customerId: customerId),
  );
}

class _CustomerProfileModal extends ConsumerWidget {
  const _CustomerProfileModal({required this.customerId});
  final String customerId;

  static final _currencyFmt =
      NumberFormat.currency(symbol: '₹', decimalDigits: 2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(customerProfileProvider(customerId));

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      profileAsync.maybeWhen(
                        data: (p) => p.customer.fullName.isEmpty
                            ? 'Customer Profile'
                            : p.customer.fullName,
                        orElse: () => 'Customer Profile',
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // Body
            Flexible(
              child: profileAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(48),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          size: 40, color: AppColors.error),
                      const SizedBox(height: 12),
                      const Text(
                        'Failed to load customer profile',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        e.toString(),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                data: (profile) => SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: _ProfileModalBody(
                    profile: profile,
                    currencyFmt: _currencyFmt,
                  ),
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileModalBody extends StatelessWidget {
  const _ProfileModalBody({
    required this.profile,
    required this.currencyFmt,
  });
  final CustomerProfile profile;
  final NumberFormat currencyFmt;

  @override
  Widget build(BuildContext context) {
    final c = profile.customer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Identity ────────────────────────────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              backgroundImage:
                  c.profileImageUrl != null && c.profileImageUrl!.isNotEmpty
                      ? NetworkImage(c.profileImageUrl!) as ImageProvider
                      : null,
              child: c.profileImageUrl == null || c.profileImageUrl!.isEmpty
                  ? Text(
                      c.fullName.isNotEmpty
                          ? c.fullName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (c.customerNumber != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            c.customerNumber!,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: c.isActive
                              ? AppColors.success.withValues(alpha: 0.1)
                              : AppColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          c.isActive ? 'Active' : 'Inactive',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: c.isActive
                                ? AppColors.success
                                : AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (c.phone.isNotEmpty)
                    Text(c.phone,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)),
                  if (c.email.isNotEmpty)
                    Text(c.email,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)),
                  if (c.createdAt != null)
                    Text(
                      'Joined ${_dateFmt.format(c.createdAt!)}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Booking stats ───────────────────────────────────────────────────────
        Row(
          children: [
            _MiniStat('Total', '${profile.totalBookings}', AppColors.primary),
            const SizedBox(width: 8),
            _MiniStat('Completed', '${profile.completedBookings}',
                AppColors.success),
            const SizedBox(width: 8),
            _MiniStat(
                'Pending', '${profile.pendingBookings}', AppColors.warning),
            const SizedBox(width: 8),
            _MiniStat(
                'Cancelled', '${profile.cancelledBookings}', AppColors.error),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.currency_rupee_rounded,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                currencyFmt.format(profile.totalSpent),
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(width: 6),
              const Text(
                'total spent (completed)',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),

        // Addresses ───────────────────────────────────────────────────────────
        if (profile.addresses.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Saved Addresses',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          ...profile.addresses.map(_AddressCard.new),
        ],

        // Recent bookings ─────────────────────────────────────────────────────
        if (profile.bookings.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Recent Bookings',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          ...profile.bookings.take(5).map(_BookingRow.new),
          if (profile.bookings.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+ ${profile.bookings.length - 5} more bookings',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
        ],
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: color)),
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textSecondary),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard(this.address);
  final CustomerAddress address;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.location_on_outlined,
                size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      address.addressLine1,
                      if (address.addressLine2 != null &&
                          address.addressLine2!.isNotEmpty)
                        address.addressLine2!,
                      address.city,
                    ].where((s) => s.isNotEmpty).join(', '),
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    '${address.state} – ${address.pincode}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            if (address.isDefault)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('Default',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ),
          ],
        ),
      ),
    );
  }
}

class _BookingRow extends StatelessWidget {
  const _BookingRow(this.booking);
  final CustomerBooking booking;

  @override
  Widget build(BuildContext context) {
    final (label, textColor, bgColor) = booking.statusConfig;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
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
                    booking.bookingNumber ??
                        'BK-${booking.id.substring(0, 8).toUpperCase()}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  if (booking.items.isNotEmpty)
                    Text(
                      booking.items
                          .map((i) => i.serviceName)
                          .where((s) => s.isNotEmpty)
                          .join(', '),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: textColor)),
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
