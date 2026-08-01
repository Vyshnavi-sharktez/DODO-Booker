import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../vendors/application/providers/vendors_providers.dart';

// ── Date helpers ──────────────────────────────────────────────────────────────

const _kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _fmt(DateTime d) => '${d.day} ${_kMonths[d.month - 1]} ${d.year}';

// Adds N calendar months to a UTC base date, clamping the day to the last day
// of the target month.  Mirrors PostgreSQL: start + N * interval '1 month'.
//
// Example: 2026-07-30 + 7 months = 2027-02-28 (not 2027-03-02).
DateTime _addCalendarMonths(DateTime base, int months) {
  final total = (base.month - 1) + months;
  final targetYear = base.year + total ~/ 12;
  final targetMonth = total % 12 + 1;
  // Day 0 of the following month == last day of targetMonth
  final daysInMonth = DateTime.utc(targetYear, targetMonth + 1, 0).day;
  return DateTime.utc(targetYear, targetMonth, base.day.clamp(1, daysInMonth));
}

// Computes the fixed planned due date for visit N using the same calendar
// arithmetic as the PostgreSQL trigger.  createdAt must be a UTC DateTime.
DateTime? _adminPlannedDate(
    DateTime createdAt, String? interval, int visitNumber) {
  if (interval == null) return null;
  final n = visitNumber - 1; // 0-based month/year offset
  final base = DateTime.utc(createdAt.year, createdAt.month, createdAt.day);
  return switch (interval) {
    'weekly'      => base.add(Duration(days: 7 * n)),
    'bi_weekly'   => base.add(Duration(days: 14 * n)),
    'monthly'     => _addCalendarMonths(base, n),
    'quarterly'   => _addCalendarMonths(base, 3 * n),
    'half_yearly' => _addCalendarMonths(base, 6 * n),
    'yearly'      => _addCalendarMonths(base, 12 * n),
    _ => null,
  };
}

// Planned date of the final visit = end of contract service schedule.
DateTime? _contractEndDate(_AmcContract c) {
  final total = c.effectiveTotal;
  if (total <= 0) return null;
  return _adminPlannedDate(c.createdAt, c.serviceInterval, total);
}

String _intervalLabel(String? s) => switch (s) {
      'weekly'      => 'Weekly',
      'bi_weekly'   => 'Bi-Weekly',
      'monthly'     => 'Monthly',
      'quarterly'   => 'Quarterly',
      'half_yearly' => 'Half Yearly',
      'yearly'      => 'Yearly',
      _ => s ?? '—',
    };

String _durationLabel(String? s) => switch (s) {
      'monthly'     => 'Monthly',
      'quarterly'   => 'Quarterly',
      'half_yearly' => 'Half Yearly',
      'yearly'      => 'Yearly',
      _ => s ?? '—',
    };

// ── Lightweight models ────────────────────────────────────────────────────────

class _AmcVisit {
  final String id;
  final int? visitNumber;
  final String status;
  final DateTime? serviceDate;
  final String timeSlot;
  final double totalAmount;
  final String? vendorId;
  final DateTime? completedAt;

  const _AmcVisit({
    required this.id,
    this.visitNumber,
    required this.status,
    this.serviceDate,
    required this.timeSlot,
    required this.totalAmount,
    this.vendorId,
    this.completedAt,
  });

  factory _AmcVisit.fromMap(Map<String, dynamic> m) => _AmcVisit(
        id: m['id'] as String,
        visitNumber: (m['amc_visit_number'] as num?)?.toInt(),
        status: m['status'] as String? ?? 'pending',
        serviceDate: m['service_date'] != null
            ? DateTime.tryParse(m['service_date'] as String)
            : null,
        timeSlot: m['scheduled_time'] as String? ?? '',
        totalAmount: (m['total_amount'] as num?)?.toDouble() ?? 0.0,
        vendorId: m['vendor_id'] as String?,
        completedAt: m['otp_verified_at'] != null
            ? DateTime.tryParse(m['otp_verified_at'] as String)
            : null,
      );
}

