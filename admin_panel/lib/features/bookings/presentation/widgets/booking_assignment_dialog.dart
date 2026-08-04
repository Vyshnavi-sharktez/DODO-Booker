import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/clickable.dart';
import '../../../dodo_teams/application/providers/dodo_teams_providers.dart';
import '../../../dodo_teams/domain/models/dodo_team.dart';
import '../../../settings/application/providers/settings_providers.dart';
import '../../../vendor_serving_areas/application/providers/vendor_serving_areas_providers.dart';
import '../../../vendor_serving_areas/domain/models/vendor_serving_area.dart';
import '../../../vendors/application/providers/vendors_providers.dart';
import '../../../vendors/domain/models/vendor.dart';
import '../../../notifications/application/providers/notifications_providers.dart';
import '../../domain/models/booking.dart';
import '../../domain/services/vendor_assignment_service.dart';

final _dateFmt = DateFormat('dd MMM yyyy');
final _isoDateFmt = DateFormat('yyyy-MM-dd');

// Booking statuses that mean the vendor has committed to a job and cannot
// take another on the same date.
//
// 'assigned' is intentionally excluded: it means the admin offered the
// booking but the vendor has not yet accepted — the vendor is not actively
// working and is still available for other assignments.
//
// Must stay in sync with get_vendor_busy_status RPC (supabase/migrations).
const _kBusyStatuses = ['accepted', 'in_progress', 'awaiting_verification'];


/// For AMC bookings: returns (vendorId, vendorName, completedDate) for the
/// vendor who completed the most recent visit under the given contract.
/// Returns null when there are no completed visits or the contract ID is null.
final _amcLastVendorProvider = FutureProvider.autoDispose
    .family<({String vendorId, DateTime? completedAt})?, String>((ref, contractId) async {
  if (contractId.isEmpty) return null;
  final rows = await Supabase.instance.client
      .from('bookings')
      .select('vendor_id, otp_verified_at')
      .eq('amc_contract_id', contractId)
      .eq('status', 'completed')
      .not('vendor_id', 'is', null)
      .order('otp_verified_at', ascending: false)
      .limit(1);
  if ((rows as List).isEmpty) return null;
  final row = rows.first as Map<String, dynamic>;
  final vid = row['vendor_id'] as String?;
  if (vid == null || vid.isEmpty) return null;
  return (
    vendorId: vid,
    completedAt: row['otp_verified_at'] != null
        ? DateTime.tryParse(row['otp_verified_at'] as String)
        : null,
  );
});

/// Single-query busy check: returns the set of vendor IDs that already have a
/// committed booking on the given service date.
/// Keyed as '$dateISO|$excludeBookingId' so the family auto-refreshes when
/// the date picker changes without an extra query per vendor.
final _vendorBusyProvider = FutureProvider.autoDispose
    .family<Set<String>, String>((ref, params) async {
  final pipe = params.indexOf('|');
  final date = params.substring(0, pipe);
  final excludeId = params.substring(pipe + 1);
  final rows = await Supabase.instance.client
      .from('bookings')
      .select('vendor_id')
      .eq('service_date', date)
      .inFilter('status', _kBusyStatuses)
      .neq('id', excludeId);
  return {
    for (final r in rows as List)
      if (r['vendor_id'] != null) r['vendor_id'] as String,
  };
});

