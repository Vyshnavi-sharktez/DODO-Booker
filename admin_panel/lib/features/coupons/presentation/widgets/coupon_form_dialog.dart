import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../catalog_v2/application/providers/catalog_node_providers.dart';
import '../../../catalog_v2/domain/models/catalog_node.dart';
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
  late String _discountType;
  late DateTime? _validFrom;
  late DateTime? _validTo;
  late bool _isActive;
  late String _applicabilityType;
  late List<String> _applicableNodeIds;
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
    _discountType = e?.discountType ?? 'percentage';
    _validFrom = e?.validFrom ?? DateTime.now();
    _validTo = e?.validTo;
    _isActive = e?.isActive ?? true;
    _applicabilityType = e?.applicabilityType ?? 'all';
    _applicableNodeIds = List<String>.from(e?.applicableNodeIds ?? []);
  }

  @override
  void dispose() {
    _code.dispose();
    _description.dispose();
    _discountValue.dispose();
    _minOrderAmount.dispose();
    _maxDiscountAmount.dispose();
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
        maxDiscountAmount: _maxDiscountAmount.text.trim().isEmpty
            ? null
            : double.tryParse(_maxDiscountAmount.text.trim()),
        usageLimit: limitText.isEmpty ? null : int.tryParse(limitText),
        validFrom: _validFrom,
        validTo: _validTo,
        isActive: _isActive,
        applicabilityType: _applicabilityType,
        applicableNodeIds: _applicabilityType == 'all' ? [] : _applicableNodeIds,
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