class _AmcContract {
  final String id;
  final String customerId;
  final String serviceName;
  final String planName;
  final String recurrenceInterval;
  final double pricePerVisit;
  final String status;
  final int totalVisits;
  final int? numVisits;
  final double? originalTotal;
  final String? discountType;
  final double? discountValue;
  final double? discountAmount;
  final double? finalPrice;
  final DateTime createdAt;
  final String? serviceInterval;
  final String? packageDuration;
  final String? cancellationReason;
  final String? cancellationRemarks;
  final DateTime? cancellationRequestedAt;
  final int quantity;
  final bool isRenewal;
  final String? previousContractId;
  final List<_AmcVisit> visits;

  const _AmcContract({
    required this.id,
    required this.customerId,
    required this.serviceName,
    required this.planName,
    required this.recurrenceInterval,
    required this.pricePerVisit,
    required this.status,
    required this.totalVisits,
    this.numVisits,
    this.originalTotal,
    this.discountType,
    this.discountValue,
    this.discountAmount,
    this.finalPrice,
    required this.createdAt,
    this.serviceInterval,
    this.packageDuration,
    this.cancellationReason,
    this.cancellationRemarks,
    this.cancellationRequestedAt,
    this.quantity = 1,
    this.isRenewal = false,
    this.previousContractId,
    this.visits = const [],
  });

  bool get isCancellationRequested => status == 'cancellation_requested';

  int get effectiveTotal => numVisits ?? totalVisits;
  int get completedCount =>
      visits.where((v) => v.status == 'completed').length;
  int get remainingCount => (effectiveTotal - completedCount).clamp(0, 9999);

  factory _AmcContract.fromMap(
    Map<String, dynamic> m, {
    List<_AmcVisit> visits = const [],
  }) =>
      _AmcContract(
        id: m['id'] as String,
        customerId: m['customer_id'] as String? ?? '',
        serviceName: m['service_name'] as String? ?? '',
        planName: m['plan_name'] as String? ?? '',
        recurrenceInterval: m['recurrence_interval'] as String? ?? '',
        pricePerVisit: (m['price_per_visit'] as num?)?.toDouble() ?? 0.0,
        status: m['status'] as String? ?? 'active',
        totalVisits: (m['total_visits'] as num?)?.toInt() ?? 0,
        numVisits: (m['num_visits'] as num?)?.toInt(),
        originalTotal: (m['original_total'] as num?)?.toDouble(),
        discountType: m['discount_type'] as String?,
        discountValue: (m['discount_value'] as num?)?.toDouble(),
        discountAmount: (m['discount_amount'] as num?)?.toDouble(),
        finalPrice: (m['final_price'] as num?)?.toDouble(),
        createdAt: DateTime.parse(m['created_at'] as String),
        serviceInterval: m['service_interval'] as String?,
        packageDuration: m['package_duration'] as String?,
        cancellationReason: m['cancellation_reason'] as String?,
        cancellationRemarks: m['cancellation_remarks'] as String?,
        cancellationRequestedAt: m['cancellation_requested_at'] != null
            ? DateTime.tryParse(m['cancellation_requested_at'] as String)
            : null,
        quantity: (m['quantity'] as num?)?.toInt() ?? 1,
        isRenewal: m['is_renewal'] as bool? ?? false,
        previousContractId: m['previous_contract_id'] as String?,
        visits: visits,
      );
}

// ── Provider ──────────────────────────────────────────────────────────────────