/// Single-query COD subscription check: returns the set of vendor IDs that
/// currently have an active, non-expired subscription. Only watched when the
/// booking payment_method is 'cod' and subscription enforcement is active.
final _vendorSubscribedProvider =
    FutureProvider.autoDispose<Set<String>>((ref) async {
  final rows = await Supabase.instance.client
      .from('vendor_subscriptions')
      .select('vendor_id')
      .eq('status', 'active')
      .gt('expiry_date', DateTime.now().toIso8601String());
  return {for (final r in rows as List) r['vendor_id'] as String};
});

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
  final DateTime? preferredDate;

  const BookingAssignmentDialog({
    super.key,
    required this.booking,
    required this.onSave,
    this.preferredDate,
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
  bool _isDefaultDate = false;
  DateTime? _preferredDate;
  bool _saving = false;
  bool _showAllVendors = false;
  bool _showAllTeams = false;

  // Wallet error inline state — populated when the DB rejects an assignment
  // because the selected vendor's balance is below the global minimum.
  String? _walletErrVendorId;
  double? _walletErrBalance;
  double? _walletErrMinimum;

  bool get _bookingHasAddress =>
      widget.booking.address != null &&
      widget.booking.address!.trim().isNotEmpty;

  bool get _bookingHasCoordinates =>
      widget.booking.latitude != null && widget.booking.longitude != null;

  @override
  void initState() {
    super.initState();
    _notesCtrl = TextEditingController(text: widget.booking.notes ?? '');
    _vendorId = widget.booking.vendorId;
    _dodoTeamId = widget.booking.dodoTeamId;
    _serviceDate = widget.booking.serviceDate;
    _preferredDate = widget.preferredDate;
    _assigneeType = switch (widget.booking.assignmentType) {
      'DODO Team' => _AssigneeType.team,
      'Unassigned' => _AssigneeType.unassigned,
      _ => _AssigneeType.vendor,
    };

    // For AMC bookings with no service date, pre-populate from the booking's
    // planned_due_date (computed from contract start + service interval).
    if (widget.booking.isAmc && widget.booking.serviceDate == null) {
      final planned = widget.booking.plannedDueDate;
      if (planned != null) {
        _serviceDate = planned;
        _isDefaultDate = true;
      }
    }
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
    if (picked != null) {
      setState(() {
        _serviceDate = picked;
        _isDefaultDate = false;
      });
    }
  }

  void _clearWalletError() {
    _walletErrVendorId = null;
    _walletErrBalance = null;
    _walletErrMinimum = null;
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
        if (e is PostgrestException &&
            e.code == 'P0001' &&
            e.message.toLowerCase().contains('wallet')) {
          // Parse the two numeric amounts embedded in the trigger message:
          // "Vendor wallet balance (X) is below the required minimum (Y)."
          final m = RegExp(r'\((\d+(?:\.\d+)?)\)[^(]*\((\d+(?:\.\d+)?)\)')
              .firstMatch(e.message);
          setState(() {
            _walletErrVendorId = _vendorId;
            _walletErrBalance = double.tryParse(m?.group(1) ?? '');
            _walletErrMinimum = double.tryParse(m?.group(2) ?? '');
          });
        } else {
          final message = switch (e) {
            PostgrestException(:final code) when code == 'P0001' =>
              'This vendor cannot accept COD bookings. '
                  'Ensure they have an active subscription with COD permission.',
            PostgrestException(:final message) => message,
            _ => e.toString().replaceFirst('Exception: ', ''),
          };
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendorsAsync = ref.watch(vendorsNotifierProvider);
    final servingAreasAsync = ref.watch(vendorServingAreasProvider);
    final assignmentsAsync = ref.watch(allVendorAreaAssignmentsProvider);
    final dodoTeamsAsync = ref.watch(dodoTeamsNotifierProvider);

    // One query for the whole date — no per-vendor round trip.
    // Shows Available while loading; updates to Busy once query resolves.
    final busyKey = _serviceDate == null
        ? null
        : '${_isoDateFmt.format(_serviceDate!)}|${widget.booking.id}';
    final busyVendorIds = busyKey == null
        ? const <String>{}
        : ref.watch(_vendorBusyProvider(busyKey)).valueOrNull ??
            const <String>{};

    // COD enforcement: mirror check_vendor_cod_eligibility settings logic.
    // subscription_enabled + subscription_require_active must both be true,
    // and subscription_allow_free_vendors must be false, for any vendor to be
    // blocked. Only active when the booking is COD.
    final settings = ref.watch(settingsNotifierProvider).valueOrNull ?? {};
    final isCodBooking = widget.booking.isCod;
    final codEnforced = isCodBooking &&
        settings['subscription_enabled'] == 'true' &&
        settings['subscription_require_active'] == 'true' &&
        (settings['subscription_allow_free_vendors'] ?? 'true') != 'true';

    // Fetch subscribed vendor IDs only when enforcement is active.
    final subscribedVendorIds = codEnforced
        ? ref.watch(_vendorSubscribedProvider).valueOrNull
        : null;

    final allVendors = vendorsAsync.valueOrNull ?? <Vendor>[];
    final allTeams = dodoTeamsAsync.valueOrNull ?? <DodoTeam>[];

    // Vendors that are active but have no active subscription are ineligible
    // for COD assignment. Empty when enforcement is off or data is still loading.
    final codIneligibleVendorIds = (codEnforced && subscribedVendorIds != null)
        ? allVendors
            .where((v) => v.isActive && !subscribedVendorIds.contains(v.id))
            .map((v) => v.id)
            .toSet()
        : const <String>{};

    final vendorResult = VendorAssignmentService.rankVendorAssigneesByServingAreas(
      bookingLat: widget.booking.latitude,
      bookingLng: widget.booking.longitude,
      vendors: allVendors,
      servingAreas: servingAreasAsync.valueOrNull ?? <VendorServingArea>[],
      assignmentsMap: assignmentsAsync.valueOrNull ?? {},
      busyVendorIds: busyVendorIds,
      codIneligibleVendorIds: codIneligibleVendorIds,
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
                              servingAreasAsync.isLoading ||
                              assignmentsAsync.isLoading,
                          hasError: vendorsAsync.hasError ||
                              servingAreasAsync.hasError ||
                              assignmentsAsync.hasError,
                          allVendors: allVendors,
                          codEnforced: codEnforced,
                          contractId: widget.booking.isAmc
                              ? (widget.booking.amcContractId ?? '')
                              : '',
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

                      if (_assigneeType == _AssigneeType.vendor &&
                          _walletErrVendorId != null &&
                          _walletErrVendorId == _vendorId) ...[
                        const SizedBox(height: 12),
                        _WalletErrorBanner(
                          key: ValueKey(_walletErrVendorId),
                          vendorId: _walletErrVendorId!,
                          vendorName: allVendors
                                  .where((v) => v.id == _walletErrVendorId)
                                  .firstOrNull
                                  ?.businessName ??
                              'Vendor',
                          balance: _walletErrBalance ?? 0,
                          minimum: _walletErrMinimum ?? 0,
                        ),
                      ],

                      const SizedBox(height: 20),

                      InkWell(
                        onTap: _saving ? null : _pickDate,
                        borderRadius: BorderRadius.circular(8),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Service Date *',
                            prefixIcon:
                                const Icon(Icons.calendar_today_rounded),
                            helperText: _isDefaultDate
                                ? 'Default from AMC Schedule'
                                : null,
                            helperStyle: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                            suffixIcon: const Icon(
                                Icons.edit_calendar_rounded,
                                size: 18,
                                color: AppColors.textSecondary),
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
                      if (_preferredDate != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.event_available_rounded,
                                size: 14,
                                color: AppColors.textSecondary),
                            const SizedBox(width: 6),
                            Text(
                              'Customer Preferred Date:  ${_dateFmt.format(_preferredDate!)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (widget.booking.isAmc &&
                          widget.booking.amcQuantity > 1) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.devices_rounded,
                                size: 14, color: AppColors.primary),
                            const SizedBox(width: 6),
                            Text(
                              'AMC covers ${widget.booking.amcQuantity} units',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
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
    bool codEnforced = false,
    String contractId = '',
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

    // ── AMC recommended vendor ─────────────────────────────────────────────
    Widget? amcRecommendedSection;
    if (contractId.isNotEmpty) {
      final lastVendorAsync = ref.watch(_amcLastVendorProvider(contractId));
      final lastVendorData = lastVendorAsync.valueOrNull;
      if (lastVendorData != null) {
        final recVendor = allVendors
            .where((v) => v.id == lastVendorData.vendorId)
            .firstOrNull;
        if (recVendor != null) {
          final completedStr = lastVendorData.completedAt != null
              ? _dateFmt.format(lastVendorData.completedAt!.toLocal())
              : null;
          amcRecommendedSection = _AmcRecommendedVendorCard(
            vendor: recVendor,
            completedAt: completedStr,
            isSelected: _vendorId == recVendor.id,
            onSelect: _saving
                ? null
                : () => setState(() {
                      if (recVendor.id != _walletErrVendorId) _clearWalletError();
                      _vendorId = recVendor.id;
                    }),
          );
        }
      }
    }

    // COD enforcement banner — shown whenever enforcement is active so the
    // admin understands why some vendors are disabled.
    Widget? codBanner = codEnforced
        ? _InfoBanner(
            icon: Icons.credit_card_off_rounded,
            color: const Color(0xFFD69E2E),
            message:
                'COD booking — only vendors with an active subscription can be assigned.',
          )
        : null;

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
          ?codBanner,
          if (codBanner != null) const SizedBox(height: 12),
          ?currentAssigneeNote,
          ?amcRecommendedSection,
          if (amcRecommendedSection != null) const SizedBox(height: 12),
          if (_bookingHasAddress)
            _AddressRow(
              address: widget.booking.address!,
              trailing: _bookingHasCoordinates
                  ? TextButton(
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
                    )
                  : null,
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
              onSelect: (id) => setState(() {
                final next = _vendorId == id ? '' : id;
                if (next != _walletErrVendorId) _clearWalletError();
                _vendorId = next;
              }),
            ),
        ],
      );
    }

    // No coordinates — cannot match serving areas; require explicit action.
    if (!_bookingHasCoordinates) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?codBanner,
          if (codBanner != null) const SizedBox(height: 12),
          ?currentAssigneeNote,
          ?amcRecommendedSection,
          if (amcRecommendedSection != null) const SizedBox(height: 12),
          _InfoBanner(
            icon: Icons.location_off_rounded,
            color: AppColors.textSecondary,
            message:
                'This booking has no location data. '
                'Serving-area filtering is unavailable.',
            actionLabel: 'Show All Vendors',
            onAction: () => setState(() => _showAllVendors = true),
          ),
        ],
      );
    }

    // Booking has coordinates — show vendors assigned to the matching area.
    Widget? addressRow = _bookingHasAddress
        ? _AddressRow(
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
          )
        : null;

    if (result.inArea.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?codBanner,
          if (codBanner != null) const SizedBox(height: 12),
          ?currentAssigneeNote,
          ?amcRecommendedSection,
          if (amcRecommendedSection != null) const SizedBox(height: 12),
          ?addressRow,
          if (addressRow != null) const SizedBox(height: 8),
          _InfoBanner(
            icon: Icons.search_off_rounded,
            color: AppColors.textSecondary,
            message: 'No vendors are assigned to serve this area.',
            actionLabel: 'Show All Vendors',
            onAction: () => setState(() => _showAllVendors = true),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ?codBanner,
        if (codBanner != null) const SizedBox(height: 12),
        ?currentAssigneeNote,
        ?amcRecommendedSection,
        if (amcRecommendedSection != null) const SizedBox(height: 12),
        ?addressRow,
        const SizedBox(height: 4),
        Text(
          '${result.inArea.length} vendor${result.inArea.length == 1 ? '' : 's'} assigned to serve this area',
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
          onSelect: (id) => setState(() {
            if (id != _walletErrVendorId) _clearWalletError();
            _vendorId = id;
          }),
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
            onSelect: (id) => setState(() => _dodoTeamId = _dodoTeamId == id ? '' : id),
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
    return candidates.map((candidate) {
      final isBusy = candidate.status == AssigneeStatus.busy;
      final blocked = _saving || isBusy || candidate.ineligibleForCod;
      return _AssigneeCandidateCard(
        candidate: candidate,
        isSelected: selectedId == candidate.id,
        onSelect: blocked ? null : () => onSelect?.call(candidate.id),
      );
    }).toList();
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
            onPressed: (_saving ||
                    (_assigneeType == _AssigneeType.vendor &&
                        _vendorId.isEmpty))
                ? null
                : _submit,
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

          // ── Meta row (rating · primary status) ───────────────────────────
          // COD ineligibility is the primary status. Busy is shown as a
          // secondary line beneath it when both conditions apply, so the admin
          // sees both reasons the vendor cannot receive this booking.
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
              if (candidate.ineligibleForCod) ...[
                Icon(Icons.credit_card_off_rounded,
                    size: 13, color: AppColors.error),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'No Active Subscription · COD Not Allowed',
                    style: TextStyle(fontSize: 12, color: AppColors.error),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ] else ...[
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
            ],
          ),
          // Secondary busy indicator — only shown when the vendor is also busy,
          // so the admin knows they are blocked for two independent reasons.
          if (candidate.ineligibleForCod &&
              candidate.status == AssigneeStatus.busy) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFFD69E2E),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'Also busy on this date',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),

          // ── Action ────────────────────────────────────────────────────────
          Align(
            alignment: Alignment.centerRight,
            child: isSelected
                ? OutlinedButton.icon(
                    onPressed: onSelect,
                    icon: const Icon(Icons.check_circle_rounded, size: 15),
                    label: const Text('Selected'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 7),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
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
                    child: const Text('Select'),
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

// ── AMC recommended vendor card ────────────────────────────────────────────────

class _AmcRecommendedVendorCard extends StatelessWidget {
  final Vendor vendor;
  final String? completedAt;
  final bool isSelected;
  final VoidCallback? onSelect;

  const _AmcRecommendedVendorCard({
    required this.vendor,
    this.completedAt,
    required this.isSelected,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FFF4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF38A169).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded,
                  size: 13, color: Color(0xFF276749)),
              const SizedBox(width: 5),
              const Text(
                'RECOMMENDED VENDOR',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF276749),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vendor.businessName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Handled previous AMC visit',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                    if (completedAt != null)
                      Text(
                        'Completed: $completedAt',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF276749)),
                      ),
                  ],
                ),
              ),
              isSelected
                  ? OutlinedButton.icon(
                      onPressed: onSelect,
                      icon: const Icon(Icons.check_circle_rounded, size: 14),
                      label: const Text('Selected'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    )
                  : FilledButton(
                      onPressed: onSelect,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF38A169),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      child: const Text('Select'),
                    ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Wallet error banner ────────────────────────────────────────────────────────

enum _NotifyState { idle, sending, sent, error }

class _WalletErrorBanner extends ConsumerStatefulWidget {
  final String vendorId;
  final String vendorName;
  final double balance;
  final double minimum;

  const _WalletErrorBanner({
    super.key,
    required this.vendorId,
    required this.vendorName,
    required this.balance,
    required this.minimum,
  });

  @override
  ConsumerState<_WalletErrorBanner> createState() => _WalletErrorBannerState();
}

class _WalletErrorBannerState extends ConsumerState<_WalletErrorBanner> {
  _NotifyState _notifyState = _NotifyState.idle;

  Future<void> _sendNotification() async {
    setState(() => _notifyState = _NotifyState.sending);
    final fmt =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
    try {
      await ref.read(notificationsRepositoryProvider).createNotification(
            userType: 'vendor',
            userId: widget.vendorId,
            title: 'Wallet Balance Alert',
            message:
                'Your current wallet balance (${fmt.format(widget.balance)}) '
                'is below the required minimum of ${fmt.format(widget.minimum)}. '
                'Please top up your wallet to continue receiving booking assignments.',
            notificationType: 'wallet_low_balance',
            entityType: 'vendor_wallet',
            entityId: widget.vendorId,
          );
      if (mounted) setState(() => _notifyState = _NotifyState.sent);
    } catch (_) {
      if (mounted) setState(() => _notifyState = _NotifyState.error);
    }
  }

  Widget _buildAction() {
    return switch (_notifyState) {
      _NotifyState.sending => const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      _NotifyState.sent => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded,
                size: 14, color: AppColors.success),
            const SizedBox(width: 5),
            const Text(
              'Notification sent',
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.success,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      _NotifyState.idle || _NotifyState.error => Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              onPressed: _sendNotification,
              icon: const Icon(Icons.notifications_rounded, size: 13),
              label: const Text('Notify Vendor'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD69E2E),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
            if (_notifyState == _NotifyState.error) ...[
              const SizedBox(height: 3),
              const Text(
                'Failed to send. Tap to retry.',
                style: TextStyle(fontSize: 10, color: AppColors.error),
              ),
            ],
          ],
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final fmt =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: 15, color: AppColors.error),
              const SizedBox(width: 7),
              Text(
                'Wallet balance too low',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${widget.vendorName} cannot be assigned until the wallet is topped up.',
            style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _BalanceLabel(
                  label: 'Current',
                  value: fmt.format(widget.balance),
                  valueColor: AppColors.error),
              const SizedBox(width: 20),
              _BalanceLabel(
                  label: 'Required',
                  value: fmt.format(widget.minimum),
                  valueColor: AppColors.textSecondary),
              const Spacer(),
              _buildAction(),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalanceLabel extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _BalanceLabel({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: AppColors.textSecondary)),
        Text(value,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor)),
      ],
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
