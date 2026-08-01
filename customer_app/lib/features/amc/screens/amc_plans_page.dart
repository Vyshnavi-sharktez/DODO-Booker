import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../providers/amc_plans_provider.dart';
import '../screens/amc_contract_details_screen.dart';

class AmcPlansPage extends ConsumerWidget {
  const AmcPlansPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contractsAsync = ref.watch(allAmcContractsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My AMC Plans'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: contractsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
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
                  onPressed: () => ref.invalidate(allAmcContractsProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (contracts) {
          if (contracts.isEmpty) {
            return _EmptyState();
          }

          final active = contracts
              .where((c) =>
                  c.status == 'active' ||
                  c.status == 'cancellation_requested')
              .toList();
          final completed =
              contracts.where((c) => c.status == 'completed').toList();
          final cancelled =
              contracts.where((c) => c.status == 'cancelled').toList();

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(allAmcContractsProvider),
            child: ListView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              children: [
                if (active.isNotEmpty) ...[
                  _SectionHeader('Active', active.length),
                  ...active.map((c) => _AmcPlanCard(
                        record: c,
                        onRefresh: () =>
                            ref.invalidate(allAmcContractsProvider),
                      )),
                  const SizedBox(height: 8),
                ],
                if (completed.isNotEmpty) ...[
                  _SectionHeader('Completed', completed.length),
                  ...completed.map((c) => _AmcPlanCard(
                        record: c,
                        onRefresh: () =>
                            ref.invalidate(allAmcContractsProvider),
                      )),
                  const SizedBox(height: 8),
                ],
                if (cancelled.isNotEmpty) ...[
                  _SectionHeader('Cancelled', cancelled.length),
                  ...cancelled.map((c) => _AmcPlanCard(
                        record: c,
                        onRefresh: () =>
                            ref.invalidate(allAmcContractsProvider),
                      )),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

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
              style:
                  tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
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

// ── Section header ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  const _SectionHeader(this.title, this.count);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textHint,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary),
            ),
          ),
        ],
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
                      if (_r.planName.isNotEmpty &&
                          _r.serviceName.isNotEmpty)
                        Text(
                          _r.planName,
                          style: tt.labelSmall?.copyWith(
                              color: AppColors.textSecondary),
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
                  style: tt.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w700),
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
        'active'                  => (AppColors.success, 'Active'),
        'paused'                  => (AppColors.warning, 'Paused'),
        'completed'               => (AppColors.primary, 'Completed'),
        'cancelled'               => (AppColors.error, 'Cancelled'),
        'cancellation_requested'  => (const Color(0xFFC05621), 'Cancel Pending'),
        _                         => (AppColors.textHint, 'Unknown'),
      };

  static String _fmtDate(DateTime d) {
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }
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
      const _months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      final d = r.scheduledVisitDate!;
      final dateStr = '${d.day} ${_months[d.month-1]} ${d.year}';
      final timeStr = r.scheduledVisitTime?.isNotEmpty == true
          ? ' · ${r.scheduledVisitTime}'
          : '';
      return (Icons.calendar_month_rounded,
          'Next Visit: $dateStr$timeStr',
          AppColors.success,
          false);
    }
    if (r.hasPendingRequest) {
      return (Icons.hourglass_top_rounded,
          'Scheduling requested — awaiting admin',
          AppColors.warning,
          true);
    }
    if (r.pendingVisitId != null) {
      return (Icons.schedule_send_rounded,
          'Next visit pending scheduling — tap Request',
          AppColors.textSecondary,
          true);
    }
    // No pending visit — all visits scheduled/completed or contract just started
    return (Icons.check_circle_outline_rounded,
        'All visits accounted for',
        AppColors.textHint,
        true);
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
              style: tt.labelSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
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