final _amcContractDetailProvider = FutureProvider.autoDispose
    .family<_AmcContract?, String>((ref, contractId) async {
  final client = Supabase.instance.client;

  final raw = await client
      .from('amc_contracts')
      .select(
        'id, customer_id, service_name, plan_name, recurrence_interval, price_per_visit, '
        'status, total_visits, num_visits, created_at, '
        'service_interval, package_duration, '
        'original_total, discount_type, discount_value, discount_amount, final_price, '
        'cancellation_reason, cancellation_remarks, cancellation_requested_at, '
        'quantity, is_renewal, previous_contract_id',
      )
      .eq('id', contractId)
      .maybeSingle();

  if (raw == null) return null;

  final row = Map<String, dynamic>.from(raw);

  final visitsRaw = await client
      .from('bookings')
      .select(
          'id, amc_visit_number, status, service_date, scheduled_time, '
          'total_amount, vendor_id, otp_verified_at')
      .eq('amc_contract_id', contractId)
      .order('amc_visit_number', ascending: true, nullsFirst: false)
      .order('created_at', ascending: true);

  final visits = (visitsRaw as List<dynamic>)
      .map((v) => _AmcVisit.fromMap(Map<String, dynamic>.from(v as Map)))
      .toList();

  return _AmcContract.fromMap(row, visits: visits);
});

// ── Dialog shell ──────────────────────────────────────────────────────────────

class AmcContractDetailsDialog extends ConsumerStatefulWidget {
  final String contractId;
  final String planName;

  const AmcContractDetailsDialog({
    super.key,
    required this.contractId,
    this.planName = 'AMC Contract',
  });

  @override
  ConsumerState<AmcContractDetailsDialog> createState() =>
      _AmcContractDetailsDialogState();
}

