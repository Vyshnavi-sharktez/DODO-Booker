import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/clickable.dart';
import '../../../dodo_teams/application/providers/dodo_teams_providers.dart';
import '../../../dodo_teams/domain/models/dodo_team.dart';
import '../../../vendors/application/providers/vendor_detail_providers.dart';
import '../../../vendors/application/providers/vendors_providers.dart';
import '../../../vendors/domain/models/vendor.dart';
import '../../domain/models/booking.dart';
import '../../domain/services/vendor_assignment_service.dart';

final _dateFmt = DateFormat('dd MMM yyyy');

enum _AssigneeType { vendor, team, unassigned }

// ── Dialog ─────────────────────────────────────────────────────────────────────

class BookingAssignmentDialog extends ConsumerStatefulWidget {
  final Booking booking;
  final Future<void> Function({
    required String assignmentType,
    String? vendorId,
    String? dodoTeamId,
    required DateTime serviceDate,
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

  late _AssigneeType _assigneeType;
  late String _vendorId;
  late String _dodoTeamId;
  late DateTime? _serviceDate;
  bool _saving = false;
  bool _showAllVendors = false;
  bool _showAllTeams = false;

  bool get _bookingHasAddress =>
      widget.booking.address != null &&
      widget.booking.address!.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _notesCtrl = TextEditingController(text: widget.booking.notes ?? '');
    _vendorId = widget.booking.vendorId;
    _dodoTeamId = widget.booking.dodoTeamId;
    _serviceDate = widget.booking.serviceDate;
    _assigneeType = switch (widget.booking.assignmentType) {
      'DODO Team' => _AssigneeType.team,
      'Unassigned' => _AssigneeType.unassigned,
      _ => _AssigneeType.vendor,
    };
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
    if (_assigneeType == _AssigneeType.vendor && _vendorId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a vendor')),
      );
      return;
    }
    if (_assigneeType == _AssigneeType.team && _dodoTeamId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a DODO Team')),
      );
      return;
    }

    final assignmentType = switch (_assigneeType) {
      _AssigneeType.vendor => 'External Vendor',
      _AssigneeType.team => 'DODO Team',
      _AssigneeType.unassigned => 'Unassigned',
    };

