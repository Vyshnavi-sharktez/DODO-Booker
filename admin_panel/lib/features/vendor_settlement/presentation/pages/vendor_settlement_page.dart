import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/clickable.dart';
import '../../application/providers/vendor_settlement_providers.dart';
import '../../domain/models/vendor_earnings_summary.dart';
import '../widgets/settlement_create_dialog.dart';
import '../widgets/settlement_history_dialog.dart';

enum _SettlementFilter { all, pendingPayment, settled, noEarnings }

class VendorSettlementPage extends ConsumerStatefulWidget {
  const VendorSettlementPage({super.key});

  @override
  ConsumerState<VendorSettlementPage> createState() =>
      _VendorSettlementPageState();
}

class _VendorSettlementPageState extends ConsumerState<VendorSettlementPage> {
  final _searchCtrl = TextEditingController();
  _SettlementFilter _filter = _SettlementFilter.all;

  static final _moneyFmt = NumberFormat('#,##0.00', 'en_IN');

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<VendorEarningsSummary> _applyFilters(
      List<VendorEarningsSummary> summaries) {
    final query = _searchCtrl.text.trim().toLowerCase();
    return summaries.where((s) {
      final matchesSearch = query.isEmpty ||
          s.vendorName.toLowerCase().contains(query) ||
          (s.ownerName?.toLowerCase().contains(query) ?? false);

      final matchesFilter = switch (_filter) {
        _SettlementFilter.all => true,
        _SettlementFilter.pendingPayment =>
          s.settlementStatus == SettlementStatus.pendingPayment,
        _SettlementFilter.settled =>
          s.settlementStatus == SettlementStatus.settled,
        _SettlementFilter.noEarnings =>
          s.settlementStatus == SettlementStatus.noEarnings,
      };

      return matchesSearch && matchesFilter;
    }).toList();
  }