class _AmcContractDetailsDialogState
    extends ConsumerState<AmcContractDetailsDialog> {
  bool _approving = false;
  bool _rejecting = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.invalidate(_amcContractDetailProvider(widget.contractId));
    });
  }

  Future<void> _resolveRequest(
      dynamic client, String contractId, String newStatus) async {
    try {
      final rows = await client
          .from('amc_cancellation_requests')
          .select('id')
          .eq('contract_id', contractId)
          .eq('status', 'pending')
          .limit(1);
      if ((rows as List).isNotEmpty) {
        await client.from('amc_cancellation_requests').update({
          'status': newStatus,
          'resolved_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', rows.first['id'] as String);
      }
    } catch (_) {}
  }

  Future<void> _approve(BuildContext context, _AmcContract contract) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Approve Cancellation'),
        content: Text(
          'Approve cancellation of "${contract.planName}"?\n\n'
          'All pending and scheduled visits will be cancelled. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Approve Cancellation'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _approving = true);
    try {
      final client = Supabase.instance.client;
      await _resolveRequest(client, contract.id, 'approved');
      final updated = await client
          .from('amc_contracts')
          .update({
            'status': 'cancelled',
            if (contract.cancellationReason != null)
              'cancellation_reason': contract.cancellationReason,
            if (contract.cancellationRemarks != null)
              'cancellation_remarks': contract.cancellationRemarks,
            if (contract.cancellationRequestedAt != null)
              'cancellation_requested_at':
                  contract.cancellationRequestedAt!.toUtc().toIso8601String(),
          })
          .eq('id', contract.id)
          .select('id');
      if ((updated as List).isEmpty) {
        throw Exception(
            'Contract update failed — apply pending database migrations.');
      }
      await client
          .from('bookings')
          .update({'status': 'cancelled'})
          .eq('amc_contract_id', contract.id)
          .inFilter('status', [
            'pending', 'assigned', 'assigned_to_dodo_team', 'accepted',
          ]);
      await client
          .from('amc_scheduling_requests')
          .update({'status': 'cancelled'})
          .eq('amc_contract_id', contract.id)
          .eq('status', 'pending');
      if (contract.customerId.isNotEmpty) {
        try {
          await client.from('notifications').insert({
            'user_type': 'customer',
            'user_id': contract.customerId,
            'title': 'AMC Cancellation Approved',
            'message':
                'Your request to cancel the "${contract.planName}" AMC contract has been approved. Your membership is now cancelled.',
            'notification_type': 'amc_cancellation_approved',
            'is_read': false,
            'entity_type': 'amc_contract',
            'entity_id': contract.id,
          });
        } catch (_) {}
      }
      ref.invalidate(_amcContractDetailProvider(widget.contractId));
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('AMC contract "${contract.planName}" cancelled.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to approve cancellation: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  Future<void> _reject(BuildContext context, _AmcContract contract) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Reject Cancellation'),
        content: Text(
          'Reject the cancellation request for "${contract.planName}"?\n\n'
          'The contract will be restored to Active status.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reject Request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _rejecting = true);
    try {
      final client = Supabase.instance.client;
      await _resolveRequest(client, contract.id, 'rejected');
      await client.from('amc_contracts').update({
        'status': 'active',
        'cancellation_reason': null,
        'cancellation_remarks': null,
        'cancellation_requested_at': null,
      }).eq('id', contract.id);
      if (contract.customerId.isNotEmpty) {
        try {
          await client.from('notifications').insert({
            'user_type': 'customer',
            'user_id': contract.customerId,
            'title': 'AMC Cancellation Rejected',
            'message':
                'Your request to cancel the "${contract.planName}" AMC contract has been rejected. Your membership remains active.',
            'notification_type': 'amc_cancellation_rejected',
            'is_read': false,
            'entity_type': 'amc_contract',
            'entity_id': contract.id,
          });
        } catch (_) {}
      }
      ref.invalidate(_amcContractDetailProvider(widget.contractId));
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Cancellation rejected — membership restored to Active.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to reject: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _rejecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contractAsync =
        ref.watch(_amcContractDetailProvider(widget.contractId));
    final vendors = ref.watch(vendorsNotifierProvider).valueOrNull ?? [];
    final vendorMap = {for (final v in vendors) v.id: v.businessName};

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DialogHeader(planName: widget.planName),
            Flexible(
              child: contractAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                    child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Error: $e'),
                )),
                data: (contract) {
                  if (contract == null) {
                    return const Center(
                        child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Contract not found.'),
                    ));
                  }
                  return _DialogBody(
                    contract: contract,
                    vendorMap: vendorMap,
                    approving: _approving,
                    rejecting: _rejecting,
                    onApprove: () => _approve(context, contract),
                    onReject: () => _reject(context, contract),
                  );
                },
              ),
            ),
            _DialogFooter(onClose: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _DialogHeader extends StatelessWidget {
  final String planName;
  const _DialogHeader({required this.planName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.autorenew_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AMC Contract',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
                Text(
                  planName,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
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
}

// ── Footer ────────────────────────────────────────────────────────────────────

class _DialogFooter extends StatelessWidget {
  final VoidCallback onClose;
  const _DialogFooter({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration:
          const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
      child: Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton(onPressed: onClose, child: const Text('Close')),
      ),
    );
  }
}

// ── Dialog body ───────────────────────────────────────────────────────────────

class _DialogBody extends StatelessWidget {
  final _AmcContract contract;
  final Map<String, String> vendorMap;
  final bool approving;
  final bool rejecting;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _DialogBody({
    required this.contract,
    required this.vendorMap,
    required this.approving,
    required this.rejecting,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final total = contract.effectiveTotal;
    final displayCount = total > 0 ? total : contract.visits.length;
    final visitMap = _buildVisitMap(contract.visits);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SummaryCard(contract: contract),
          if (contract.isCancellationRequested) ...[
            const SizedBox(height: 16),
            _CancellationSection(
              contract: contract,
              approving: approving,
              rejecting: rejecting,
              onApprove: onApprove,
              onReject: onReject,
            ),
          ],
          const SizedBox(height: 16),
          // Section label
          const _SectionLabel('VISIT TIMELINE'),
          const SizedBox(height: 8),
          if (displayCount == 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No visits linked to this contract yet.',
                style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic),
              ),
            )
          else
            ...List.generate(displayCount, (i) {
              final n = i + 1;
              final v = visitMap[n];
              return _VisitCard(
                visit: v,
                visitNumber: n,
                plannedDueDate: _adminPlannedDate(
                    contract.createdAt, contract.serviceInterval, n),
                vendorName:
                    v?.vendorId != null ? vendorMap[v!.vendorId!] : null,
              );
            }),
        ],
      ),
    );
  }

  static Map<int, _AmcVisit> _buildVisitMap(List<_AmcVisit> visits) {
    final map = <int, _AmcVisit>{};
    for (final v in visits) {
      final n = v.visitNumber;
      if (n != null && n >= 1) {
        final existing = map[n];
        if (existing == null ||
            _statusRank(v.status) > _statusRank(existing.status)) {
          map[n] = v;
        }
      }
    }
    return map;
  }

  static int _statusRank(String s) => switch (s) {
        'completed' => 5,
        'awaiting_verification' => 4,
        'in_progress' || 'started' => 3,
        'assigned' || 'accepted' || 'en_route' => 2,
        'pending' => 1,
        _ => 0,
      };
}

