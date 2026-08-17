import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../providers/amc_plans_provider.dart';
import '../screens/amc_contract_details_screen.dart';

class AmcPlansPage extends StatelessWidget {
  final bool inModal;
  const AmcPlansPage({super.key, this.inModal = false});

  static const _tabs = [Tab(text: 'My Plans'), Tab(text: 'Pause & Resume')];
  static const _tabViews = [_PlansTab(), _PauseResumeTab()];

  @override
  Widget build(BuildContext context) {
    if (inModal) {
      return DefaultTabController(
        length: 2,
        child: Column(
          children: [
            TabBar(
              tabs: _tabs,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              indicatorWeight: 2,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const Divider(height: 1, color: AppColors.divider),
            const Expanded(child: TabBarView(children: _tabViews)),
          ],
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('My AMC Plans'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            tabs: _tabs,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        body: const TabBarView(children: _tabViews),
      ),
    );
  }
}

// ── Tab 1: My Plans ───────────────────────────────────────────────────────────

enum _PlansFilter { all, active, paused, completed, cancelled }

class _PlansTab extends ConsumerStatefulWidget {
  const _PlansTab();

  @override
  ConsumerState<_PlansTab> createState() => _PlansTabState();
}

class _PlansTabState extends ConsumerState<_PlansTab>
    with AutomaticKeepAliveClientMixin {
  _PlansFilter _filter = _PlansFilter.all;

  @override
  bool get wantKeepAlive => true;

  List<AmcPlanRecord> _applyFilter(List<AmcPlanRecord> contracts) =>
      switch (_filter) {
        _PlansFilter.all => contracts,
        _PlansFilter.active => contracts
            .where((c) =>
                c.status == 'active' || c.status == 'cancellation_requested')
            .toList(),
        _PlansFilter.paused =>
          contracts.where((c) => c.status == 'paused').toList(),
        _PlansFilter.completed =>
          contracts.where((c) => c.status == 'completed').toList(),
        _PlansFilter.cancelled =>
          contracts.where((c) => c.status == 'cancelled').toList(),
      };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final contractsAsync = ref.watch(allAmcContractsProvider);

    return Column(
      children: [
        // Filter chips
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _filter == _PlansFilter.all,
                  color: AppColors.primary,
                  onTap: () => setState(() => _filter = _PlansFilter.all),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Active',
                  selected: _filter == _PlansFilter.active,
                  color: AppColors.success,
                  onTap: () => setState(() => _filter = _PlansFilter.active),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Paused',
                  selected: _filter == _PlansFilter.paused,
                  color: AppColors.warning,
                  onTap: () => setState(() => _filter = _PlansFilter.paused),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Completed',
                  selected: _filter == _PlansFilter.completed,
                  color: AppColors.primary,
                  onTap: () =>
                      setState(() => _filter = _PlansFilter.completed),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Cancelled',
                  selected: _filter == _PlansFilter.cancelled,
                  color: AppColors.error,
                  onTap: () =>
                      setState(() => _filter = _PlansFilter.cancelled),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: contractsAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        size: 48, color: AppColors.textHint),
                    const SizedBox(height: 12),
                    Text('Failed to load AMC plans',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      e.toString(),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () =>
                          ref.invalidate(allAmcContractsProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
            data: (contracts) {
              if (contracts.isEmpty) return _EmptyState();
              final filtered = _applyFilter(contracts);
              if (filtered.isEmpty) {
                return _EmptyFilterState(filter: _filter);
              }
              return RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(allAmcContractsProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _AmcPlanCard(
                    record: filtered[i],
                    onRefresh: () =>
                        ref.invalidate(allAmcContractsProvider),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Tab 2: Pause & Resume Requests ────────────────────────────────────────────

enum _PauseResumeFilter { all, pending, active, history }

sealed class _PauseResumeEntry {
  DateTime get createdAt;
  String get status;
  String get contractId;
  String get serviceName;
  String get planName;
  String get contractStatus;
}

final class _PauseReqEntry extends _PauseResumeEntry {
  final AmcPauseRequestSummary data;
  _PauseReqEntry(this.data);
  @override DateTime get createdAt => data.createdAt;
  @override String get status => data.status;
  @override String get contractId => data.contractId;
  @override String get serviceName => data.serviceName;
  @override String get planName => data.planName;
  @override String get contractStatus => data.contractStatus;
}

final class _ResumeReqEntry extends _PauseResumeEntry {
  final AmcResumeRequestSummary data;
  _ResumeReqEntry(this.data);
  @override DateTime get createdAt => data.createdAt;
  @override String get status => data.status;
  @override String get contractId => data.contractId;
  @override String get serviceName => data.serviceName;
  @override String get planName => data.planName;
  @override String get contractStatus => data.contractStatus;
}

class _PauseResumeTab extends ConsumerStatefulWidget {
  const _PauseResumeTab();

  @override
  ConsumerState<_PauseResumeTab> createState() => _PauseResumeTabState();
}

class _PauseResumeTabState extends ConsumerState<_PauseResumeTab>
    with AutomaticKeepAliveClientMixin {
  _PauseResumeFilter _filter = _PauseResumeFilter.all;

  @override
  bool get wantKeepAlive => true;

  List<_PauseResumeEntry> _buildList(
    List<AmcPauseRequestSummary> pauseItems,
    List<AmcResumeRequestSummary> resumeItems,
  ) {
    List<AmcPauseRequestSummary> fp;
    List<AmcResumeRequestSummary> fr;

    switch (_filter) {
      case _PauseResumeFilter.all:
        fp = pauseItems;
        fr = resumeItems;
      case _PauseResumeFilter.pending:
        fp = pauseItems.where((i) => i.status == 'pending').toList();
        fr = resumeItems.where((i) => i.status == 'pending').toList();
      case _PauseResumeFilter.active:
        fp = pauseItems
            .where((i) =>
                i.status == 'approved' && i.contractStatus == 'paused')
            .toList();
        fr = [];
      case _PauseResumeFilter.history:
        fp = pauseItems
            .where((i) =>
                i.status == 'rejected' ||
                i.status == 'cancelled' ||
                (i.status == 'approved' && i.contractStatus != 'paused'))
            .toList();
        fr = resumeItems.where((i) => i.status != 'pending').toList();
    }

    return [
      ...fp.map(_PauseReqEntry.new),
      ...fr.map(_ResumeReqEntry.new),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  void _openContract(BuildContext context, String contractId, String label) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AmcContractDetailsScreen(
        contractId: contractId,
        initialPlanName: label,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final pauseAsync = ref.watch(allAmcPauseRequestsProvider);
    final resumeAsync = ref.watch(allAmcResumeRequestsProvider);

    return Column(
      children: [
        // Filter chips
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _filter == _PauseResumeFilter.all,
                  color: AppColors.primary,
                  onTap: () =>
                      setState(() => _filter = _PauseResumeFilter.all),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Pending',
                  selected: _filter == _PauseResumeFilter.pending,
                  color: AppColors.warning,
                  onTap: () =>
                      setState(() => _filter = _PauseResumeFilter.pending),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Active',
                  selected: _filter == _PauseResumeFilter.active,
                  color: const Color(0xFF2C7A7B),
                  onTap: () =>
                      setState(() => _filter = _PauseResumeFilter.active),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'History',
                  selected: _filter == _PauseResumeFilter.history,
                  color: AppColors.textSecondary,
                  onTap: () =>
                      setState(() => _filter = _PauseResumeFilter.history),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: pauseAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 40, color: AppColors.textHint),
                  const SizedBox(height: 12),
                  Text('Failed to load requests',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () {
                      ref.invalidate(allAmcPauseRequestsProvider);
                      ref.invalidate(allAmcResumeRequestsProvider);
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
            data: (pauseItems) => resumeAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        size: 40, color: AppColors.textHint),
                    const SizedBox(height: 12),
                    Text('Failed to load requests',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () {
                        ref.invalidate(allAmcPauseRequestsProvider);
                        ref.invalidate(allAmcResumeRequestsProvider);
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (resumeItems) {
                final entries = _buildList(pauseItems, resumeItems);
                if (entries.isEmpty) {
                  return _EmptyRequestsState(filter: _filter);
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(allAmcPauseRequestsProvider);
                    ref.invalidate(allAmcResumeRequestsProvider);
                    ref.invalidate(allAmcContractsProvider);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: 10),
                    itemBuilder: (ctx, i) {
                      final entry = entries[i];
                      final label = entry.planName.isNotEmpty
                          ? entry.planName
                          : entry.serviceName;
                      return switch (entry) {
                        _PauseReqEntry(:final data) => _PauseRequestCard(
                            item: data,
                            onViewContract: () =>
                                _openContract(context, data.contractId, label),
                          ),
                        _ResumeReqEntry(:final data) => _ResumeRequestCard(
                            item: data,
                            onViewContract: () =>
                                _openContract(context, data.contractId, label),
                          ),
                      };
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ── Pause request card ─────────────────────────────────────────────────────────

class _PauseRequestCard extends StatelessWidget {
  final AmcPauseRequestSummary item;
  final VoidCallback onViewContract;

  const _PauseRequestCard({
    required this.item,
    required this.onViewContract,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isActive = item.status == 'approved' && item.contractStatus == 'paused';
    final (statusLabel, statusColor, statusBg) = _statusMeta(item.status, isActive);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.pause_circle_rounded,
                      size: 18, color: AppColors.warning),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.serviceName.isNotEmpty
                            ? item.serviceName
                            : 'AMC Plan',
                        style: tt.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.planName.isNotEmpty)
                        Text(
                          item.planName,
                          style: tt.labelSmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            // Details
            _DetailRow(
              icon: Icons.pause_outlined,
              label: 'Type',
              value: 'Pause Request',
            ),
            if (item.reason.isNotEmpty)
              _DetailRow(
                icon: Icons.notes_rounded,
                label: 'Reason',
                value: item.reason,
              ),
            _DetailRow(
              icon: Icons.calendar_today_rounded,
              label: 'Submitted',
              value: _fmtDate(item.createdAt.toLocal()),
            ),
            if (item.resolvedAt != null)
              _DetailRow(
                icon: Icons.check_circle_outline_rounded,
                label: 'Resolved',
                value: _fmtDate(item.resolvedAt!.toLocal()),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: onViewContract,
                icon: const Icon(Icons.open_in_new_rounded, size: 13),
                label: const Text('View Contract'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  (String, Color, Color) _statusMeta(String status, bool isActive) =>
      switch (status) {
        'pending' => (
            'Pending',
            AppColors.warning,
            AppColors.warning.withValues(alpha: 0.12),
          ),
        'approved' when isActive => (
            'Active',
            const Color(0xFF2C7A7B),
            const Color(0xFFE6FFFA),
          ),
        'approved' => (
            'Completed',
            AppColors.success,
            AppColors.success.withValues(alpha: 0.12),
          ),
        'rejected' => ('Rejected', AppColors.textSecondary, AppColors.border),
        'cancelled' => ('Cancelled', AppColors.textSecondary, AppColors.border),
        _ => (status, AppColors.textHint, AppColors.border),
      };
}

// ── Resume request card ────────────────────────────────────────────────────────

class _ResumeRequestCard extends StatelessWidget {
  final AmcResumeRequestSummary item;
  final VoidCallback onViewContract;

  const _ResumeRequestCard({
    required this.item,
    required this.onViewContract,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final (statusLabel, statusColor, statusBg) = _statusMeta(item.status);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.play_circle_rounded,
                      size: 18, color: AppColors.success),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.serviceName.isNotEmpty
                            ? item.serviceName
                            : 'AMC Plan',
                        style: tt.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.planName.isNotEmpty)
                        Text(
                          item.planName,
                          style: tt.labelSmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            // Details
            _DetailRow(
              icon: Icons.play_circle_outline_rounded,
              label: 'Type',
              value: 'Resume Request',
            ),
            if (item.reason != null && item.reason!.isNotEmpty)
              _DetailRow(
                icon: Icons.notes_rounded,
                label: 'Reason',
                value: item.reason!,
              ),
            if (item.pauseDurationDays != null && item.pauseDurationDays! > 0)
              _DetailRow(
                icon: Icons.timer_outlined,
                label: 'Pause Duration',
                value:
                    '${item.pauseDurationDays} day${item.pauseDurationDays == 1 ? '' : 's'}',
              ),
            _DetailRow(
              icon: Icons.calendar_today_rounded,
              label: 'Submitted',
              value: _fmtDate(item.createdAt.toLocal()),
            ),
            if (item.resolvedAt != null)
              _DetailRow(
                icon: Icons.check_circle_outline_rounded,
                label: 'Resolved',
                value: _fmtDate(item.resolvedAt!.toLocal()),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: onViewContract,
                icon: const Icon(Icons.open_in_new_rounded, size: 13),
                label: const Text('View Contract'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  (String, Color, Color) _statusMeta(String status) => switch (status) {
        'pending' => (
            'Pending',
            AppColors.warning,
            AppColors.warning.withValues(alpha: 0.12),
          ),
        'approved' => (
            'Approved',
            AppColors.success,
            AppColors.success.withValues(alpha: 0.12),
          ),
        'rejected' => ('Rejected', AppColors.textSecondary, AppColors.border),
        'cancelled' => ('Cancelled', AppColors.textSecondary, AppColors.border),
        _ => (status, AppColors.textHint, AppColors.border),
      };
}

// ── Shared detail row ──────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 13, color: AppColors.textHint),
          ),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: tt.labelSmall?.copyWith(color: AppColors.textSecondary),
          ),
          Expanded(
            child: Text(
              value,
              style: tt.labelSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Filter chip ────────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? color : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ── Empty states ──────────────────────────────────────────────────────────────

class _EmptyRequestsState extends StatelessWidget {
  final _PauseResumeFilter filter;
  const _EmptyRequestsState({required this.filter});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final label = switch (filter) {
      _PauseResumeFilter.all => 'No pause or resume requests yet.',
      _PauseResumeFilter.pending => 'No pending requests.',
      _PauseResumeFilter.active => 'No active pauses.',
      _PauseResumeFilter.history => 'No history yet.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.border,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.pause_circle_outline_rounded,
                  size: 30, color: AppColors.textHint),
            ),
            const SizedBox(height: 16),
            Text(label,
                style: tt.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _EmptyFilterState extends StatelessWidget {
  final _PlansFilter filter;
  const _EmptyFilterState({required this.filter});

  @override
  Widget build(BuildContext context) {
    final label = switch (filter) {
      _PlansFilter.all => 'No AMC plans found.',
      _PlansFilter.active => 'No active plans.',
      _PlansFilter.paused => 'No paused plans.',
      _PlansFilter.completed => 'No completed plans.',
      _PlansFilter.cancelled => 'No cancelled plans.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.border,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.autorenew_rounded,
                  size: 30, color: AppColors.textHint),
            ),
            const SizedBox(height: 16),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.autorenew_rounded,
                  size: 36, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            Text(
              'No AMC Plans Yet',
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Subscribe to an Annual Maintenance Contract\nto keep your services running smoothly.',
              style: tt.bodySmall
                  ?.copyWith(color: AppColors.textSecondary, height: 1.6),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── AMC plan card ──────────────────────────────────────────────────────────────

class _AmcPlanCard extends ConsumerStatefulWidget {
  final AmcPlanRecord record;
  final VoidCallback onRefresh;

  const _AmcPlanCard({required this.record, required this.onRefresh});

  @override
  ConsumerState<_AmcPlanCard> createState() => _AmcPlanCardState();
}

class _AmcPlanCardState extends ConsumerState<_AmcPlanCard> {
  AmcPlanRecord get _r => widget.record;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final (statusColor, statusLabel) = _statusMeta(_r.status);
    final total = _r.totalVisits;
    final completed = _r.visitsCompleted;
    final progress = total > 0 ? (completed / total).clamp(0.0, 1.0) : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ───────────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.autorenew_rounded,
                      size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _r.serviceName.isNotEmpty
                            ? _r.serviceName
                            : _r.planName,
                        style: tt.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_r.planName.isNotEmpty && _r.serviceName.isNotEmpty)
                        Text(
                          _r.planName,
                          style: tt.labelSmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusChip(label: statusLabel, color: statusColor),
              ],
            ),

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // ── Info rows ─────────────────────────────────────────────────
            _InfoRow(
              Icons.calendar_today_rounded,
              'Purchase Date',
              _fmtDate(_r.createdAt.toLocal()),
            ),
            if (_r.expiryDate != null)
              _InfoRow(
                Icons.event_rounded,
                'Expiry Date',
                _fmtDate(_r.expiryDate!),
              ),

            const SizedBox(height: 8),

            // ── Progress ──────────────────────────────────────────────────
            Row(
              children: [
                Text(
                  '$completed / $total Visits',
                  style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  'Remaining: ${_r.remainingVisits}',
                  style: tt.labelSmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: AppColors.border,
                color: _r.status == 'completed'
                    ? AppColors.primary
                    : AppColors.success,
              ),
            ),

            const SizedBox(height: 8),

            // ── Next visit status ─────────────────────────────────────────
            _NextVisitRow(record: _r),

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // ── Action buttons ────────────────────────────────────────────
            _buildActions(context, tt),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context, TextTheme tt) {
    return Align(
      alignment: Alignment.centerRight,
      child: OutlinedButton.icon(
        onPressed: () => _openDetails(context),
        icon: const Icon(Icons.open_in_new_rounded, size: 14),
        label: const Text('View Details'),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          textStyle: const TextStyle(fontSize: 12),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
      ),
    );
  }

  void _openDetails(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AmcContractDetailsScreen(
        contractId: _r.contractId,
        initialPlanName:
            _r.planName.isNotEmpty ? _r.planName : _r.serviceName,
      ),
    ));
  }

  static (Color, String) _statusMeta(String s) => switch (s) {
        'active' => (AppColors.success, 'Active'),
        'paused' => (AppColors.warning, 'Paused'),
        'completed' => (AppColors.primary, 'Completed'),
        'cancelled' => (AppColors.error, 'Cancelled'),
        'cancellation_requested' => (const Color(0xFFC05621), 'Cancel Pending'),
        _ => (AppColors.textHint, 'Unknown'),
      };
}

// ── Next visit row ─────────────────────────────────────────────────────────────

class _NextVisitRow extends StatelessWidget {
  final AmcPlanRecord record;
  const _NextVisitRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    if (!record.isActive) return const SizedBox.shrink();

    final (icon, label, color, italic) = _visitState(record);

    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: tt.labelSmall?.copyWith(
              color: color,
              fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  static (IconData, String, Color, bool) _visitState(AmcPlanRecord r) {
    if (r.scheduledVisitDate != null) {
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final d = r.scheduledVisitDate!;
      final dateStr = '${d.day} ${months[d.month - 1]} ${d.year}';
      final timeStr = r.scheduledVisitTime?.isNotEmpty == true
          ? ' · ${r.scheduledVisitTime}'
          : '';
      return (Icons.calendar_month_rounded,
          'Next Visit: $dateStr$timeStr', AppColors.success, false);
    }
    if (r.hasPendingRequest) {
      return (Icons.hourglass_top_rounded,
          'Scheduling requested — awaiting admin', AppColors.warning, true);
    }
    if (r.pendingVisitId != null) {
      return (Icons.schedule_send_rounded,
          'Next visit pending scheduling — tap Request',
          AppColors.textSecondary, true);
    }
    return (Icons.check_circle_outline_rounded,
        'All visits accounted for', AppColors.textHint, true);
  }
}

// ── Tiny widgets ───────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 13, color: AppColors.textHint),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: tt.labelSmall?.copyWith(color: AppColors.textSecondary),
          ),
          Expanded(
            child: Text(
              value,
              style: tt.labelSmall?.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

String _fmtDate(DateTime d) {
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}
