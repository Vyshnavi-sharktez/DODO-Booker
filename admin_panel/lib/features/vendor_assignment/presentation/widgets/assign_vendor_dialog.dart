import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../bookings/domain/models/booking.dart';
import '../../../vendors/domain/models/vendor.dart';
import '../../application/providers/vendor_assignment_providers.dart';

final _dateFmt = DateFormat('dd MMM yyyy');

const _statusOptions = [
  ('assigned', 'Assigned'),
  ('in_progress', 'In Progress'),
];

class AssignVendorDialog extends ConsumerStatefulWidget {
  final Booking booking;
  final String customerName;
  final String currentVendorName;

  final Future<void> Function({
    required String vendorId,
    required String vendorName,
    required DateTime serviceDate,
    required String status,
    String? notes,
  }) onAssign;

  const AssignVendorDialog({
    super.key,
    required this.booking,
    required this.customerName,
    required this.currentVendorName,
    required this.onAssign,
  });

  @override
  ConsumerState<AssignVendorDialog> createState() =>
      _AssignVendorDialogState();
}

class _AssignVendorDialogState extends ConsumerState<AssignVendorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _notes;
  late String? _selectedVendorId;
  late DateTime? _serviceDate;
  late String _status;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _notes = TextEditingController(text: widget.booking.notes ?? '');
    _serviceDate = widget.booking.serviceDate;
    // Pre-select current vendor if it's active.
    _selectedVendorId = widget.booking.vendorId.isNotEmpty
        ? widget.booking.vendorId
        : null;
    // Default to 'assigned'; if already further along keep current.
    _status = (widget.booking.status == 'in_progress')
        ? 'in_progress'
        : 'assigned';
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
    if (_selectedVendorId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a vendor')),
      );
      return;
    }
    if (_serviceDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a service date')),
      );
      return;
    }

    final activeVendors = ref.read(activeVendorsProvider);
    final vendor =
        activeVendors.firstWhere((v) => v.id == _selectedVendorId);

    setState(() => _saving = true);
    try {
      await widget.onAssign(
        vendorId: _selectedVendorId!,
        vendorName: vendor.businessName,
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
    final activeVendors = ref.watch(activeVendorsProvider);
    final vendorIds = activeVendors.map((v) => v.id).toSet();

    // If pre-selected vendorId is not in active list, clear it.
    if (_selectedVendorId != null && !vendorIds.contains(_selectedVendorId)) {
      _selectedVendorId = null;
    }

    final isReassign = widget.booking.vendorId.isNotEmpty &&
        widget.booking.status != 'pending';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
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
                    isReassign
                        ? Icons.swap_horiz_rounded
                        : Icons.assignment_ind_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isReassign
                        ? 'Reassign Vendor — #${widget.booking.bookingNumber}'
                        : 'Assign Vendor — #${widget.booking.bookingNumber}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Booking info card ──────────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          children: [
                            _InfoRow(
                              label: 'Booking #',
                              value: widget.booking.bookingNumber,
                            ),
                            _InfoRow(
                              label: 'Customer',
                              value: widget.customerName,
                            ),
                            _InfoRow(
                              label: 'Current Status',
                              value: _statusLabel(widget.booking.status),
                            ),
                            if (widget.currentVendorName.isNotEmpty)
                              _InfoRow(
                                label: 'Current Vendor',
                                value: widget.currentVendorName,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Vendor dropdown ────────────────────────────────────
                      if (activeVendors.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.error.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_rounded,
                                  color: AppColors.error, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                'No active vendors available for assignment.',
                                style: TextStyle(
                                    color: AppColors.error, fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      else
                        DropdownButtonFormField<String>(
                          // ignore: deprecated_member_use
                          value: _selectedVendorId,
                          decoration: const InputDecoration(
                            labelText: 'Assign to Vendor *',
                            prefixIcon: Icon(Icons.store_rounded),
                          ),
                          isExpanded: true,
                          items: activeVendors
                              .map(
                                (v) => DropdownMenuItem(
                                  value: v.id,
                                  child: _VendorDropdownItem(vendor: v),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _selectedVendorId = v),
                          validator: (v) =>
                              v == null ? 'Please select a vendor' : null,
                        ),
                      const SizedBox(height: 16),

                      // ── Service date ───────────────────────────────────────
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

                      // ── Status ─────────────────────────────────────────────
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

                      // ── Notes ──────────────────────────────────────────────
                      TextFormField(
                        controller: _notes,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          hintText: 'Assignment notes (optional)',
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
                            horizontal: 24, vertical: 12)),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed:
                        (_saving || activeVendors.isEmpty) ? null : _submit,
                    icon: Icon(
                      isReassign
                          ? Icons.swap_horiz_rounded
                          : Icons.assignment_ind_rounded,
                      size: 16,
                    ),
                    label: Text(isReassign ? 'Reassign' : 'Assign'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 12),
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

// ── Helpers ───────────────────────────────────────────────────────────────────

String _statusLabel(String status) {
  const map = {
    'pending': 'Pending',
    'assigned': 'Assigned',
    'in_progress': 'In Progress',
    'completed': 'Completed',
    'cancelled': 'Cancelled',
  };
  return map[status] ?? status;
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _VendorDropdownItem extends StatelessWidget {
  final Vendor vendor;

  const _VendorDropdownItem({required this.vendor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(vendor.businessName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14)),
        ),
        const SizedBox(width: 8),
        if (vendor.rating != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star_rounded,
                  size: 13, color: Color(0xFFDD6B20)),
              const SizedBox(width: 2),
              Text(vendor.rating!.toStringAsFixed(1),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
      ],
    );
  }
}