// ── Summary card ──────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final _AmcContract contract;
  const _SummaryCard({required this.contract});

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor, statusBg) = _statusMeta(contract.status);
    final total = contract.effectiveTotal;
    final completed = contract.completedCount;
    final remaining = contract.remainingCount;
    final progress = total > 0 ? completed / total : 0.0;

    final startDate = _fmt(contract.createdAt.toLocal());
    final endDate = _contractEndDate(contract);
    final endStr = endDate != null ? _fmt(endDate) : '—';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEBF8FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: const Color(0xFF3182CE).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Plan name + status
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contract.planName.isNotEmpty
                          ? contract.planName
                          : 'AMC Contract',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2B6CB0)),
                    ),
                    if (contract.serviceName.isNotEmpty)
                      Text(
                        contract.serviceName,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(20)),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: statusColor),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Date + interval grid
          Row(
            children: [
              Expanded(
                  child: _MetaItem(label: 'Start Date', value: startDate)),
              Expanded(child: _MetaItem(label: 'End Date', value: endStr)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                  child: _MetaItem(
                      label: 'Service Interval',
                      value: _intervalLabel(contract.serviceInterval))),
              Expanded(
                  child: _MetaItem(
                      label: 'Package Duration',
                      value: _durationLabel(contract.packageDuration))),
            ],
          ),

          // Pricing (compact, only when present)
          if (contract.finalPrice != null && contract.finalPrice! > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (contract.originalTotal != null &&
                    contract.originalTotal! > 0)
                  Expanded(
                      child: _MetaItem(
                          label: 'Original Total',
                          value:
                              '₹${contract.originalTotal!.toStringAsFixed(0)}')),
                if (contract.discountAmount != null &&
                    contract.discountAmount! > 0)
                  Expanded(
                      child: _MetaItem(
                          label: 'Discount',
                          value: _discountLabel(contract))),
                Expanded(
                    child: _MetaItem(
                        label: 'Final Price',
                        value:
                            '₹${contract.finalPrice!.toStringAsFixed(0)}')),
              ],
            ),
          ],

          if (contract.quantity > 1 || contract.isRenewal) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (contract.quantity > 1)
                  Expanded(
                    child: _MetaItem(
                      label: 'Units Covered',
                      value: '${contract.quantity} units',
                    ),
                  ),
                if (contract.isRenewal)
                  Expanded(
                    child: _MetaItem(
                      label: 'Contract Type',
                      value: 'Renewal',
                    ),
                  ),
              ],
            ),
          ],
          if (contract.previousContractId != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                showDialog(
                  context: context,
                  builder: (_) => AmcContractDetailsDialog(
                    contractId: contract.previousContractId!,
                    planName: 'Previous Contract',
                  ),
                );
              },
              icon: const Icon(Icons.history_rounded, size: 14),
              label: const Text('View Previous Contract',
                  style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF3182CE),
                side: const BorderSide(color: Color(0xFF3182CE)),
                padding: const EdgeInsets.symmetric(vertical: 8),
                minimumSize: const Size.fromHeight(36),
              ),
            ),
          ],

          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFBEE3F8)),
          const SizedBox(height: 10),

          // Progress
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$completed of $total visits completed',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2B6CB0)),
              ),
              Text(
                '$remaining remaining',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.6),
              color: const Color(0xFF276749),
            ),
          ),
        ],
      ),
    );
  }

  String _discountLabel(_AmcContract c) {
    final amt = c.discountAmount ?? 0;
    if (c.discountType == 'percentage' && c.discountValue != null) {
      return '−₹${amt.toStringAsFixed(0)} (${c.discountValue!.toStringAsFixed(0)}%)';
    }
    return '−₹${amt.toStringAsFixed(0)}';
  }

  (String, Color, Color) _statusMeta(String status) => switch (status) {
        'active' => ('Active', const Color(0xFF276749), const Color(0xFFF0FFF4)),
        'paused' =>
          ('Paused', const Color(0xFF744210), const Color(0xFFFEFCBF)),
        'completed' => ('Completed', const Color(0xFF2B6CB0),
            const Color(0xFFEBF8FF)),
        'cancelled' => ('Cancelled', const Color(0xFFC53030),
            const Color(0xFFFFF5F5)),
        'cancellation_requested' => ('Cancel Pending', const Color(0xFFC05621),
            const Color(0xFFFFF3E0)),
        _ => ('Unknown', AppColors.textSecondary, AppColors.border),
      };
}

