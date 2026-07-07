import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../service_addons/application/providers/service_addons_providers.dart';
import '../../../service_addons/domain/models/service_addon.dart';

final _dateFmt = DateFormat('dd MMM yyyy');

class CreateBookingDialog extends ConsumerStatefulWidget {
  const CreateBookingDialog({
    super.key,
    required this.onCreate,
  });

  final Future<void> Function({
    required String customerId,
    required DateTime serviceDate,
    required String address,
    String? notes,
    required List<({
      String serviceId,
      int quantity,
      double unitPrice,
    })> items,
    required List<({
      String addonId,
      String addonName,
      double addonPrice,
    })> addons,
  }) onCreate;

  @override
  ConsumerState<CreateBookingDialog> createState() =>
      _CreateBookingDialogState();
}

class _ItemFields {
  _ItemFields()
      : serviceId = TextEditingController(),
        quantity = TextEditingController(text: '1'),
        unitPrice = TextEditingController();

  final TextEditingController serviceId;
  final TextEditingController quantity;
  final TextEditingController unitPrice;

  void dispose() {
    serviceId.dispose();
    quantity.dispose();
    unitPrice.dispose();
  }
}

class _CreateBookingDialogState extends ConsumerState<CreateBookingDialog> {
  final _formKey = GlobalKey<FormState>();
  final _customerIdCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final List<_ItemFields> _items = [_ItemFields()];
  final Set<String> _selectedAddonIds = {};

  DateTime? _serviceDate;
  bool _creating = false;

  @override
  void dispose() {
    _customerIdCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _addItem() {
    setState(() => _items.add(_ItemFields()));
  }

  void _removeItem(int index) {
    if (_items.length <= 1) return;
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _serviceDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _serviceDate = picked);
  }

  Future<void> _submit(List<ServiceAddon> allAddons) async {
    if (!_formKey.currentState!.validate()) return;
    if (_serviceDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a service date')),
      );
      return;
    }

    final bookingItems = <({String serviceId, int quantity, double unitPrice})>[];
    for (final item in _items) {
      bookingItems.add((
        serviceId: item.serviceId.text.trim(),
        quantity: int.parse(item.quantity.text.trim()),
        unitPrice: double.parse(item.unitPrice.text.trim()),
      ));
    }

    final selectedAddons = allAddons
        .where((a) => _selectedAddonIds.contains(a.id))
        .map((a) => (addonId: a.id, addonName: a.name, addonPrice: a.price))
        .toList();

    setState(() => _creating = true);
    try {
      await widget.onCreate(
        customerId: _customerIdCtrl.text.trim(),
        serviceDate: _serviceDate!,
        address: _addressCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        items: bookingItems,
        addons: selectedAddons,
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
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final addonsAsync = ref.watch(allAddonsNotifierProvider);
    final allAddons = addonsAsync.valueOrNull
            ?.where((a) => a.isActive)
            .toList() ??
        [];

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text(
        'Create Booking',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _customerIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Customer ID *',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _addressCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Address *',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(8),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Service Date *',
                      prefixIcon: Icon(Icons.calendar_today_rounded),
                    ),
                    child: Text(
                      _serviceDate != null
                          ? _dateFmt.format(_serviceDate!)
                          : 'Select date',
                      style: TextStyle(
                        fontSize: 14,
                        color: _serviceDate != null
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    hintText: 'Optional notes',
                    prefixIcon: Icon(Icons.notes_rounded),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Booking Items *',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _addItem,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Item'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < _items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _BookingItemRow(
                    index: i,
                    fields: _items[i],
                    canRemove: _items.length > 1,
                    onRemove: () => _removeItem(i),
                  ),
                ],

                // ── Suggested Add-ons ──────────────────────────────────────
                if (addonsAsync.isLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (allAddons.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Suggested Add-ons',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Optional',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFD4AF37),
                          ),
                        ),
                      ),
                      if (_selectedAddonIds.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_selectedAddonIds.length} selected',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: allAddons.map((addon) {
                      final isSelected = _selectedAddonIds.contains(addon.id);
                      return _AddonChip(
                        addon: addon,
                        isSelected: isSelected,
                        onToggle: () => setState(() {
                          if (isSelected) {
                            _selectedAddonIds.remove(addon.id);
                          } else {
                            _selectedAddonIds.add(addon.id);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _creating ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _creating ? null : () => _submit(allAddons),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: _creating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}

class _BookingItemRow extends StatelessWidget {
  const _BookingItemRow({
    required this.index,
    required this.fields,
    required this.canRemove,
    required this.onRemove,
  });

  final int index;
  final _ItemFields fields;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Item ${index + 1}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              if (canRemove)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.remove_circle_outline_rounded,
                      size: 20),
                  color: AppColors.error,
                  tooltip: 'Remove item',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: fields.serviceId,
            decoration: const InputDecoration(
              labelText: 'Service ID *',
              isDense: true,
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: fields.quantity,
                  decoration: const InputDecoration(
                    labelText: 'Quantity *',
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    final n = int.tryParse(v.trim());
                    if (n == null || n < 1) return 'Min 1';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: fields.unitPrice,
                  decoration: const InputDecoration(
                    labelText: 'Unit Price *',
                    prefixText: '₹ ',
                    isDense: true,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    final n = double.tryParse(v.trim());
                    if (n == null || n < 0) return 'Invalid';
                    return null;
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddonChip extends StatelessWidget {
  final ServiceAddon addon;
  final bool isSelected;
  final VoidCallback onToggle;

  const _AddonChip({
    required this.addon,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.08)
              : AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              size: 16,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              addon.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? AppColors.primary
                    : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '+ ₹${addon.price.toInt()}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? const Color(0xFFD4AF37)
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
