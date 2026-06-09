import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/vendors/application/providers/vendors_providers.dart';
import '../../../../features/vendors/domain/models/vendor.dart';
import '../../application/providers/vendor_settlement_providers.dart';
import '../../domain/models/vendor_settlement.dart';
import '../widgets/settlement_create_dialog.dart';
import '../widgets/settlement_history_dialog.dart';

enum _WalletFilter { all, withBalance, withoutBalance }

class VendorSettlementPage extends ConsumerStatefulWidget {
  const VendorSettlementPage({super.key});

  @override
  ConsumerState<VendorSettlementPage> createState() =>
      _VendorSettlementPageState();
}

class _VendorSettlementPageState extends ConsumerState<VendorSettlementPage> {
  final _searchCtrl = TextEditingController();
  _WalletFilter _filter = _WalletFilter.all;

  static final _moneyFmt = NumberFormat('#,##0.00', 'en_IN');
  static final _dateFmt = DateFormat('dd MMM yyyy, hh:mm a');

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Vendor> _applyFilters(List<Vendor> vendors) {
    final query = _searchCtrl.text.trim().toLowerCase();
    return vendors.where((v) {
      final matchesSearch = query.isEmpty ||
          v.businessName.toLowerCase().contains(query) ||
          v.city.toLowerCase().contains(query) ||
          (v.ownerName?.toLowerCase().contains(query) ?? false);

      final matchesFilter = switch (_filter) {
        _WalletFilter.all => true,
        _WalletFilter.withBalance => v.walletBalance > 0,
        _WalletFilter.withoutBalance => v.walletBalance <= 0,
      };

      return matchesSearch && matchesFilter;
    }).toList();
  }

  Future<void> _openSettleDialog(Vendor vendor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => SettlementCreateDialog(vendor: vendor),
    );
    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Settlement processed for ${vendor.businessName}',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  void _openHistoryDialog(Vendor vendor) {
    showDialog<void>(
      context: context,
      builder: (_) => SettlementHistoryDialog(
        vendorId: vendor.id,
        vendorName: vendor.businessName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vendorsAsync = ref.watch(vendorsNotifierProvider);
    final totalBalance = ref.watch(totalWalletBalanceProvider);
    final vendorsWithBalance = ref.watch(vendorsWithBalanceCountProvider);
    final totalSettled = ref.watch(totalSettledAmountProvider);
    final sessionHistory = ref.watch(vendorSettlementHistoryProvider);

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Stats ──────────────────────────────────────────────────────────
          _StatsRow(
            totalBalance: totalBalance,
            vendorsWithBalance: vendorsWithBalance,
            totalSettled: totalSettled,
            sessionCount: sessionHistory.length,
          ),
          const SizedBox(height: 24),

          // ── Vendor Wallets Section ─────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Section header + filter bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  child: Row(
                    children: [
                      const Text(
                        'Vendor Wallets',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      // Search
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
                      // Filter chips
                      _FilterChip(
                        label: 'All',
                        selected: _filter == _WalletFilter.all,
                        onTap: () =>
                            setState(() => _filter = _WalletFilter.all),
                      ),
                      const SizedBox(width: 6),
                      _FilterChip(
                        label: 'With Balance',
                        selected: _filter == _WalletFilter.withBalance,
                        onTap: () =>
                            setState(() => _filter = _WalletFilter.withBalance),
                      ),
                      const SizedBox(width: 6),
                      _FilterChip(
                        label: 'Zero Balance',
                        selected: _filter == _WalletFilter.withoutBalance,
                        onTap: () => setState(
                            () => _filter = _WalletFilter.withoutBalance),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),

                // Table
                vendorsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(48),
                    child: Center(
                      child: Text(
                        'Error loading vendors: $e',
                        style:
                            const TextStyle(color: AppColors.error),
                      ),
                    ),
                  ),
                  data: (vendors) {
                    final filtered = _applyFilters(vendors);
                    if (filtered.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.account_balance_wallet_outlined,
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
                        ),
                      );
                    }
                    return _VendorTable(
                      vendors: filtered,
                      onSettle: _openSettleDialog,
                      onHistory: _openHistoryDialog,
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Settlement History Section ─────────────────────────────────────
          _SettlementHistorySection(
            history: sessionHistory,
            moneyFmt: _moneyFmt,
            dateFmt: _dateFmt,
          ),
        ],
      ),
    );
  }
}

