import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../customers/application/providers/customers_providers.dart';
import '../../../services/application/providers/services_providers.dart';
import '../../../services/domain/models/service.dart';

final _dateFmt = DateFormat('dd MMM yyyy');
final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

typedef OnCreateBooking = Future<void> Function({
  required String customerId,
  required DateTime serviceDate,
  required String address,
  String? notes,
  required List<({String serviceId, int quantity, double unitPrice})> items,
});

class _ServiceEntry {
  final Service service;
  int quantity;
  _ServiceEntry({required this.service, this.quantity = 1});
  double get total => service.basePrice * quantity;
}

class CreateBookingDialog extends ConsumerStatefulWidget {
  final OnCreateBooking onCreate;

  const CreateBookingDialog({super.key, required this.onCreate});

  @override
  ConsumerState<CreateBookingDialog> createState() =>
      _CreateBookingDialogState();
}

class _CreateBookingDialogState extends ConsumerState<CreateBookingDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedCustomerId;
  DateTime? _serviceDate;
  final _address = TextEditingController();
  final _notes = TextEditingController();
  Service? _pendingService;
  final List<_ServiceEntry> _entries = [];
  bool _saving = false;

  @override
  void dispose() {
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  double get _subtotal =>
      _entries.fold(0.0, (sum, e) => sum + e.total);

  void _addPending() {
    if (_pendingService == null) return;
    final idx =
        _entries.indexWhere((e) => e.service.id == _pendingService!.id);
    if (idx >= 0) {
      setState(() {
        _entries[idx].quantity++;
        _pendingService = null;
      });
    } else {
      setState(() {
        _entries.add(_ServiceEntry(service: _pendingService!));
        _pendingService = null;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _serviceDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _serviceDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a customer')),
      );
      return;
    }
    if (_serviceDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a service date')),
      );
      return;
    }
    if (_entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one service')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.onCreate(
        customerId: _selectedCustomerId!,
        serviceDate: _serviceDate!,
        address: _address.text.trim(),
        notes:
            _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        items: _entries
            .map((e) => (
                  serviceId: e.service.id,
                  quantity: e.quantity,
                  unitPrice: e.service.basePrice,
                ))
            .toList(),
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
    final customers =
        ref.watch(customersNotifierProvider).valueOrNull ?? [];
    final allServices =
        ref.watch(servicesNotifierProvider).valueOrNull ?? [];
    final services =
        allServices.where((s) => s.isActive).toList();
    final selectedServiceIds = _entries.map((e) => e.service.id).toSet();
    final availableServices =
        services.where((s) => !selectedServiceIds.contains(s.id)).toList();

    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
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
                  const Icon(Icons.book_online_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  const Text(
                    'New Booking',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // ── Content ───────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Customer
                      _Label('Customer'),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _selectedCustomerId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          hintText: 'Select customer',
                          prefixIcon: Icon(Icons.person_rounded),
                        ),
                        items: customers
                            .map(
                              (c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(
                                  c.fullName.isNotEmpty
                                      ? c.fullName
                                      : c.email,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedCustomerId = v),
                        validator: (v) =>
                            v == null ? 'Please select a customer' : null,
                      ),
                      const SizedBox(height: 20),

                      // Services
                      _Label('Services'),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<Service>(
                              // ignore: deprecated_member_use
                              value: _pendingService,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                hintText: 'Add a service',
                                prefixIcon: Icon(
                                    Icons.home_repair_service_rounded),
                              ),
                              items: availableServices
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(
                                        s.name,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _pendingService = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 48,
                            child: FilledButton(
                              onPressed: _pendingService != null
                                  ? _addPending
                                  : null,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.accent,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20),
                              ),
                              child: const Text('Add'),
                            ),
                          ),
                        ],
                      ),

                      if (_entries.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children:
                                _entries.asMap().entries.map((entry) {
                              final i = entry.key;
                              final e = entry.value;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  border: i > 0
                                      ? Border(
                                          top: BorderSide(
                                              color: AppColors.border))
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        e.service.name,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      onPressed: e.quantity > 1
                                          ? () =>
                                              setState(() => e.quantity--)
                                          : null,
                                      icon: const Icon(
                                          Icons.remove_circle_outline_rounded,
                                          size: 18),
                                      visualDensity:
                                          VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                    ),
                                    SizedBox(
                                      width: 28,
                                      child: Text(
                                        '${e.quantity}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () =>
                                          setState(() => e.quantity++),
                                      icon: const Icon(
                                          Icons.add_circle_outline_rounded,
                                          size: 18),
                                      visualDensity:
                                          VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                    ),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 72,
                                      child: Text(
                                        _currency.format(e.total),
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      onPressed: () => setState(
                                          () => _entries.removeAt(i)),
                                      icon: Icon(Icons.close_rounded,
                                          size: 16,
                                          color: AppColors.error),
                                      visualDensity:
                                          VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 10, right: 4),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'Total  ${_currency.format(_subtotal)}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),

                      // Service date
                      _Label('Service Date'),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(8),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.calendar_today_rounded),
                          ),
                          child: Text(
                            _serviceDate != null
                                ? _dateFmt.format(_serviceDate!)
                                : 'Select service date',
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

                      // Address
                      _Label('Address (optional)'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _address,
                        decoration: const InputDecoration(
                          hintText: 'Service address',
                          prefixIcon: Icon(Icons.location_on_rounded),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 2,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                      const SizedBox(height: 16),

                      // Notes
                      _Label('Notes (optional)'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _notes,
                        decoration: const InputDecoration(
                          hintText: 'Any special instructions',
                          prefixIcon: Icon(Icons.notes_rounded),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 2,
                        textCapitalization: TextCapitalization.sentences,
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
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Create Booking'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
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

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
        letterSpacing: 1.0,
      ),
    );
  }
}