    setState(() => _saving = true);
    try {
      await widget.onSave(
        assignmentType: assignmentType,
        vendorId: _assigneeType == _AssigneeType.vendor ? _vendorId : null,
        dodoTeamId: _assigneeType == _AssigneeType.team ? _dodoTeamId : null,
        serviceDate: _serviceDate!,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
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
    final dodoTeamsAsync = ref.watch(dodoTeamsNotifierProvider);

    final allVendors = vendorsAsync.valueOrNull ?? <Vendor>[];
    final allTeams = dodoTeamsAsync.valueOrNull ?? <DodoTeam>[];

    final vendorResult = VendorAssignmentService.rankVendorAssignees(
      bookingAddress: widget.booking.address,
      vendors: allVendors,
      serviceAreasMap: serviceAreasAsync.valueOrNull ?? {},
    );

    final teamResult = VendorAssignmentService.rankTeamAssignees(
      bookingAddress: widget.booking.address,
      teams: allTeams,
    );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAssigneeTypeSelector(),
                      const SizedBox(height: 20),

                      if (_assigneeType == _AssigneeType.vendor)
                        _buildVendorPanel(
                          result: vendorResult,
                          isLoading: vendorsAsync.isLoading ||
                              serviceAreasAsync.isLoading,
                          hasError: vendorsAsync.hasError ||
                              serviceAreasAsync.hasError,
                          allVendors: allVendors,
                        ),

                      if (_assigneeType == _AssigneeType.team)
                        _buildTeamPanel(
                          result: teamResult,
                          isLoading: dodoTeamsAsync.isLoading,
                          hasError: dodoTeamsAsync.hasError,
                        ),

                      if (_assigneeType == _AssigneeType.unassigned)
                        _InfoBanner(
                          icon: Icons.person_off_rounded,
                          color: AppColors.textSecondary,
                          message:
                              'Saving will clear any existing vendor or team '
                              'assignment and mark the booking as Unassigned.',
                        ),

                      const SizedBox(height: 20),

                      InkWell(
                        onTap: _saving ? null : _pickDate,
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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
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

  Widget _buildAssigneeTypeSelector() {
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
            icon: Icons.store_rounded,
            label: 'External Vendor',
            selected: _assigneeType == _AssigneeType.vendor,
            onTap: _saving
                ? null
                : () => setState(() {
                      _assigneeType = _AssigneeType.vendor;
                      _showAllVendors = false;
                    }),
          ),
          _ModeTab(
            icon: Icons.groups_rounded,
            label: 'DODO Team',
            selected: _assigneeType == _AssigneeType.team,
            onTap: _saving
                ? null
                : () => setState(() {
                      _assigneeType = _AssigneeType.team;
                      _showAllTeams = false;
                    }),
          ),
          _ModeTab(
            icon: Icons.person_off_rounded,
            label: 'Unassigned',
            selected: _assigneeType == _AssigneeType.unassigned,
            onTap: _saving
                ? null
                : () =>
                    setState(() => _assigneeType = _AssigneeType.unassigned),
          ),
        ],
      ),
    );
  }

  Widget _buildVendorPanel({
    required ({List<AssigneeCandidate> inArea, List<AssigneeCandidate> all})
        result,
    required bool isLoading,
    required bool hasError,
    required List<Vendor> allVendors,
  }) {
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
        message: 'Failed to load vendor data. Please try again.',
      );
    }

    // Surface currently-assigned vendor if they are not in the active list
    // (e.g. deactivated after the booking was made).
    final currentInList =
        _vendorId.isEmpty || result.all.any((c) => c.id == _vendorId);
    Widget? currentAssigneeNote;
    if (!currentInList) {
      final existing =
          allVendors.where((v) => v.id == _vendorId).firstOrNull;
      currentAssigneeNote = _CurrentAssigneeBanner(
        name: existing?.businessName ?? 'Unknown vendor',
        inactive: existing?.isActive == false,
      );
    }

    // Admin explicitly requested the full list.
    if (_showAllVendors) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?currentAssigneeNote,
          if (_bookingHasAddress)
            _AddressRow(
              address: widget.booking.address!,
              trailing: TextButton(
                onPressed: _saving
                    ? null
                    : () => setState(() => _showAllVendors = false),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('In-area only'),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'All ${result.all.length} active vendor${result.all.length == 1 ? '' : 's'}',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 10),
          if (result.all.isEmpty)
            _InfoBanner(
              icon: Icons.search_off_rounded,
              color: AppColors.textSecondary,
              message: 'No active vendors available.',
            )
          else
            ..._candidateCards(
              result.all,
              selectedId: _vendorId,
              onSelect: (id) => setState(() => _vendorId = id),
            ),
        ],
      );
    }

    // No booking address — cannot filter by area; require explicit action.
    if (!_bookingHasAddress) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?currentAssigneeNote,
          _InfoBanner(
            icon: Icons.location_off_rounded,
            color: AppColors.textSecondary,
            message:
                'This booking has no address. Location-based filtering '
                'is unavailable.',
            actionLabel: 'Show All Vendors',
            onAction: () => setState(() => _showAllVendors = true),
          ),
        ],
      );
    }

    // Booking has address — show in-area vendors only.
    final addressRow = _AddressRow(
      address: widget.booking.address!,
      trailing: result.inArea.isNotEmpty
          ? TextButton(
              onPressed: _saving
                  ? null
                  : () => setState(() => _showAllVendors = true),
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: Text('Show all (${result.all.length})'),
            )
          : null,
    );

    if (result.inArea.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?currentAssigneeNote,
          addressRow,
          const SizedBox(height: 8),
          _InfoBanner(
            icon: Icons.search_off_rounded,
            color: AppColors.textSecondary,
            message: 'No vendors available in this location.',
            actionLabel: 'Show All Vendors',
            onAction: () => setState(() => _showAllVendors = true),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ?currentAssigneeNote,
        addressRow,
        const SizedBox(height: 4),
        Text(
          '${result.inArea.length} vendor${result.inArea.length == 1 ? '' : 's'} serving this area',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 10),
        ..._candidateCards(
          result.inArea,
          selectedId: _vendorId,
          onSelect: (id) => setState(() => _vendorId = id),
        ),
      ],
    );
  }

  Widget _buildTeamPanel({
    required ({List<AssigneeCandidate> inArea, List<AssigneeCandidate> all})
        result,
    required bool isLoading,
    required bool hasError,
  }) {
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
        message: 'Failed to load DODO Teams.',
      );
    }

    if (result.all.isEmpty) {
      return _InfoBanner(
        icon: Icons.groups_outlined,
        color: AppColors.textSecondary,
        message: 'No active DODO Teams available. Create a team first.',
      );
    }

    // Admin explicitly requested the full list.
    if (_showAllTeams) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_bookingHasAddress)
            _AddressRow(
              address: widget.booking.address!,
              trailing: TextButton(
                onPressed: _saving
                    ? null
                    : () => setState(() => _showAllTeams = false),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('In-area only'),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'All ${result.all.length} active team${result.all.length == 1 ? '' : 's'}',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 10),
          ..._candidateCards(
            result.all,
            selectedId: _dodoTeamId,
            onSelect: (id) => setState(() => _dodoTeamId = id),
          ),
        ],
      );
    }

    // No booking address — require explicit action to list teams.
    if (!_bookingHasAddress) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoBanner(
            icon: Icons.location_off_rounded,
            color: AppColors.textSecondary,
            message:
                'This booking has no address. Location-based filtering '
                'is unavailable.',
            actionLabel: 'Show All Teams',
            onAction: () => setState(() => _showAllTeams = true),
          ),
        ],
      );
    }

    // Booking has address — show in-area teams only.
    final addressRow = _AddressRow(
      address: widget.booking.address!,
      trailing: result.inArea.isNotEmpty
          ? TextButton(
              onPressed: _saving
                  ? null
                  : () => setState(() => _showAllTeams = true),
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: Text('Show all (${result.all.length})'),
            )
          : null,
    );

    if (result.inArea.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          addressRow,
          const SizedBox(height: 8),
          _InfoBanner(
            icon: Icons.search_off_rounded,
            color: AppColors.textSecondary,
            message: 'No teams available in this location.',
            actionLabel: 'Show All Teams',
            onAction: () => setState(() => _showAllTeams = true),
          ),
        ],
      );
    }

    final headerText =
        '${result.inArea.length} team${result.inArea.length == 1 ? '' : 's'} serving this area · sorted by availability';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        addressRow,
        const SizedBox(height: 4),
        Text(
          headerText,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 10),
        ..._candidateCards(
          result.inArea,
          selectedId: _dodoTeamId,
          onSelect: (id) => setState(() => _dodoTeamId = id),
        ),
      ],
    );
  }

  List<Widget> _candidateCards(
    List<AssigneeCandidate> candidates, {
    String? selectedId,
    void Function(String id)? onSelect,
  }) {
    return candidates
        .map((candidate) => _AssigneeCandidateCard(
              candidate: candidate,
              isSelected: selectedId == candidate.id,
              onSelect: _saving ? null : () => onSelect?.call(candidate.id),
            ))
        .toList();
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

// ── Shared card widget ─────────────────────────────────────────────────────────

class _AssigneeCandidateCard extends StatelessWidget {
  final AssigneeCandidate candidate;
  final bool isSelected;
  final VoidCallback? onSelect;

  const _AssigneeCandidateCard({
    required this.candidate,
    required this.isSelected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (candidate.status) {
      AssigneeStatus.available => AppColors.success,
      AssigneeStatus.busy => const Color(0xFFD69E2E),
      AssigneeStatus.offline => AppColors.textSecondary,
    };
    final statusLabel = switch (candidate.status) {
      AssigneeStatus.available => 'Available',
      AssigneeStatus.busy => 'Busy',
      AssigneeStatus.offline => 'Offline',
    };

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
          // ── Name / subtitle row ───────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      candidate.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (candidate.subtitle != null)
                      Text(
                        candidate.subtitle!,
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Meta row (rating · status) ────────────────────────────────────
          Row(
            children: [
              if (candidate.rating != null) ...[
                const Icon(Icons.star_rounded,
                    size: 13, color: Color(0xFFD69E2E)),
                const SizedBox(width: 3),
                Text(
                  candidate.rating!.toStringAsFixed(1),
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textPrimary),
                ),
                const SizedBox(width: 12),
              ] else if (candidate.kind == AssigneeKind.vendor) ...[
                Text(
                  'No rating',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(width: 12),
              ],
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                statusLabel,
                style: TextStyle(fontSize: 12, color: statusColor),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Action ────────────────────────────────────────────────────────
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
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    child: const Text('Assign'),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Address row widget ─────────────────────────────────────────────────────────

class _AddressRow extends StatelessWidget {
  final String address;
  final Widget? trailing;

  const _AddressRow({required this.address, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(Icons.location_on_rounded,
              size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              address,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

// ── Current assignee banner ────────────────────────────────────────────────────

class _CurrentAssigneeBanner extends StatelessWidget {
  final String name;
  final bool inactive;

  const _CurrentAssigneeBanner({required this.name, required this.inactive});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Currently assigned: $name${inactive ? ' (inactive)' : ''}',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared tab widget ──────────────────────────────────────────────────────────

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
      child: Clickable(
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
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Info banner ────────────────────────────────────────────────────────────────

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
                  style:
                      TextStyle(fontSize: 13, color: AppColors.textPrimary),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 8),
                  Clickable(
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
