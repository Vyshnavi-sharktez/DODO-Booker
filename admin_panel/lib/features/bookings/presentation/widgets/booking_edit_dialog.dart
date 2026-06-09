import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../vendors/application/providers/vendors_providers.dart';
import '../../../vendors/domain/models/vendor.dart';
import '../../domain/models/booking.dart';

const _statusOptions = [
  ('pending', 'Pending'),
  ('assigned', 'Assigned'),
  ('in_progress', 'In Progress'),
  ('completed', 'Completed'),
  ('cancelled', 'Cancelled'),
];

final _dateFmt = DateFormat('dd MMM yyyy');

class BookingEditDialog extends ConsumerStatefulWidget {
  final Booking booking;
  final Future<void> Function({
    required String vendorId,
    required DateTime serviceDate,
    required String status,
    String? notes,
  }) onSave;

  const BookingEditDialog({
    super.key,
    required this.booking,
    required this.onSave,
  });

  @override
  ConsumerState<BookingEditDialog> createState() => _BookingEditDialogState();
}

class _BookingEditDialogState extends ConsumerState<BookingEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _notes;
  late String _vendorId;
  late DateTime? _serviceDate;
  late String _status;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _notes = TextEditingController(text: widget.booking.notes ?? '');
    _vendorId = widget.booking.vendorId;
    _serviceDate = widget.booking.serviceDate;
    _status = widget.booking.status;
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
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
    setState(() => _saving = true);
    try {
      await widget.onSave(
        vendorId: _vendorId,
        serviceDate: _serviceDate!,
        status: _status,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
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
    final vendorsAsync = ref.watch(vendorsNotifierProvider);
    final vendors = vendorsAsync.valueOrNull ?? <Vendor>[];

    // Ensure the current vendorId is representable in the dropdown.
    final vendorIds = vendors.map((v) => v.id).toSet();
    final currentVendorKnown = vendorIds.contains(_vendorId);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 500,
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
                  const Icon(Icons.edit_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Edit #${widget.booking.bookingNumber}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
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

            // ── Form ────────────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Vendor dropdown
                      DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: currentVendorKnown ? _vendorId : null,
                        decoration: const InputDecoration(
                          labelText: 'Vendor *',
                          prefixIcon: Icon(Icons.store_rounded),
                        ),
                        isExpanded: true,
                        items: [
                          if (!currentVendorKnown)
                            DropdownMenuItem(
                              value: _vendorId,
                              child: Text(
                                'Unknown vendor (${_vendorId.substring(0, 8)}…)',
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13),
                              ),
                            ),
                          ...vendors.map(
                            (v) => DropdownMenuItem(
                              value: v.id,
                              child: Text(v.businessName),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _vendorId = v);
                        },
                        validator: (v) => v == null ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),

                      // Service date picker
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

                      // Status dropdown
                      DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _status,
                        decoration: const InputDecoration(
                          labelText: 'Status *',
                          prefixIcon: Icon(Icons.flag_rounded),
                        ),
                        items: _statusOptions
                            .map(
                              (s) => DropdownMenuItem(
                                value: s.$1,
                                child: Text(s.$2),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _status = v);
                        },
                        validator: (v) => v == null ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),

                      // Notes
                      TextFormField(
                        controller: _notes,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          hintText: 'Additional notes',
                          prefixIcon: Icon(Icons.notes_rounded),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
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
                        : const Text('Save Changes'),
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
