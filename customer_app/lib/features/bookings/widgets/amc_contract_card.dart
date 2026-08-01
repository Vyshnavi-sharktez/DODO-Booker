import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../amc/models/amc_contract_summary.dart';
import '../../amc/screens/amc_contract_details_screen.dart';

class AmcContractCard extends StatelessWidget {
  final AmcContractSummary contract;

  const AmcContractCard({super.key, required this.contract});

  AmcContractSummary get _c => contract;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final (statusColor, statusLabel) = _statusMeta(_c.contractStatus);
    final total = _c.totalVisits;
    final completed = _c.visitsCompleted;
    final progress = total > 0 ? (completed / total).clamp(0.0, 1.0) : 0.0;

    // Next visit display
    final next = _c.nextUpcomingVisit;
    final nextLabel = next?.serviceDate != null
        ? _formatDate(next!.serviceDate!)
        : (next != null ? 'Not yet scheduled' : '—');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: () => _openDetails(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────────────
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
                    child: const Icon(
                      Icons.autorenew_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _c.serviceName.isNotEmpty
                              ? _c.serviceName
                              : _c.planName,
                          style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_c.planName.isNotEmpty &&
                            _c.serviceName.isNotEmpty)
                          Text(
                            _c.planName,
                            style: tt.labelSmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StatusChip(label: statusLabel, color: statusColor),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'AMC',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // ── Progress ─────────────────────────────────────────────────────
              Text(
                '$completed / $total Visits Completed',
                style: tt.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: AppColors.border,
                  color: _c.isCompleted ? AppColors.primary : AppColors.success,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    'Remaining: ${_c.remainingVisits}',
                    style: tt.labelSmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  if (next != null) ...[
                    const SizedBox(width: 12),
                    const Text('·',
                        style: TextStyle(color: AppColors.textHint)),
                    const SizedBox(width: 12),
                    const Icon(Icons.calendar_today_rounded,
                        size: 11, color: AppColors.textHint),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Next: $nextLabel',
                        style: tt.labelSmall?.copyWith(
                          color: next.serviceDate != null
                              ? AppColors.textPrimary
                              : AppColors.textHint,
                          fontStyle: next.serviceDate == null
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),

              // ── Footer ──────────────────────────────────────────────────────
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _openDetails(context),
                  icon: const Icon(Icons.open_in_new_rounded, size: 14),
                  label: const Text('View Details'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDetails(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AmcContractDetailsScreen(
          contractId: _c.contractId,
          initialPlanName:
              _c.planName.isNotEmpty ? _c.planName : _c.serviceName,
        ),
      ),
    );
  }

  static (Color, String) _statusMeta(String status) => switch (status) {
        'active' => (AppColors.success, 'Active'),
        'paused' => (AppColors.warning, 'Paused'),
        'completed' => (AppColors.primary, 'Completed'),
        'cancelled' => (AppColors.error, 'Cancelled'),
        'cancellation_requested' => (const Color(0xFFC05621), 'Cancel Pending'),
        _ => (AppColors.textHint, 'Unknown'),
      };

  static String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
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