// ── Stats Row ──────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.totalBalance,
    required this.vendorsWithBalance,
    required this.totalSettled,
    required this.sessionCount,
  });
  final double totalBalance;
  final int vendorsWithBalance;
  final double totalSettled;
  final int sessionCount;

  static final _fmt = NumberFormat('#,##0.00', 'en_IN');

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Total Wallet Balance',
            value: '₹${_fmt.format(totalBalance)}',
            icon: Icons.account_balance_wallet_rounded,
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _StatCard(
            label: 'Vendors with Balance',
            value: vendorsWithBalance.toString(),
            icon: Icons.store_rounded,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _StatCard(
            label: 'Settled This Session',
            value: '₹${_fmt.format(totalSettled)}',
            icon: Icons.payments_rounded,
            color: const Color(0xFF805AD5),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _StatCard(
            label: 'Settlements This Session',
            value: sessionCount.toString(),
            icon: Icons.receipt_long_rounded,
            color: AppColors.accent,
          ),
        ),
      ],
    );
  }
}

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

// ── Vendor Table ───────────────────────────────────────────────────────────────

class _VendorTable extends StatelessWidget {
  const _VendorTable({
    required this.vendors,
    required this.onSettle,
    required this.onHistory,
  });
  final List<Vendor> vendors;
  final void Function(Vendor) onSettle;
  final void Function(Vendor) onHistory;

  static final _fmt = NumberFormat('#,##0.00', 'en_IN');

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.of(context).size.width - 112,
        ),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(3),
            1: FlexColumnWidth(2),
            2: FlexColumnWidth(1.5),
            3: FlexColumnWidth(2),
            4: FlexColumnWidth(2),
          },
          children: [
            TableRow(
              decoration: const BoxDecoration(color: AppColors.background),
              children: const [
                _TableHeader('Vendor'),
                _TableHeader('City'),
                _TableHeader('Status'),
                _TableHeader('Wallet Balance'),
                _TableHeader('Actions'),
              ],
            ),
            for (final vendor in vendors)
              TableRow(
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppColors.border, width: 0.5),
                  ),
                ),
                children: [
                  // Vendor name + owner
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vendor.businessName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (vendor.ownerName?.isNotEmpty == true)
                          Text(
                            vendor.ownerName!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // City
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Text(
                      vendor.city,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ),
                  // Status
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: _StatusBadge(isActive: vendor.isActive),
                  ),
                  // Wallet Balance
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Text(
                      '₹${_fmt.format(vendor.walletBalance)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: vendor.walletBalance > 0
                            ? AppColors.success
                            : AppColors.textSecondary,
                      ),
                    ),
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
                          enabled: vendor.walletBalance > 0,
                          onTap: () => onSettle(vendor),
                        ),
                        const SizedBox(width: 8),
                        _ActionButton(
                          label: 'History',
                          icon: Icons.history_rounded,
                          color: AppColors.primary,
                          enabled: true,
                          onTap: () => onHistory(vendor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isActive});
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (isActive ? AppColors.success : AppColors.textSecondary)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isActive ? AppColors.success : AppColors.textSecondary,
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
      child: GestureDetector(
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

// ── Settlement History Section ────────────────────────────────────────────────

class _SettlementHistorySection extends StatelessWidget {
  const _SettlementHistorySection({
    required this.history,
    required this.moneyFmt,
    required this.dateFmt,
  });
  final List<VendorSettlement> history;
  final NumberFormat moneyFmt;
  final DateFormat dateFmt;

  @override
  Widget build(BuildContext context) {
    return Container(
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
                  'Settlement History',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'This Session · ${history.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),

          if (history.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 40,
                      color: AppColors.border,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No settlements processed in this session',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                columnWidths: const {
                  0: FixedColumnWidth(200),
                  1: FixedColumnWidth(140),
                  2: FixedColumnWidth(220),
                  3: FixedColumnWidth(220),
                  4: FixedColumnWidth(120),
                },
                children: [
                  const TableRow(
                    decoration: BoxDecoration(color: AppColors.background),
                    children: [
                      _TableHeader('Vendor'),
                      _TableHeader('Amount'),
                      _TableHeader('Balance Change'),
                      _TableHeader('Date'),
                      _TableHeader('Settled By'),
                    ],
                  ),
                  for (final entry in history)
                    TableRow(
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: AppColors.border,
                            width: 0.5,
                          ),
                        ),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Text(
                            entry.vendorName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Text(
                            '₹${moneyFmt.format(entry.amount)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.success,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Text(
                            '₹${moneyFmt.format(entry.balanceBefore)} → ₹${moneyFmt.format(entry.balanceAfter)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Text(
                            dateFmt.format(entry.settledAt),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Text(
                            entry.settledBy,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
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
    return GestureDetector(
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
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
