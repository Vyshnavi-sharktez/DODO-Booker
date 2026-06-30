import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';

final _dateFmt = DateFormat('dd MMM yyyy');

class CreateBookingDialog extends StatefulWidget {
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
  }) onCreate;

  @override
  State<CreateBookingDialog> createState() => _CreateBookingDialogState();
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

class _CreateBookingDialogState extends State<CreateBookingDialog> {
  final _formKey = GlobalKey<FormState>();
  final _customerIdCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final List<_ItemFields> _items = [_ItemFields()];

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

  Future<void> _submit() async {
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

    setState(() => _creating = true);
    try {
      await widget.onCreate(
        customerId: _customerIdCtrl.text.trim(),
        serviceDate: _serviceDate!,
        address: _addressCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        items: bookingItems,
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
        width: 480,
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
          onPressed: _creating ? null : _submit,
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
