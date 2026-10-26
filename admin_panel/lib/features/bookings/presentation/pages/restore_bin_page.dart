import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/restore_bin_providers.dart';
import '../../domain/models/booking.dart';
import '../../domain/models/deleted_booking.dart';
import '../widgets/booking_details_dialog.dart';

// ── Page ──────────────────────────────────────────────────────────────────────

class RestoreBinPage extends ConsumerWidget {
  const RestoreBinPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Scaffold(
      backgroundColor: Color(0xFFF7F8FC),
      body: _RestoreBinBody(),
    );
  }
}

class _RestoreBinBody extends ConsumerStatefulWidget {
  const _RestoreBinBody();

  @override
  ConsumerState<_RestoreBinBody> createState() => _RestoreBinBodyState();
}

class _RestoreBinBodyState extends ConsumerState<_RestoreBinBody> {
  String _search = '';
  int _selectedTab = 0; // 0 = Eligible, 1 = Expired

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(deletedBookingsNotifierProvider);
    final retentionAsync = ref.watch(retentionSettingsProvider);

    final retention = retentionAsync.valueOrNull ?? (value: 30, unit: 'days');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(bookingsAsync),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _RetentionCard(
                initialValue: retention.value,
                initialUnit: retention.unit,
                onSaved: () => ref.invalidate(retentionSettingsProvider),
              ),
              const SizedBox(height: 20),
              _buildTabs(bookingsAsync, retention),
              const SizedBox(height: 12),
              _buildSearchBar(),
              const SizedBox(height: 16),
              _buildTable(bookingsAsync, retention),
            ],
          ),
        ),
      ],
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  Widget _buildHeader(AsyncValue<List<DeletedBooking>> bookingsAsync) {
    final count = bookingsAsync.valueOrNull?.length ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.restore_from_trash_rounded,
                          color: AppColors.error, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Restore Bin',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A202C),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  bookingsAsync.isLoading
                      ? 'Loading…'
                      : '$count deleted booking${count == 1 ? '' : 's'} in restore bin',
                  style: const TextStyle(color: Color(0xFF718096), fontSize: 13),
                ),
              ],
            ),
          ),
          _PurgeButton(),
        ],
      ),
    );
  }

  // ── Search bar ──────────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return SizedBox(
      height: 40,
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search by booking number, customer name, or phone…',
          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFA0AEC0)),
          prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFFA0AEC0)),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
        onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
      ),
    );
  }

  // ── Tab bar ─────────────────────────────────────────────────────────────────

  Widget _buildTabs(
    AsyncValue<List<DeletedBooking>> bookingsAsync,
    ({int value, String unit}) retention,
  ) {
    final all = bookingsAsync.valueOrNull ?? [];
    int eligibleCount = 0;
    int expiredCount = 0;
    for (final b in all) {
      if (b.isExpired(
        retentionValue: retention.value,
        retentionUnit: retention.unit,
      )) {
        expiredCount++;
      } else {
        eligibleCount++;
      }
    }
    return Row(
      children: [
        _TabChip(
          label: 'Eligible',
          count: eligibleCount,
          selected: _selectedTab == 0,
          onTap: () => setState(() => _selectedTab = 0),
        ),
        const SizedBox(width: 8),
        _TabChip(
          label: 'Expired',
          count: expiredCount,
          selected: _selectedTab == 1,
          isExpired: true,
          onTap: () => setState(() => _selectedTab = 1),
        ),
      ],
    );
  }

  // ── Table ───────────────────────────────────────────────────────────────────

  Widget _buildTable(
    AsyncValue<List<DeletedBooking>> bookingsAsync,
    ({int value, String unit}) retention,
  ) {
    if (bookingsAsync.isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 64),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (bookingsAsync.hasError) {
      return _ErrorCard(
        message: bookingsAsync.error.toString(),
        onRetry: () => ref
            .read(deletedBookingsNotifierProvider.notifier)
            .refresh(),
      );
    }

    final all = bookingsAsync.valueOrNull ?? [];

    final tabFiltered = _selectedTab == 0
        ? all
            .where((b) => !b.isExpired(
                  retentionValue: retention.value,
                  retentionUnit: retention.unit,
                ))
            .toList()
        : all
            .where((b) => b.isExpired(
                  retentionValue: retention.value,
                  retentionUnit: retention.unit,
                ))
            .toList();

    final filtered = _search.isEmpty
        ? tabFiltered
        : tabFiltered.where((b) {
            return b.bookingNumber.toLowerCase().contains(_search) ||
                (b.customerName?.toLowerCase().contains(_search) ?? false) ||
                (b.customerPhone?.toLowerCase().contains(_search) ?? false);
          }).toList();

    if (filtered.isEmpty) {
      return _EmptyState(isFiltered: _search.isNotEmpty);
    }

    return _BinTable(
      bookings: filtered,
      retentionValue: retention.value,
      retentionUnit: retention.unit,
    );
  }
}