// ── Cancellation section ──────────────────────────────────────────────────────

class _CancellationSection extends StatelessWidget {
  final _AmcContract contract;
  final bool approving;
  final bool rejecting;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _CancellationSection({
    required this.contract,
    required this.approving,
    required this.rejecting,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    const borderColor = Color(0xFFC05621);
    const bgColor = Color(0xFFFFF3E0);
    final requestedAt = contract.cancellationRequestedAt;
    final requestedStr = requestedAt != null ? _fmt(requestedAt.toLocal()) : '—';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cancel_outlined, size: 16, color: borderColor),
              const SizedBox(width: 6),
              const Text(
                'CANCELLATION REQUEST',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: borderColor,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: borderColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Pending Approval',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: borderColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'REASON',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: borderColor,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      contract.cancellationReason ?? '—',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF7B341E),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'REQUESTED ON',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: borderColor,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    requestedStr,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF7B341E),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (contract.cancellationRemarks != null &&
              contract.cancellationRemarks!.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'REMARKS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: borderColor,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              contract.cancellationRemarks!,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF7B341E),
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFDDA98C)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: (approving || rejecting) ? null : onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                  ),
                  child: rejecting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : const Text('Reject'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: (approving || rejecting) ? null : onApprove,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                  ),
                  child: approving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: Colors.white),
                        )
                      : const Text('Approve Cancellation'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Meta item ─────────────────────────────────────────────────────────────────

class _MetaItem extends StatelessWidget {
  final String label;
  final String value;
  const _MetaItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 1),
        Text(value,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2D3748))),
      ],
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }
}

// ── Visit card ────────────────────────────────────────────────────────────────

class _VisitCard extends StatelessWidget {
  final _AmcVisit? visit;
  final int visitNumber;
  final DateTime? plannedDueDate;
  final String? vendorName;

  const _VisitCard({
    required this.visit,
    required this.visitNumber,
    this.plannedDueDate,
    this.vendorName,
  });

