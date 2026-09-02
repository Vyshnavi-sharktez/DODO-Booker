import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../catalog_v2/application/providers/catalog_node_providers.dart';
import '../../../catalog_v2/domain/models/catalog_node.dart';
import '../../domain/models/service_addon.dart';

class AddonFormDialog extends ConsumerStatefulWidget {
  final ServiceAddon? existing;
  final Future<void> Function({
    required String name,
    String? description,
    required double price,
    required bool isActive,
    String? serviceId,
    String discountType,
    double discountValue,
  }) onSave;

  const AddonFormDialog({
    super.key,
    this.existing,
    required this.onSave,
  });

  @override
  ConsumerState<AddonFormDialog> createState() => _AddonFormDialogState();
}

class _AddonFormDialogState extends ConsumerState<AddonFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;
  late bool _isActive;
  String? _selectedServiceId;
  late String _discountType;
  late final TextEditingController _discountValue;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _price = TextEditingController(
      text: e != null ? e.price.toStringAsFixed(2) : '',
    );
    _isActive = e?.isActive ?? true;
    _selectedServiceId = e?.serviceId;
    _discountType = e?.discountType ?? 'percentage';
    _discountValue = TextEditingController(
      text: (e != null && e.discountValue > 0)
          ? e.discountValue.toStringAsFixed(0)
          : '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _discountValue.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        name: _name.text.trim(),
        price: double.parse(_price.text.trim()),
        isActive: _isActive,
        serviceId: _selectedServiceId,
        discountType: _discountType,
        discountValue: double.tryParse(_discountValue.text.trim()) ?? 0,
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
    final nodesAsync = ref.watch(catalogNodeNotifierProvider);
    final leafNodes = nodesAsync.valueOrNull
            ?.where((n) => n.isBookable && n.childrenCount == 0)
            .toList() ??
        [];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ────────────────────────────────────────────────────
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
                    isEdit ? 'Edit Add-on' : 'New Add-on',
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

            // ── Form ──────────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Add-on Name *',
                          hintText: 'e.g. Deep Cleaning Spray',
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),

                      // Price
                      TextFormField(
                        controller: _price,
                        decoration: const InputDecoration(
                          labelText: 'Price (₹) *',
                          hintText: '0.00',
                          prefixText: '₹ ',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          final p = double.tryParse(v.trim());
                          if (p == null || p < 0) return 'Enter a valid price';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Service assignment
                      _ServiceSelector(
                        leafNodes: leafNodes,
                        selectedId: _selectedServiceId,
                        loading: nodesAsync.isLoading,
                        onChanged: (id) =>
                            setState(() => _selectedServiceId = id),
                      ),
                      const SizedBox(height: 20),

                      // Active toggle
                      _ToggleRow(
                        icon: Icons.visibility_off_outlined,
                        activeIcon: Icons.visibility_rounded,
                        label: 'Active',
                        subtitle: 'Inactive add-ons are hidden from customers',
                        value: _isActive,
                        activeColor: AppColors.success,
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text(
                            'Discount',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '(optional)',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ToggleButtons(
                            isSelected: [
                              _discountType == 'percentage',
                              _discountType == 'flat',
                            ],
                            onPressed: (i) => setState(() =>
                                _discountType =
                                    i == 0 ? 'percentage' : 'flat'),
                            borderRadius: BorderRadius.circular(6),
                            selectedColor: Colors.white,
                            fillColor: AppColors.primary,
                            textStyle: const TextStyle(fontSize: 13),
                            constraints: const BoxConstraints(
                                minWidth: 44, minHeight: 42),
                            children: const [
                              Padding(
                                padding:
                                    EdgeInsets.symmetric(horizontal: 12),
                                child: Text('%'),
                              ),
                              Padding(
                                padding:
                                    EdgeInsets.symmetric(horizontal: 12),
                                child: Text('₹'),
                              ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _discountValue,
                              decoration: InputDecoration(
                                labelText: _discountType == 'percentage'
                                    ? 'Discount %'
                                    : 'Discount ₹',
                                hintText: '0',
                                prefixText: _discountType == 'flat'
                                    ? '₹ '
                                    : null,
                                suffixText: _discountType == 'percentage'
                                    ? '%'
                                    : null,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d{0,2}')),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Footer ────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.border))),
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
                        : Text(isEdit ? 'Save Changes' : 'Create Add-on'),
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

// ── Service selector ──────────────────────────────────────────────────────────

class _ServiceSelector extends StatelessWidget {
  const _ServiceSelector({
    required this.leafNodes,
    required this.selectedId,
    required this.loading,
    required this.onChanged,
  });

  final List<CatalogNode> leafNodes;
  final String? selectedId;
  final bool loading;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Assign to Service',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        loading
            ? const SizedBox(
                height: 48,
                child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : DropdownButtonFormField<String?>(
                value: selectedId,
                isExpanded: true,
                decoration: const InputDecoration(
                  hintText: 'No service (unassigned)',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('No service (unassigned)',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ),
                  ...leafNodes.map((n) => DropdownMenuItem<String?>(
                        value: n.id,
                        child: Text(
                          n.parentName != null
                              ? '${n.parentName} › ${n.name}'
                              : n.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )),
                ],
                onChanged: onChanged,
              ),
        const SizedBox(height: 4),
        Text(
          'Customers see only the add-ons assigned to the service they are viewing.',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

// ── Toggle row ────────────────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String subtitle;
  final bool value;
  final Color activeColor;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            value ? activeIcon : icon,
            color: value ? activeColor : AppColors.textSecondary,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: activeColor,
          ),
        ],
      ),
    );
  }
}