// ── Retention configuration card ─────────────────────────────────────────────

class _RetentionCard extends ConsumerStatefulWidget {
  final int initialValue;
  final String initialUnit;
  final VoidCallback onSaved;

  const _RetentionCard({
    required this.initialValue,
    required this.initialUnit,
    required this.onSaved,
  });

  @override
  ConsumerState<_RetentionCard> createState() => _RetentionCardState();
}

class _RetentionCardState extends ConsumerState<_RetentionCard> {
  late final TextEditingController _ctrl;
  late String _unit;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue.toString());
    _unit = widget.initialUnit;
  }

  @override
  void didUpdateWidget(_RetentionCard old) {
    super.didUpdateWidget(old);
    if (old.initialValue != widget.initialValue) {
      _ctrl.text = widget.initialValue.toString();
    }
    if (old.initialUnit != widget.initialUnit) {
      _unit = widget.initialUnit;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final raw = int.tryParse(_ctrl.text.trim());
    if (raw == null || raw < 1) {
      setState(() => _error = 'Enter a number greater than 0');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ref
          .read(restoreBinRepositoryProvider)
          .saveRetentionSettings(raw, _unit);
      widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Retention period saved')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timer_outlined, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text(
                'Retention Policy',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A202C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Deleted bookings are permanently removed from the restore bin after this period. '
            'Changing the period does not reset existing deletion dates.',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF718096)),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Auto-delete after',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF4A5568),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _ctrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                    errorText: _error != null ? '' : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 38,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _unit,
                    isDense: true,
                    items: const [
                      DropdownMenuItem(value: 'days',   child: Text('Days')),
                      DropdownMenuItem(value: 'weeks',  child: Text('Weeks')),
                      DropdownMenuItem(value: 'months', child: Text('Months')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _unit = v);
                    },
                    style: const TextStyle(fontSize: 13, color: Color(0xFF2D3748)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 38,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white,
                          ),
                        )
                      : const Text('Save'),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: TextStyle(color: AppColors.error, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

// ── Purge expired button ──────────────────────────────────────────────────────

class _PurgeButton extends ConsumerStatefulWidget {
  @override
  ConsumerState<_PurgeButton> createState() => _PurgeButtonState();
}

class _PurgeButtonState extends ConsumerState<_PurgeButton> {
  bool _loading = false;

  Future<void> _purge() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Purge Expired Records?'),
        content: const Text(
          'Permanently delete all bookings in the restore bin that have exceeded '
          'the configured retention period. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Purge'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);
    try {
      final result = await ref
          .read(deletedBookingsNotifierProvider.notifier)
          .purgeExpired();
      final count = result['purged_count'] as int? ?? 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              count == 0
                  ? 'No expired records found'
                  : '$count expired booking${count == 1 ? '' : 's'} permanently deleted',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Purge failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _loading ? null : _purge,
      icon: _loading
          ? const SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.delete_sweep_rounded, size: 16),
      label: const Text('Purge Expired'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.error,
        side: BorderSide(color: AppColors.error.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        textStyle: const TextStyle(fontSize: 13),
      ),
    );
  }
}

// ── Main table ────────────────────────────────────────────────────────────────

class _BinTable extends StatelessWidget {
  final List<DeletedBooking> bookings;
  final int retentionValue;
  final String retentionUnit;