  @override
  Widget build(BuildContext context) {
    final v = visit;
    final (statusLabel, statusColor, statusBg) =
        _statusMeta(v?.status);

    // Scheduled date: service_date is stored as a date-only string (no .toLocal() needed)
    final scheduledDate = v?.serviceDate;
    final scheduledStr =
        scheduledDate != null ? _fmt(scheduledDate) : 'Not Scheduled';
    final hasScheduled = scheduledDate != null;

    // Completed date: otp_verified_at is a real TIMESTAMPTZ — use .toLocal()
    final completedAt = v?.completedAt;
    final completedStr =
        completedAt != null ? _fmt(completedAt.toLocal()) : '—';
    final hasCompleted = completedAt != null;

    // Due date: computed UTC DateTime — use raw fields (UTC = calendar day)
    final dueStr = plannedDueDate != null ? _fmt(plannedDueDate!) : '—';

    final badgeColor =
        v != null ? const Color(0xFF3182CE) : AppColors.textSecondary;
    final badgeBg =
        v != null ? const Color(0xFFEBF8FF) : AppColors.border;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Visit header ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(6)),
                  child: Center(
                    child: Text(
                      '$visitNumber',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: badgeColor),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Visit #$visitNumber',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
                if (vendorName != null) ...[
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      vendorName!,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ] else
                  const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: statusColor),
                  ),
                ),
              ],
            ),
          ),

          // ── Three date columns ──────────────────────────────────────────────
          const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: _DatePill(
                    label: 'Due Date',
                    value: dueStr,
                    valueColor: const Color(0xFF2B6CB0),
                    labelColor: const Color(0xFF3182CE),
                    bg: const Color(0xFFEBF8FF),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _DatePill(
                    label: 'Scheduled',
                    value: scheduledStr,
                    valueColor: hasScheduled
                        ? const Color(0xFFDD6B20)
                        : AppColors.textSecondary,
                    labelColor: hasScheduled
                        ? const Color(0xFFDD6B20)
                        : AppColors.textSecondary,
                    bg: hasScheduled
                        ? const Color(0xFFFFF3E0)
                        : AppColors.background,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _DatePill(
                    label: 'Completed',
                    value: completedStr,
                    valueColor: hasCompleted
                        ? const Color(0xFF276749)
                        : AppColors.textSecondary,
                    labelColor: hasCompleted
                        ? const Color(0xFF276749)
                        : AppColors.textSecondary,
                    bg: hasCompleted
                        ? const Color(0xFFF0FFF4)
                        : AppColors.background,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (String, Color, Color) _statusMeta(String? status) => switch (status) {
        'completed' => (
          'Completed',
          const Color(0xFF276749),
          const Color(0xFFF0FFF4)
        ),
        'cancelled' => (
          'Cancelled',
          const Color(0xFFC53030),
          const Color(0xFFFFF5F5)
        ),
        'in_progress' || 'started' => (
          'In Progress',
          const Color(0xFF805AD5),
          const Color(0xFFFAF5FF)
        ),
        'awaiting_verification' => (
          'Awaiting OTP',
          const Color(0xFFDD6B20),
          const Color(0xFFFEEBC8)
        ),
        'assigned' || 'accepted' || 'en_route' => (
          'Scheduled',
          const Color(0xFF2C7A7B),
          const Color(0xFFE6FFFA)
        ),
        'pending' => (
          'Pending',
          const Color(0xFFDD6B20),
          const Color(0xFFFEEBC8)
        ),
        _ => ('Remaining', AppColors.textSecondary, AppColors.border),
      };
}

// ── Date pill ─────────────────────────────────────────────────────────────────

class _DatePill extends StatelessWidget {
  final String label;
  final String value;
  final Color labelColor;
  final Color valueColor;
  final Color bg;

  const _DatePill({
    required this.label,
    required this.value,
    required this.labelColor,
    required this.valueColor,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
            color: labelColor.withValues(alpha: 0.2), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              color: labelColor,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
