import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../vendors/application/providers/vendor_detail_providers.dart';
import '../../../vendors/application/providers/vendors_providers.dart';
import '../../../vendors/domain/models/vendor.dart';
import '../../domain/models/booking.dart';
import '../../domain/services/vendor_assignment_service.dart';

const _statusOptions = [
  ('pending', 'Pending'),
  ('assigned', 'Assigned'),
  ('in_progress', 'In Progress'),
  ('completed', 'Completed'),
  ('cancelled', 'Cancelled'),
];

final _dateFmt = DateFormat('dd MMM yyyy');

enum _AssignMode { auto, manual }

// ── Dialog ─────────────────────────────────────────────────────────────────────

class BookingAssignmentDialog extends ConsumerStatefulWidget {
  final Booking booking;
  final Future<void> Function({
    required String vendorId,
    required DateTime serviceDate,
    required String status,
    String? notes,
  }) onSave;

  const BookingAssignmentDialog({
    super.key,
    required this.booking,
    required this.onSave,
  });

  @override
  ConsumerState<BookingAssignmentDialog> createState() =>
      _BookingAssignmentDialogState();
}

class _BookingAssignmentDialogState
    extends ConsumerState<BookingAssignmentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _notesCtrl;

  late _AssignMode _mode;
  late String _vendorId;
  late DateTime? _serviceDate;
  late String _status;
  bool _saving = false;

  // Tracks whether the current _vendorId was selected via auto mode.
  bool _autoSelected = false;
  double? _autoSelectedDistanceKm;

  bool get _bookingHasLocation =>
      widget.booking.latitude != null && widget.booking.longitude != null;

  @override
  void initState() {
    super.initState();
    _notesCtrl = TextEditingController(text: widget.booking.notes ?? '');
    _vendorId = widget.booking.vendorId;
    _serviceDate = widget.booking.serviceDate;
    _status = widget.booking.status;
    // Default to auto when the booking has coordinates.
    _mode = _bookingHasLocation ? _AssignMode.auto : _AssignMode.manual;
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
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
        notes:
            _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
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
    final serviceAreasAsync = ref.watch(allVendorServiceAreasProvider);
    final allVendors = vendorsAsync.valueOrNull ?? <Vendor>[];

    // Compute ranked candidates synchronously when both providers are ready.
    final candidates =
        (_mode == _AssignMode.auto && _bookingHasLocation &&
                vendorsAsync.hasValue && serviceAreasAsync.hasValue)
            ? VendorAssignmentService.rankEligibleVendors(
                bookingLat: widget.booking.latitude!,
                bookingLng: widget.booking.longitude!,
                vendors: allVendors,
                serviceAreasMap: serviceAreasAsync.valueOrNull ?? {},
              )
            : <VendorCandidate>[];

    final selectedVendor =
        allVendors.where((v) => v.id == _vendorId).firstOrNull;

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
            _buildHeader(),

            // ── Scrollable content ───────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Mode toggle
                      _buildModeSelector(),
                      const SizedBox(height: 20),

                      // Mode panel
                      if (_mode == _AssignMode.auto)
                        _buildAutoPanel(
                          isLoading: vendorsAsync.isLoading ||
                              serviceAreasAsync.isLoading,
                          hasError: vendorsAsync.hasError ||
                              serviceAreasAsync.hasError,
                          candidates: candidates,
                        )
                      else
                        _buildManualPanel(allVendors),

                      const SizedBox(height: 20),

                      // Selected vendor indicator
                      if (selectedVendor != null) ...[
                        _buildSelectedIndicator(selectedVendor),
                        const SizedBox(height: 16),
                      ],

                      // Shared: service date
                      InkWell(
                        onTap: _saving ? null : _pickDate,
                        borderRadius: BorderRadius.circular(8),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Service Date *',
                            prefixIcon:
                                Icon(Icons.calendar_today_rounded),
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

                      // Shared: status
                      DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _status,
                        decoration: const InputDecoration(
                          labelText: 'Status *',
                          prefixIcon: Icon(Icons.flag_rounded),
                        ),
                        items: _statusOptions
                            .map((s) => DropdownMenuItem(
                                  value: s.$1,
                                  child: Text(s.$2),
                                ))
                            .toList(),
                        onChanged: _saving
                            ? null
                            : (v) {
                                if (v != null) setState(() => _status = v);
                              },
                        validator: (v) => v == null ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),

                      // Shared: notes
                      TextFormField(
                        controller: _notesCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          hintText: 'Additional notes',
                          prefixIcon: Icon(Icons.notes_rounded),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                        enabled: !_saving,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Footer ──────────────────────────────────────────────────────
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  // ── Section builders ───────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.assignment_ind_rounded,
              color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Assign Booking #${widget.booking.bookingNumber}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _ModeTab(
            icon: Icons.auto_awesome_rounded,
            label: 'Auto Assign',
            selected: _mode == _AssignMode.auto,
            onTap: _saving
                ? null
                : () => setState(() => _mode = _AssignMode.auto),
          ),
          _ModeTab(
            icon: Icons.edit_rounded,
            label: 'Manual Assign',
            selected: _mode == _AssignMode.manual,
            onTap: _saving
                ? null
                : () => setState(() {
                      _mode = _AssignMode.manual;
                      _autoSelected = false;
                      _autoSelectedDistanceKm = null;
                    }),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoPanel({
    required bool isLoading,
    required bool hasError,
    required List<VendorCandidate> candidates,
  }) {
    if (!_bookingHasLocation) {
      return _InfoBanner(
        icon: Icons.location_off_rounded,
        color: AppColors.error,
        message:
            'This booking has no location data. Auto-assignment requires '
            'booking coordinates. Use manual assignment instead.',
        actionLabel: 'Switch to Manual',
        onAction: () => setState(() => _mode = _AssignMode.manual),
      );
    }

    if (isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (hasError) {
      return _InfoBanner(
        icon: Icons.error_outline_rounded,
        color: AppColors.error,
        message: 'Failed to load vendor data. Try manual assignment.',
        actionLabel: 'Switch to Manual',
        onAction: () => setState(() => _mode = _AssignMode.manual),
      );
    }

    final locRow = Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(Icons.location_on_rounded,
              size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            'Booking: '
            '${widget.booking.latitude!.toStringAsFixed(5)}, '
            '${widget.booking.longitude!.toStringAsFixed(5)}',
            style: TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );

    if (candidates.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          locRow,
          const SizedBox(height: 8),
          _InfoBanner(
            icon: Icons.search_off_rounded,
            color: AppColors.textSecondary,
            message:
                'No active vendors found within any service radius for '
                'this booking location.',
            actionLabel: 'Switch to Manual',
            onAction: () => setState(() => _mode = _AssignMode.manual),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        locRow,
        Text(
          '${candidates.length} eligible vendor'
          '${candidates.length == 1 ? '' : 's'} within service radius',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 12),
        ...candidates.asMap().entries.map(
              (e) => _VendorCandidateCard(
                candidate: e.value,
                isFirst: e.key == 0,
                isSelected: _vendorId == e.value.vendor.id,
                onSelect: _saving
                    ? null
                    : () => setState(() {
                          _vendorId = e.value.vendor.id;
                          _autoSelected = true;
                          _autoSelectedDistanceKm = e.value.distanceKm;
                          if (_status == 'pending') _status = 'assigned';
                        }),
              ),
            ),
      ],
    );
  }

  Widget _buildManualPanel(List<Vendor> vendors) {
    final vendorIds = vendors.map((v) => v.id).toSet();
    final currentKnown = vendorIds.contains(_vendorId);
    // Treat empty string as unselected.
    final dropdownValue =
        (currentKnown && _vendorId.isNotEmpty) ? _vendorId : null;

    return DropdownButtonFormField<String>(
      // ignore: deprecated_member_use
      value: dropdownValue,
      decoration: const InputDecoration(
        labelText: 'Vendor *',
        prefixIcon: Icon(Icons.store_rounded),
      ),
      isExpanded: true,
      items: [
        if (!currentKnown && _vendorId.isNotEmpty)
          DropdownMenuItem(
            value: _vendorId,
            child: Text(
              'Unknown vendor '
              '(${_vendorId.substring(0, min(8, _vendorId.length))}…)',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
        ...vendors.map(
          (v) => DropdownMenuItem(value: v.id, child: Text(v.businessName)),
        ),
      ],
      onChanged: _saving
          ? null
          : (v) {
              if (v != null) {
                setState(() {
                  _vendorId = v;
                  _autoSelected = false;
                  _autoSelectedDistanceKm = null;
                });
              }
            },
      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
    );
  }

  Widget _buildSelectedIndicator(Vendor vendor) {
    final annotation = (_autoSelected && _autoSelectedDistanceKm != null)
        ? 'auto — ${_autoSelectedDistanceKm!.toStringAsFixed(1)} km away'
        : 'manual';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded,
              size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: vendor.businessName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  TextSpan(
                    text: '  ·  $annotation',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppColors.primary.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
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
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Confirm Assignment'),
          ),
        ],
      ),
    );
  }
}

// ── Private widgets ────────────────────────────────────────────────────────────

class _ModeTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _ModeTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.all(3),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color:
                      selected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textPrimary),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: onAction,
                    child: Text(
                      actionLabel!,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.accent,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VendorCandidateCard extends StatelessWidget {
  final VendorCandidate candidate;
  final bool isFirst;
  final bool isSelected;
  final VoidCallback? onSelect;

  const _VendorCandidateCard({
    required this.candidate,
    required this.isFirst,
    required this.isSelected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final vendor = candidate.vendor;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primaryLight : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? AppColors.primary : AppColors.border,
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: [NEAREST chip?] + name + distance badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (isFirst) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3CD),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: const Color(0xFFD69E2E), width: 0.8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_rounded,
                          size: 10, color: Color(0xFFD69E2E)),
                      SizedBox(width: 3),
                      Text(
                        'NEAREST',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFD69E2E),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  vendor.businessName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Distance badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.4)
                        : AppColors.border,
                  ),
                ),
                child: Text(
                  '${candidate.distanceKm.toStringAsFixed(1)} km',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Detail row: rating · active status · radius
          Row(
            children: [
              // Rating
              if (vendor.rating != null) ...[
                const Icon(Icons.star_rounded,
                    size: 13, color: Color(0xFFD69E2E)),
                const SizedBox(width: 3),
                Text(
                  vendor.rating!.toStringAsFixed(1),
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textPrimary),
                ),
              ] else
                Text(
                  'No rating',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              const SizedBox(width: 12),

              // Active status dot
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: vendor.isActive
                      ? AppColors.success
                      : AppColors.error,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                vendor.isActive ? 'Active' : 'Inactive',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 12),

              // Effective radius
              Icon(Icons.radar_rounded,
                  size: 13, color: AppColors.textSecondary),
              const SizedBox(width: 3),
              Text(
                'radius ${candidate.effectiveRadiusKm.toStringAsFixed(1)} km',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Select / Selected indicator
          Align(
            alignment: Alignment.centerRight,
            child: isSelected
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        'Selected',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  )
                : FilledButton(
                    onPressed: onSelect,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 7),
                      minimumSize: Size.zero,
                      tapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    child: const Text('Select'),
                  ),
          ),
        ],
      ),
    );
  }
}