  const _BinTable({
    required this.bookings,
    required this.retentionValue,
    required this.retentionUnit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Table header
          _TableHeader(),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          // Rows
          ...bookings.map(
            (b) => _BookingRow(
              booking: b,
              retentionValue: retentionValue,
              retentionUnit: retentionUnit,
            ),
          ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: const [
          _HeaderCell('Booking #', flex: 2),
          _HeaderCell('Customer', flex: 3),
          _HeaderCell('Services', flex: 3),
          _HeaderCell('Status', flex: 2),
          _HeaderCell('Deleted', flex: 3),
          _HeaderCell('Expires', flex: 3),
          _HeaderCell('', flex: 3),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  final int flex;

  const _HeaderCell(this.label, {required this.flex});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: Color(0xFF718096),
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ── Individual booking row ────────────────────────────────────────────────────

class _BookingRow extends ConsumerStatefulWidget {
  final DeletedBooking booking;
  final int retentionValue;
  final String retentionUnit;

  const _BookingRow({
    required this.booking,
    required this.retentionValue,
    required this.retentionUnit,
  });

  @override
  ConsumerState<_BookingRow> createState() => _BookingRowState();
}

class _BookingRowState extends ConsumerState<_BookingRow> {
  bool _restoring = false;
  bool _viewing = false;
  bool _deleting = false;

  Future<void> _openView() async {
    setState(() => _viewing = true);
    try {
      final Booking booking = await ref
          .read(restoreBinRepositoryProvider)
          .fetchDeletedBookingDetail(widget.booking.bookingId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => BookingDetailsDialog(
          booking: booking,
          allowAssign: false,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load booking details: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _viewing = false);
    }
  }

  Future<void> _confirmRestore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore Booking?'),
        content: Text(
          'Restore booking #${widget.booking.bookingNumber} back to the '
          'active Bookings page?\n\n'
          'The booking will return with its original status and all '
          'available data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _restoring = true);
    try {
      final bookingNumber = await ref
          .read(deletedBookingsNotifierProvider.notifier)
          .restore(widget.booking.bookingId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Booking #$bookingNumber restored successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _restoring = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restore failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _confirmPermanentDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Permanently Delete?'),
        content: Text(
          'Permanently delete booking #${widget.booking.bookingNumber} from the '
          'restore bin?\n\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete Forever'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      final bookingNumber = await ref
          .read(deletedBookingsNotifierProvider.notifier)
          .permanentlyDelete(widget.booking.bookingId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Booking #$bookingNumber permanently deleted'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    final expired = b.isExpired(
      retentionValue: widget.retentionValue,
      retentionUnit: widget.retentionUnit,
    );
    final expiresAt = b.expiresAt(
      retentionValue: widget.retentionValue,
      retentionUnit: widget.retentionUnit,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              // Booking number
              Expanded(
                flex: 2,
                child: Text(
                  b.bookingNumber.isNotEmpty ? b.bookingNumber : '—',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2D3748),
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              // Customer
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.displayName,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF2D3748)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (b.customerPhone?.isNotEmpty == true)
                      Text(
                        b.customerPhone!,
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF718096)),
                      ),
                  ],
                ),
              ),
              // Services
              Expanded(
                flex: 3,
                child: Text(
                  b.serviceSummary,
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF4A5568)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Original status badge
              Expanded(
                flex: 2,
                child: _StatusBadge(status: b.status ?? ''),
              ),
              // Deleted at
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('dd MMM yyyy').format(b.deletedAt.toLocal()),
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF4A5568)),
                    ),
                    Text(
                      DateFormat('HH:mm').format(b.deletedAt.toLocal()),
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF718096)),
                    ),
                    if (b.deletedByName?.isNotEmpty == true)
                      Text(
                        'by ${b.deletedByName}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFFA0AEC0)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              // Expires at
              Expanded(
                flex: 3,
                child: expired
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Expired ${_timeAgo(expiresAt)}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.error,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('dd MMM yyyy').format(expiresAt.toLocal()),
                            style: const TextStyle(
                                fontSize: 12.5, color: Color(0xFF4A5568)),
                          ),
                          Text(
                            _timeRemaining(expiresAt),
                            style: const TextStyle(
                                fontSize: 11.5, color: Color(0xFF38A169)),
                          ),
                        ],
                      ),
              ),
              // Actions: View + Restore (or pending-deletion for expired)
              Expanded(
                flex: 3,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // View button
                    _viewing
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(Icons.visibility_outlined, size: 17),
                            onPressed: _openView,
                            tooltip: 'View details',
                            style: IconButton.styleFrom(
                              foregroundColor: const Color(0xFF4A5568),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                    const SizedBox(width: 4),
                    // Restore / pending-deletion
                    if (expired)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.hourglass_empty_rounded,
                                size: 11, color: Color(0xFF9CA3AF)),
                            SizedBox(width: 4),
                            Text(
                              'Pending deletion',
                              style: TextStyle(
                                  fontSize: 11, color: Color(0xFF9CA3AF)),
                            ),
                          ],
                        ),
                      )
                    else if (_restoring)
                      const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      OutlinedButton.icon(
                        onPressed: _confirmRestore,
                        icon: const Icon(Icons.restore_rounded, size: 14),
                        label: const Text('Restore'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: BorderSide(
                              color: AppColors.primary.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                    const SizedBox(width: 4),
                    // Permanent delete
                    _deleting
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : IconButton(
                            icon: const Icon(Icons.delete_forever_rounded,
                                size: 17),
                            onPressed: _confirmPermanentDelete,
                            tooltip: 'Delete permanently',
                            style: IconButton.styleFrom(
                              foregroundColor: AppColors.error,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFF0F4F8)),
      ],
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return '${diff.inMinutes}m ago';
  }

  String _timeRemaining(DateTime dt) {
    final diff = dt.difference(DateTime.now());
    if (diff.inDays > 0) return '${diff.inDays}d remaining';
    if (diff.inHours > 0) return '${diff.inHours}h remaining';
    return '${diff.inMinutes}m remaining';
  }
}