  Future<void> _openSettleDialog(VendorEarningsSummary summary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => SettlementCreateDialog(summary: summary),
    );
    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Settlement recorded for ${summary.vendorName}'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  void _openHistoryDialog(VendorEarningsSummary summary) {
    showDialog<void>(
      context: context,
      builder: (_) => SettlementHistoryDialog(
        vendorId: summary.vendorId,
        vendorName: summary.vendorName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summariesAsync = ref.watch(vendorSettlementNotifierProvider);
    final totalPending = ref.watch(totalPendingSettlementProvider);
    final awaitingCount = ref.watch(vendorsAwaitingPaymentCountProvider);
    final monthStatsAsync = ref.watch(thisMonthSettlementStatsProvider);

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Stats ──────────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Total Pending Settlement',
                  value: '₹${_moneyFmt.format(totalPending)}',
                  icon: Icons.pending_actions_rounded,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _StatCard(
                  label: 'Vendors Awaiting Payment',
                  value: awaitingCount.toString(),
                  icon: Icons.store_rounded,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: monthStatsAsync.when(
                  loading: () => const _StatCard(
                    label: 'Settled This Month',
                    value: '…',
                    icon: Icons.payments_rounded,
                    color: AppColors.success,
                  ),
                  error: (_, __) => const _StatCard(
                    label: 'Settled This Month',
                    value: '—',
                    icon: Icons.payments_rounded,
                    color: AppColors.success,
                  ),
                  data: (stats) => _StatCard(
                    label: 'Settled This Month',
                    value: '₹${_moneyFmt.format(stats.$1)}',
                    icon: Icons.payments_rounded,
                    color: AppColors.success,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: monthStatsAsync.when(
                  loading: () => const _StatCard(
                    label: 'Settlements This Month',
                    value: '…',
                    icon: Icons.receipt_long_rounded,
                    color: AppColors.primary,
                  ),
                  error: (_, __) => const _StatCard(
                    label: 'Settlements This Month',
                    value: '—',
                    icon: Icons.receipt_long_rounded,
                    color: AppColors.primary,
                  ),
                  data: (stats) => _StatCard(
                    label: 'Settlements This Month',
                    value: stats.$2.toString(),
                    icon: Icons.receipt_long_rounded,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Vendor Settlements Table ───────────────────────────────────────
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                    child: Row(
                      children: [
                        const Text(
                          'Vendor Settlements',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        SizedBox(
                          width: 220,
                          height: 36,
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: 'Search vendor…',
                              prefixIcon: const Icon(Icons.search, size: 18),
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 0),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    const BorderSide(color: AppColors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    const BorderSide(color: AppColors.border),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _FilterChip(
                          label: 'All',
                          selected: _filter == _SettlementFilter.all,
                          onTap: () =>
                              setState(() => _filter = _SettlementFilter.all),
                        ),
                        const SizedBox(width: 6),
                        _FilterChip(
                          label: 'Pending',
                          selected:
                              _filter == _SettlementFilter.pendingPayment,
                          onTap: () => setState(
                              () => _filter = _SettlementFilter.pendingPayment),
                        ),
                        const SizedBox(width: 6),
                        _FilterChip(
                          label: 'Settled',
                          selected: _filter == _SettlementFilter.settled,
                          onTap: () => setState(
                              () => _filter = _SettlementFilter.settled),
                        ),
                        const SizedBox(width: 6),
                        _FilterChip(
                          label: 'No Earnings',
                          selected: _filter == _SettlementFilter.noEarnings,
                          onTap: () => setState(
                              () => _filter = _SettlementFilter.noEarnings),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          tooltip: 'Refresh',
                          onPressed: () => ref
                              .read(vendorSettlementNotifierProvider.notifier)
                              .refresh(),
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.border),

                  Expanded(
                    child: summariesAsync.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      error: (e, _) => Center(
                        child: Text(
                          'Error loading data: $e',
                          style: const TextStyle(color: AppColors.error),
                        ),
                      ),
                      data: (summaries) {
                        final filtered = _applyFilters(summaries);
                        if (filtered.isEmpty) {
                          return const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.payments_outlined,
                                  size: 40,
                                  color: AppColors.border,
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'No vendors found',
                                  style: TextStyle(
                                      color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          );
                        }
                        return _VendorTable(
                          summaries: filtered,
                          onSettle: _openSettleDialog,
                          onHistory: _openHistoryDialog,
                        );
                      },
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
}

// ── Vendor Table ───────────────────────────────────────────────────────────────

class _VendorTable extends StatelessWidget {
  const _VendorTable({
    required this.summaries,
    required this.onSettle,
    required this.onHistory,
  });
  final List<VendorEarningsSummary> summaries;
  final void Function(VendorEarningsSummary) onSettle;
  final void Function(VendorEarningsSummary) onHistory;

  static final _fmt = NumberFormat('#,##0.00', 'en_IN');
  static final _dateFmt = DateFormat('dd MMM yyyy');

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: MediaQuery.of(context).size.width - 112,
          ),
          child: Table(
            columnWidths: const {
              0: FlexColumnWidth(3),
              1: FlexColumnWidth(1.5),
              2: FlexColumnWidth(2),
              3: FlexColumnWidth(2),
              4: FlexColumnWidth(1.6),
              5: FlexColumnWidth(2),
            },
            children: [
              const TableRow(
                decoration: BoxDecoration(color: AppColors.background),
                children: [
                  _TableHeader('Vendor'),
                  _TableHeader('Completed Jobs'),
                  _TableHeader('Pending Settlement'),
                  _TableHeader('Last Settlement'),
                  _TableHeader('Status'),
                  _TableHeader('Actions'),
                ],
              ),
              for (final s in summaries)
                TableRow(
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom:
                          BorderSide(color: AppColors.border, width: 0.5),
                    ),
                  ),
                  children: [
                    // Vendor
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            s.vendorName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (s.ownerName?.isNotEmpty == true)
                            Text(
                              s.ownerName!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          if (!s.isActive)
                            Text(
                              'Inactive',
                              style: TextStyle(
                                fontSize: 10,
                                color:
                                    AppColors.error.withValues(alpha: 0.8),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Completed Jobs
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Text(
                        s.completedJobs.toString(),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    // Pending Settlement
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Text(
                        '₹${_fmt.format(s.pendingSettlement)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: s.pendingSettlement > 0
                              ? AppColors.warning
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    // Last Settlement
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Text(
                        s.lastSettlementAt != null
                            ? _dateFmt.format(s.lastSettlementAt!)
                            : '—',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    // Status badge
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: _StatusBadge(status: s.settlementStatus),
                    ),
                    // Actions
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ActionButton(
                            label: 'Settle',
                            icon: Icons.payments_rounded,
                            color: AppColors.success,
                            enabled: s.pendingSettlement > 0,
                            onTap: () => onSettle(s),
                          ),
                          const SizedBox(width: 8),
                          _ActionButton(
                            label: 'History',
                            icon: Icons.history_rounded,
                            color: AppColors.primary,
                            enabled: true,
                            onTap: () => onHistory(s),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Stats card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Status badge ───────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final SettlementStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      SettlementStatus.noEarnings => ('No Earnings', AppColors.textSecondary),
      SettlementStatus.settled => ('Settled', AppColors.success),
      SettlementStatus.pendingPayment => ('Pending Payment', AppColors.warning),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ── Table helpers ──────────────────────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  const _TableHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        widget.enabled ? widget.color : AppColors.textSecondary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.forbidden,
      child: Clickable(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _hovered && widget.enabled
                ? effectiveColor.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: effectiveColor.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: effectiveColor),
              const SizedBox(width: 5),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: effectiveColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Filter chip ────────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Clickable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