// ── Status badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = _resolve(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  static (String, Color, Color) _resolve(String s) {
    return switch (s) {
      'completed'     => ('Completed', const Color(0xFFD1FAE5), const Color(0xFF065F46)),
      'cancelled'     => ('Cancelled', const Color(0xFFFEE2E2), const Color(0xFF991B1B)),
      'in_progress'   => ('In Progress', const Color(0xFFDBEAFE), const Color(0xFF1E40AF)),
      'assigned' ||
      'assigned_to_dodo_team' => ('Assigned', const Color(0xFFE0E7FF), const Color(0xFF3730A3)),
      'pending'       => ('Pending', const Color(0xFFFEF3C7), const Color(0xFF92400E)),
      'accepted'      => ('Accepted', const Color(0xFFD1FAE5), const Color(0xFF065F46)),
      'payment_failed'=> ('Payment Failed', const Color(0xFFFEE2E2), const Color(0xFF991B1B)),
      _               => (
          s.replaceAll('_', ' ').split(' ')
           .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
           .join(' '),
          const Color(0xFFF3F4F6),
          const Color(0xFF6B7280),
        ),
    };
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool isFiltered;

  const _EmptyState({required this.isFiltered});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 64),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(
            isFiltered ? Icons.search_off_rounded : Icons.delete_outline_rounded,
            size: 48,
            color: const Color(0xFFCBD5E0),
          ),
          const SizedBox(height: 12),
          Text(
            isFiltered ? 'No bookings match your search' : 'Restore bin is empty',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Color(0xFF718096),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isFiltered
                ? 'Try a different search term'
                : 'Deleted bookings will appear here for the configured retention period',
            style: const TextStyle(fontSize: 13, color: Color(0xFFA0AEC0)),
          ),
        ],
      ),
    );
  }
}

// ── Tab chip ──────────────────────────────────────────────────────────────────

class _TabChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final bool isExpired;

  const _TabChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.isExpired = false,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = isExpired ? AppColors.error : AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? activeColor.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? activeColor : const Color(0xFFE2E8F0),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? activeColor : const Color(0xFF4A5568),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: selected ? activeColor : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : const Color(0xFF718096),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error card ────────────────────────────────────────────────────────────────

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Failed to load restore bin: $message',
              style: TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
