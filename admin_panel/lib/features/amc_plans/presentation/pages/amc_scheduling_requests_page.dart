import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart' show AppColors;
import '../../../bookings/application/providers/bookings_providers.dart';
import '../../../bookings/domain/models/booking.dart';
import '../../../bookings/presentation/widgets/booking_assignment_dialog.dart';

// ── Date helpers ──────────────────────────────────────────────────────────────

const _kMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _fmtDate(DateTime d) => '${d.day} ${_kMonths[d.month - 1]} ${d.year}';

String _fmtDateTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  final ampm = d.hour < 12 ? 'AM' : 'PM';
  return '${d.day} ${_kMonths[d.month - 1]} ${d.year} · $h:$m $ampm';
}

// ── Scheduling request model (list) ───────────────────────────────────────────

class _AmcSchedulingRequest {
  final String id;
  final String contractId;
  final String serviceName;
  final String planName;
  final String customerName;
  final String customerPhone;
  final DateTime requestedAt;
  final DateTime? preferredDate;
  final String? notes;
  final String status;

  const _AmcSchedulingRequest({
    required this.id,
    required this.contractId,
    required this.serviceName,
    required this.planName,
    required this.customerName,
    required this.customerPhone,
    required this.requestedAt,
    this.preferredDate,
    this.notes,
    required this.status,
  });

  bool get isPending => status == 'pending';

  factory _AmcSchedulingRequest.fromMap(Map<String, dynamic> m) {
    final contract = m['amc_contracts'] as Map<String, dynamic>? ?? {};
    final customer = m['customers'] as Map<String, dynamic>? ?? {};
    return _AmcSchedulingRequest(
      id: m['id'] as String,
      contractId: m['amc_contract_id'] as String? ?? '',
      serviceName: contract['service_name'] as String? ?? '—',
      planName: contract['plan_name'] as String? ?? '—',
      customerName: customer['full_name'] as String? ?? '—',
      customerPhone: customer['phone'] as String? ?? '—',
      requestedAt: DateTime.parse(m['requested_at'] as String),
      preferredDate: m['preferred_date'] != null
          ? DateTime.tryParse(m['preferred_date'] as String)
          : null,
      notes: m['notes'] as String?,
      status: m['status'] as String? ?? 'pending',
    );
  }
}

String _requestStatusLabel(String s) => switch (s) {
  'pending' => 'Pending',
  'scheduled' => 'Scheduled',
  'rejected' => 'Rejected',
  'cancelled' => 'Cancelled',
  _ => s,
};

(Color, Color) _requestStatusColors(String s) => switch (s) {
  'pending' => (AppColors.warning, AppColors.warning.withAlpha(20)),
  'scheduled' => (const Color(0xFF2C7A7B), const Color(0xFFE6FFFA)),
  'rejected' => (AppColors.error, AppColors.error.withAlpha(18)),
  'cancelled' => (AppColors.textSecondary, AppColors.border),
  _ => (AppColors.textSecondary, AppColors.border),
};

// ── Contract detail models (detail dialog) ────────────────────────────────────

class _AmcVisitDetail {
  final String id;
  final int? visitNumber;
  final String status;
  final DateTime? serviceDate;
  final String timeSlot;
  final String? vendorId;
  final DateTime? completedAt;

  const _AmcVisitDetail({
    required this.id,
    this.visitNumber,
    required this.status,
    this.serviceDate,
    required this.timeSlot,
    this.vendorId,
    this.completedAt,
  });

  factory _AmcVisitDetail.fromMap(Map<String, dynamic> m) => _AmcVisitDetail(
    id: m['id'] as String,
    visitNumber: (m['amc_visit_number'] as num?)?.toInt(),
    status: m['status'] as String? ?? 'pending',
    serviceDate: m['service_date'] != null
        ? DateTime.tryParse(m['service_date'] as String)
        : null,
    timeSlot: m['scheduled_time'] as String? ?? '',
    vendorId: m['vendor_id'] as String?,
    completedAt: m['otp_verified_at'] != null
        ? DateTime.tryParse(m['otp_verified_at'] as String)
        : null,
  );
}

class _AmcContractFull {
  final String id;
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
  final int quantity;
  final DateTime createdAt;
  final String? serviceInterval;
  final String? serviceAddress;
  final DateTime? nextVisitDate;
  final String? paymentType;
  final List<_AmcVisitDetail> visits;

  const _AmcContractFull({
    required this.id,
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
    this.quantity = 1,
    required this.createdAt,
    this.serviceInterval,
    this.serviceAddress,
    this.nextVisitDate,
    this.paymentType,
    this.visits = const [],
  });

  int get effectiveTotal => numVisits ?? totalVisits;
  int get completedCount => visits.where((v) => v.status == 'completed').length;
  int get remainingCount => (effectiveTotal - completedCount).clamp(0, 9999);

  DateTime? get lastServiceDate => visits
      .where((v) => v.status == 'completed' && v.completedAt != null)
      .map((v) => v.completedAt!)
      .fold<DateTime?>(
        null,
        (acc, d) => acc == null || d.isAfter(acc) ? d : acc,
      );

  DateTime? get nextScheduledDate {
    if (nextVisitDate != null) return nextVisitDate;
    final upcoming =
        visits
            .where(
              (v) =>
                  v.serviceDate != null &&
                  v.status != 'completed' &&
                  v.status != 'cancelled',
            )
            .map((v) => v.serviceDate!)
            .where(
              (d) =>
                  !d.isBefore(DateTime.now().subtract(const Duration(days: 1))),
            )
            .toList()
          ..sort();
    return upcoming.isEmpty ? null : upcoming.first;
  }

  factory _AmcContractFull.fromMap(
    Map<String, dynamic> m, {
    List<_AmcVisitDetail> visits = const [],
  }) => _AmcContractFull(
    id: m['id'] as String,
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
    quantity: (m['quantity'] as num?)?.toInt() ?? 1,
    createdAt: DateTime.parse(m['created_at'] as String),
    serviceInterval: m['service_interval'] as String?,
    serviceAddress: m['address'] as String?,
    nextVisitDate: m['next_visit_date'] != null
        ? DateTime.tryParse(m['next_visit_date'] as String)
        : null,
    paymentType: m['payment_type'] as String?,
    visits: visits,
  );
}

// ── Cancellation request model ────────────────────────────────────────────────

class _AmcCancellationRequest {
  final String id;
  final String contractId;
  final String customerId;
  final String serviceName;
  final String planName;
  final String customerName;
  final String customerPhone;
  final String? reason;
  final String? remarks;
  final String status;
  final String type; // 'visit' | 'membership'
  final String? bookingId;
  final int? visitNumber;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  const _AmcCancellationRequest({
    required this.id,
    required this.contractId,
    required this.customerId,
    required this.serviceName,
    required this.planName,
    required this.customerName,
    required this.customerPhone,
    this.reason,
    this.remarks,
    required this.status,
    required this.type,
    this.bookingId,
    this.visitNumber,
    required this.createdAt,
    this.resolvedAt,
  });

  bool get isPending => status == 'pending';
  bool get isVisit => type == 'visit';

  factory _AmcCancellationRequest.fromMap(Map<String, dynamic> m) {
    final contract = m['amc_contracts'] as Map<String, dynamic>? ?? {};
    final customer = m['customers'] as Map<String, dynamic>? ?? {};
    final booking = m['bookings'] as Map<String, dynamic>?;
    return _AmcCancellationRequest(
      id: m['id'] as String,
      contractId: m['contract_id'] as String? ?? '',
      customerId: m['customer_id'] as String? ?? '',
      serviceName: contract['service_name'] as String? ?? '—',
      planName: contract['plan_name'] as String? ?? '—',
      customerName: customer['full_name'] as String? ?? '—',
      customerPhone: customer['phone'] as String? ?? '—',
      reason: m['reason'] as String?,
      remarks: m['remarks'] as String?,
      status: m['status'] as String? ?? 'pending',
      type: m['type'] as String? ?? 'membership',
      bookingId: m['booking_id'] as String?,
      visitNumber: (booking?['amc_visit_number'] as num?)?.toInt(),
      createdAt: DateTime.parse(m['created_at'] as String),
      resolvedAt: m['resolved_at'] != null
          ? DateTime.tryParse(m['resolved_at'] as String)
          : null,
    );
  }
}

String _cancellationStatusLabel(String s) => switch (s) {
  'pending' => 'Pending',
  'approved' => 'Approved',
  'rejected' => 'Rejected',
  _ => s,
};

(Color, Color) _cancellationStatusColors(String s) => switch (s) {
  'pending' => (AppColors.warning, AppColors.warning.withAlpha(20)),
  'approved' => (AppColors.error, AppColors.error.withAlpha(18)),
  'rejected' => (AppColors.textSecondary, AppColors.border),
  _ => (AppColors.textSecondary, AppColors.border),
};

// ── Pause request model ───────────────────────────────────────────────────────

class _AmcPauseRequest {
  final String id;
  final String contractId;
  final String customerId;
  final String serviceName;
  final String planName;
  final String customerName;
  final String customerPhone;
  final String reason;
  final String status;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  const _AmcPauseRequest({
    required this.id,
    required this.contractId,
    required this.customerId,
    required this.serviceName,
    required this.planName,
    required this.customerName,
    required this.customerPhone,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
  });

  bool get isPending => status == 'pending';

  factory _AmcPauseRequest.fromMap(
    Map<String, dynamic> m, [
    Map<String, Map<String, dynamic>> customerMap = const {},
  ]) {
    final contract = m['amc_contracts'] as Map<String, dynamic>? ?? {};
    final customerId = m['customer_id'] as String? ?? '';
    final customer = customerMap[customerId] ?? <String, dynamic>{};
    return _AmcPauseRequest(
      id: m['id'] as String,
      contractId: m['amc_contract_id'] as String? ?? '',
      customerId: customerId,
      serviceName: contract['service_name'] as String? ?? '—',
      planName: contract['plan_name'] as String? ?? '—',
      customerName: customer['full_name'] as String? ?? '—',
      customerPhone: customer['phone'] as String? ?? '—',
      reason: m['reason'] as String? ?? '',
      status: m['status'] as String? ?? 'pending',
      createdAt: DateTime.parse(m['created_at'] as String),
      resolvedAt: m['resolved_at'] != null
          ? DateTime.tryParse(m['resolved_at'] as String)
          : null,
    );
  }
}

String _pauseStatusLabel(String s) => switch (s) {
  'pending' => 'Pending',
  'approved' => 'Approved',
  'rejected' => 'Rejected',
  'cancelled' => 'Cancelled',
  _ => s,
};

(Color, Color) _pauseStatusColors(String s) => switch (s) {
  'pending' => (AppColors.warning, AppColors.warning.withAlpha(20)),
  'approved' => (const Color(0xFF2C7A7B), const Color(0xFFE6FFFA)),
  'rejected' => (AppColors.textSecondary, AppColors.border),
  'cancelled' => (AppColors.textSecondary, AppColors.border),
  _ => (AppColors.textSecondary, AppColors.border),
};

// ── Providers ──────────────────────────────────────────────────────────────────

// statusFilter: 'pending' | 'scheduled' | 'rejected' | 'cancelled' | null (all)
final _amcRequestsProvider = FutureProvider.autoDispose
    .family<List<_AmcSchedulingRequest>, String?>((ref, statusFilter) async {
      final client = Supabase.instance.client;
      final base = client
          .from('amc_scheduling_requests')
          .select(
            'id, amc_contract_id, requested_at, preferred_date, notes, status, '
            'amc_contracts(service_name, plan_name), '
            'customers(full_name, phone)',
          );
      // Pending: oldest first (FIFO). Everything else: newest first.
      final rows = statusFilter != null
          ? await base
                .eq('status', statusFilter)
                .order('requested_at', ascending: statusFilter == 'pending')
          : await base.order('requested_at', ascending: false);
      return (rows as List)
          .map(
            (r) => _AmcSchedulingRequest.fromMap(
              Map<String, dynamic>.from(r as Map),
            ),
          )
          .toList();
    });

final _amcContractDetailProvider = FutureProvider.autoDispose
    .family<_AmcContractFull?, String>((ref, contractId) async {
      final client = Supabase.instance.client;

      final raw = await client
          .from('amc_contracts')
          .select(
            'id, service_name, plan_name, recurrence_interval, price_per_visit, '
            'status, total_visits, num_visits, original_total, discount_type, '
            'discount_value, discount_amount, final_price, quantity, created_at, address, '
            'service_interval, next_visit_date, payment_type',
          )
          .eq('id', contractId)
          .maybeSingle();

      if (raw == null) return null;

      final visitsRaw = await client
          .from('bookings')
          .select(
            'id, amc_visit_number, status, service_date, scheduled_time, vendor_id, otp_verified_at',
          )
          .eq('amc_contract_id', contractId)
          .order('amc_visit_number', ascending: true, nullsFirst: false)
          .order('created_at', ascending: true);

      final visits = (visitsRaw as List)
          .map(
            (v) => _AmcVisitDetail.fromMap(Map<String, dynamic>.from(v as Map)),
          )
          .toList();

      return _AmcContractFull.fromMap(
        Map<String, dynamic>.from(raw as Map),
        visits: visits,
      );
    });

// statusFilter: 'pending' | 'approved' | 'rejected' | null (all)
final _amcCancellationRequestsProvider = FutureProvider.autoDispose
    .family<List<_AmcCancellationRequest>, String?>((ref, statusFilter) async {
      final client = Supabase.instance.client;
      final base = client
          .from('amc_cancellation_requests')
          .select(
            'id, contract_id, customer_id, reason, remarks, status, type, booking_id, '
            'created_at, resolved_at, '
            'amc_contracts(service_name, plan_name), '
            'customers(full_name, phone), '
            'bookings!booking_id(amc_visit_number)',
          );
      final rows = statusFilter != null
          ? await base
                .eq('status', statusFilter)
                .order('created_at', ascending: statusFilter == 'pending')
          : await base.order('created_at', ascending: false);
      return (rows as List)
          .map(
            (r) => _AmcCancellationRequest.fromMap(
              Map<String, dynamic>.from(r as Map),
            ),
          )
          .toList();
    });

// statusFilter: 'pending' | 'approved' | 'rejected' | 'cancelled' | null (all)
final _amcPauseRequestsProvider = FutureProvider.autoDispose
    .family<List<_AmcPauseRequest>, String?>((ref, statusFilter) async {
      final client = Supabase.instance.client;

      final base = client.from('amc_pause_requests').select(
        'id, amc_contract_id, customer_id, reason, status, created_at, '
        'resolved_at, amc_contracts(service_name, plan_name)',
      );
      final raw = statusFilter != null
          ? await base
                .eq('status', statusFilter)
                .order('created_at', ascending: statusFilter == 'pending')
          : await base.order('created_at', ascending: false);

      final rows = raw as List;
      if (rows.isEmpty) return [];

      // customer_id is TEXT with no FK → batch-fetch customer rows separately.
      final ids = rows
          .map((r) => (r as Map)['customer_id'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
      final Map<String, Map<String, dynamic>> customerMap;
      if (ids.isNotEmpty) {
        final cRows = await client
            .from('customers')
            .select('id, full_name, phone')
            .inFilter('id', ids);
        customerMap = {
          for (final c in cRows as List)
            (c as Map<String, dynamic>)['id'] as String:
                Map<String, dynamic>.from(c as Map),
        };
      } else {
        customerMap = {};
      }

      final result = rows
          .map(
            (r) => _AmcPauseRequest.fromMap(
              Map<String, dynamic>.from(r as Map),
              customerMap,
            ),
          )
          .toList();
      return result;
    });

// ── Resume request model ──────────────────────────────────────────────────────

class _AmcResumeRequest {
  final String id;
  final String contractId;
  final String customerId;
  final String serviceName;
  final String planName;
  final String customerName;
  final String customerPhone;
  final String? reason;
  final String status;
  final DateTime?
  pauseStartDate; // from amc_contracts join — used to calc duration
  final int? pauseDurationDays;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  const _AmcResumeRequest({
    required this.id,
    required this.contractId,
    required this.customerId,
    required this.serviceName,
    required this.planName,
    required this.customerName,
    required this.customerPhone,
    this.reason,
    required this.status,
    this.pauseStartDate,
    this.pauseDurationDays,
    required this.createdAt,
    this.resolvedAt,
  });

  bool get isPending => status == 'pending';

  factory _AmcResumeRequest.fromMap(
    Map<String, dynamic> m, [
    Map<String, Map<String, dynamic>> customerMap = const {},
  ]) {
    final contract = m['amc_contracts'] as Map<String, dynamic>? ?? {};
    final customerId = m['customer_id'] as String? ?? '';
    final customer = customerMap[customerId] ?? <String, dynamic>{};
    return _AmcResumeRequest(
      id: m['id'] as String,
      contractId: m['amc_contract_id'] as String? ?? '',
      customerId: customerId,
      serviceName: contract['service_name'] as String? ?? '—',
      planName: contract['plan_name'] as String? ?? '—',
      customerName: customer['full_name'] as String? ?? '—',
      customerPhone: customer['phone'] as String? ?? '—',
      reason: m['reason'] as String?,
      status: m['status'] as String? ?? 'pending',
      pauseStartDate: contract['pause_started_at'] != null
          ? DateTime.tryParse(contract['pause_started_at'] as String)
          : null,
      pauseDurationDays: (m['pause_duration_days'] as num?)?.toInt(),
      createdAt: DateTime.parse(m['created_at'] as String),
      resolvedAt: m['resolved_at'] != null
          ? DateTime.tryParse(m['resolved_at'] as String)
          : null,
    );
  }
}

// statusFilter: 'pending' | 'approved' | 'rejected' | 'cancelled' | null (all)
final _amcResumeRequestsProvider = FutureProvider.autoDispose
    .family<List<_AmcResumeRequest>, String?>((ref, statusFilter) async {
      final client = Supabase.instance.client;
      final base = client.from('amc_resume_requests').select(
        'id, amc_contract_id, customer_id, reason, status, pause_duration_days, '
        'created_at, resolved_at, '
        'amc_contracts(service_name, plan_name, pause_started_at)',
      );
      final raw = statusFilter != null
          ? await base
                .eq('status', statusFilter)
                .order('created_at', ascending: statusFilter == 'pending')
          : await base.order('created_at', ascending: false);

      final rows = raw as List;
      if (rows.isEmpty) return [];

      final ids = rows
          .map((r) => (r as Map)['customer_id'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
      final Map<String, Map<String, dynamic>> customerMap;
      if (ids.isNotEmpty) {
        final cRows = await client
            .from('customers')
            .select('id, full_name, phone')
            .inFilter('id', ids);
        customerMap = {
          for (final c in cRows as List)
            (c as Map<String, dynamic>)['id'] as String:
                Map<String, dynamic>.from(c as Map),
        };
      } else {
        customerMap = {};
      }

      return rows
          .map(
            (r) => _AmcResumeRequest.fromMap(
              Map<String, dynamic>.from(r as Map),
              customerMap,
            ),
          )
          .toList();
    });

// ── Page ──────────────────────────────────────────────────────────────────────

class AmcSchedulingRequestsPage extends ConsumerStatefulWidget {
  const AmcSchedulingRequestsPage({super.key});

  @override
  ConsumerState<AmcSchedulingRequestsPage> createState() =>
      _AmcSchedulingRequestsPageState();
}

class _AmcSchedulingRequestsPageState
    extends ConsumerState<AmcSchedulingRequestsPage> {
  String? _schedulingFilter = 'pending';
  String? _cancellationFilter = 'pending';
  String? _pauseFilter = 'pending';
  String? _resumeFilter = 'pending';
  String _pauseTabType = 'pause'; // 'pause' | 'resume'

  void _refreshAll() {
    ref.invalidate(_amcRequestsProvider);
    ref.invalidate(_amcCancellationRequestsProvider);
    ref.invalidate(_amcPauseRequestsProvider);
    ref.invalidate(_amcResumeRequestsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final schedulingAsync = ref.watch(_amcRequestsProvider(_schedulingFilter));
    final cancellationAsync = ref.watch(
      _amcCancellationRequestsProvider(_cancellationFilter),
    );
    final pauseAsync = ref.watch(_amcPauseRequestsProvider(_pauseFilter));
    final resumeAsync = ref.watch(_amcResumeRequestsProvider(_resumeFilter));

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AMC Requests',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Visit scheduling, cancellation, and pause requests.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton.outlined(
                    onPressed: _refreshAll,
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Tab bar ───────────────────────────────────────────────────────
            const TabBar(
              tabAlignment: TabAlignment.start,
              isScrollable: true,
              padding: EdgeInsets.symmetric(horizontal: 24),
              tabs: [
                Tab(text: 'Scheduling Requests'),
                Tab(text: 'Cancellation Requests'),
                Tab(text: 'Pause Requests'),
              ],
            ),

            const Divider(height: 1),

            // ── Tab content ───────────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                children: [
                  // ── Tab 1: Scheduling Requests ──────────────────────────────
                  Column(
                    children: [
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          children: [
                            _StatusFilterChip(
                              label: 'Pending',
                              selected: _schedulingFilter == 'pending',
                              color: AppColors.warning,
                              onTap: () =>
                                  setState(() => _schedulingFilter = 'pending'),
                            ),
                            const SizedBox(width: 8),
                            _StatusFilterChip(
                              label: 'Scheduled',
                              selected: _schedulingFilter == 'scheduled',
                              color: const Color(0xFF2C7A7B),
                              onTap: () => setState(
                                () => _schedulingFilter = 'scheduled',
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusFilterChip(
                              label: 'Rejected',
                              selected: _schedulingFilter == 'rejected',
                              color: AppColors.error,
                              onTap: () => setState(
                                () => _schedulingFilter = 'rejected',
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusFilterChip(
                              label: 'Cancelled',
                              selected: _schedulingFilter == 'cancelled',
                              color: AppColors.textSecondary,
                              onTap: () => setState(
                                () => _schedulingFilter = 'cancelled',
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusFilterChip(
                              label: 'All',
                              selected: _schedulingFilter == null,
                              color: AppColors.primary,
                              onTap: () =>
                                  setState(() => _schedulingFilter = null),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: schedulingAsync.when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  size: 48,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 12),
                                Text('Failed to load: $e'),
                                const SizedBox(height: 16),
                                FilledButton(
                                  onPressed: () =>
                                      ref.invalidate(_amcRequestsProvider),
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                          data: (requests) {
                            if (requests.isEmpty) {
                              return _EmptyState(
                                statusFilter: _schedulingFilter,
                              );
                            }
                            return ListView.separated(
                              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                              itemCount: requests.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, i) => _RequestCard(
                                request: requests[i],
                                onRefresh: () =>
                                    ref.invalidate(_amcRequestsProvider),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),

                  // ── Tab 2: Cancellation Requests ────────────────────────────
                  Column(
                    children: [
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          children: [
                            _StatusFilterChip(
                              label: 'Pending',
                              selected: _cancellationFilter == 'pending',
                              color: AppColors.warning,
                              onTap: () => setState(
                                () => _cancellationFilter = 'pending',
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusFilterChip(
                              label: 'Approved',
                              selected: _cancellationFilter == 'approved',
                              color: AppColors.error,
                              onTap: () => setState(
                                () => _cancellationFilter = 'approved',
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusFilterChip(
                              label: 'Rejected',
                              selected: _cancellationFilter == 'rejected',
                              color: AppColors.textSecondary,
                              onTap: () => setState(
                                () => _cancellationFilter = 'rejected',
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusFilterChip(
                              label: 'All',
                              selected: _cancellationFilter == null,
                              color: AppColors.primary,
                              onTap: () =>
                                  setState(() => _cancellationFilter = null),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: cancellationAsync.when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  size: 48,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 12),
                                Text('Failed to load: $e'),
                                const SizedBox(height: 16),
                                FilledButton(
                                  onPressed: () => ref.invalidate(
                                    _amcCancellationRequestsProvider,
                                  ),
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                          data: (requests) {
                            if (requests.isEmpty) {
                              return _CancellationEmptyState(
                                filter: _cancellationFilter,
                              );
                            }
                            return ListView.separated(
                              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                              itemCount: requests.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, i) => _CancellationRequestCard(
                                request: requests[i],
                                onRefresh: () {
                                  ref.invalidate(
                                    _amcCancellationRequestsProvider,
                                  );
                                  ref
                                      .read(bookingsNotifierProvider.notifier)
                                      .refresh();
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),

                  // ── Tab 3: Pause / Resume ─────────────────────────────────
                  Column(
                    children: [
                      const SizedBox(height: 12),
                      // ── Sub-type toggle ───────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          children: [
                            _TypeToggleButton(
                              label: 'Pause Requests',
                              icon: Icons.pause_circle_outline_rounded,
                              selected: _pauseTabType == 'pause',
                              onTap: () =>
                                  setState(() => _pauseTabType = 'pause'),
                            ),
                            const SizedBox(width: 8),
                            _TypeToggleButton(
                              label: 'Resume Requests',
                              icon: Icons.play_circle_outline_rounded,
                              selected: _pauseTabType == 'resume',
                              onTap: () =>
                                  setState(() => _pauseTabType = 'resume'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      // ── Status filter chips ───────────────────────────────
                      if (_pauseTabType == 'pause')
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            children: [
                              _StatusFilterChip(
                                label: 'Pending',
                                selected: _pauseFilter == 'pending',
                                color: AppColors.warning,
                                onTap: () =>
                                    setState(() => _pauseFilter = 'pending'),
                              ),
                              const SizedBox(width: 8),
                              _StatusFilterChip(
                                label: 'Approved',
                                selected: _pauseFilter == 'approved',
                                color: const Color(0xFF2C7A7B),
                                onTap: () =>
                                    setState(() => _pauseFilter = 'approved'),
                              ),
                              const SizedBox(width: 8),
                              _StatusFilterChip(
                                label: 'Rejected',
                                selected: _pauseFilter == 'rejected',
                                color: AppColors.textSecondary,
                                onTap: () =>
                                    setState(() => _pauseFilter = 'rejected'),
                              ),
                              const SizedBox(width: 8),
                              _StatusFilterChip(
                                label: 'Cancelled',
                                selected: _pauseFilter == 'cancelled',
                                color: AppColors.textSecondary,
                                onTap: () =>
                                    setState(() => _pauseFilter = 'cancelled'),
                              ),
                              const SizedBox(width: 8),
                              _StatusFilterChip(
                                label: 'All',
                                selected: _pauseFilter == null,
                                color: AppColors.primary,
                                onTap: () =>
                                    setState(() => _pauseFilter = null),
                              ),
                            ],
                          ),
                        )
                      else
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            children: [
                              _StatusFilterChip(
                                label: 'Pending',
                                selected: _resumeFilter == 'pending',
                                color: AppColors.warning,
                                onTap: () =>
                                    setState(() => _resumeFilter = 'pending'),
                              ),
                              const SizedBox(width: 8),
                              _StatusFilterChip(
                                label: 'Approved',
                                selected: _resumeFilter == 'approved',
                                color: AppColors.success,
                                onTap: () =>
                                    setState(() => _resumeFilter = 'approved'),
                              ),
                              const SizedBox(width: 8),
                              _StatusFilterChip(
                                label: 'Rejected',
                                selected: _resumeFilter == 'rejected',
                                color: AppColors.textSecondary,
                                onTap: () =>
                                    setState(() => _resumeFilter = 'rejected'),
                              ),
                              const SizedBox(width: 8),
                              _StatusFilterChip(
                                label: 'Cancelled',
                                selected: _resumeFilter == 'cancelled',
                                color: AppColors.textSecondary,
                                onTap: () =>
                                    setState(() => _resumeFilter = 'cancelled'),
                              ),
                              const SizedBox(width: 8),
                              _StatusFilterChip(
                                label: 'All',
                                selected: _resumeFilter == null,
                                color: AppColors.primary,
                                onTap: () =>
                                    setState(() => _resumeFilter = null),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 12),
                      // ── Cards ─────────────────────────────────────────────
                      Expanded(
                        child: _pauseTabType == 'pause'
                            ? pauseAsync.when(
                                loading: () => const Center(
                                  child: CircularProgressIndicator(),
                                ),
                                error: (e, _) => Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        size: 48,
                                        color: Colors.grey,
                                      ),
                                      const SizedBox(height: 12),
                                      Text('Failed to load: $e'),
                                      const SizedBox(height: 16),
                                      FilledButton(
                                        onPressed: () => ref.invalidate(
                                          _amcPauseRequestsProvider,
                                        ),
                                        child: const Text('Retry'),
                                      ),
                                    ],
                                  ),
                                ),
                                data: (requests) {
                                  if (requests.isEmpty) {
                                    return _PauseEmptyState(
                                      filter: _pauseFilter,
                                      label: 'pause',
                                    );
                                  }
                                  return ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(
                                      24,
                                      8,
                                      24,
                                      32,
                                    ),
                                    itemCount: requests.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (_, i) => _PauseRequestCard(
                                      request: requests[i],
                                      onRefresh: () => ref.invalidate(
                                        _amcPauseRequestsProvider,
                                      ),
                                    ),
                                  );
                                },
                              )
                            : resumeAsync.when(
                                loading: () => const Center(
                                  child: CircularProgressIndicator(),
                                ),
                                error: (e, _) => Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        size: 48,
                                        color: Colors.grey,
                                      ),
                                      const SizedBox(height: 12),
                                      Text('Failed to load: $e'),
                                      const SizedBox(height: 16),
                                      FilledButton(
                                        onPressed: () => ref.invalidate(
                                          _amcResumeRequestsProvider,
                                        ),
                                        child: const Text('Retry'),
                                      ),
                                    ],
                                  ),
                                ),
                                data: (requests) {
                                  if (requests.isEmpty) {
                                    return _PauseEmptyState(
                                      filter: _resumeFilter,
                                      label: 'resume',
                                    );
                                  }
                                  return ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(
                                      24,
                                      8,
                                      24,
                                      32,
                                    ),
                                    itemCount: requests.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (_, i) => _ResumeRequestCard(
                                      request: requests[i],
                                      onRefresh: () {
                                        ref.invalidate(
                                          _amcResumeRequestsProvider,
                                        );
                                        ref.invalidate(
                                          _amcPauseRequestsProvider,
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Cancellation empty state ──────────────────────────────────────────────────

class _CancellationEmptyState extends StatelessWidget {
  final String? filter;
  const _CancellationEmptyState({this.filter});

  @override
  Widget build(BuildContext context) {
    final isPending = filter == 'pending';
    final title = isPending ? 'No pending requests' : 'No requests found';
    final sub = filter == null
        ? 'No AMC cancellation requests yet.'
        : 'No ${_cancellationStatusLabel(filter!).toLowerCase()} cancellation requests.';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.green.withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline_rounded,
              size: 36,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            sub,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Cancellation request card ─────────────────────────────────────────────────

class _CancellationRequestCard extends ConsumerStatefulWidget {
  final _AmcCancellationRequest request;
  final VoidCallback onRefresh;

  const _CancellationRequestCard({
    required this.request,
    required this.onRefresh,
  });

  @override
  ConsumerState<_CancellationRequestCard> createState() =>
      _CancellationRequestCardState();
}

class _CancellationRequestCardState
    extends ConsumerState<_CancellationRequestCard> {
  bool _approving = false;
  bool _rejecting = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final tt = Theme.of(context).textTheme;
    final (statusColor, statusBg) = _cancellationStatusColors(r.status);

    final typeColor = r.isVisit ? const Color(0xFF3182CE) : AppColors.error;
    final typeLabel = r.isVisit ? 'Visit Cancel' : 'Membership Cancel';
    final typeIcon = r.isVisit
        ? Icons.event_busy_rounded
        : Icons.cancel_outlined;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(typeIcon, size: 20, color: typeColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.serviceName,
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        r.planName,
                        style: tt.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.4),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        _cancellationStatusLabel(r.status),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: typeColor.withValues(alpha: 0.3),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        typeLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: typeColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),

            _InfoRow(Icons.person_rounded, 'Customer', r.customerName),
            _InfoRow(Icons.phone_rounded, 'Phone', r.customerPhone),
            if (r.isVisit)
              _InfoRow(
                Icons.event_busy_rounded,
                'Visit',
                r.visitNumber != null
                    ? 'Visit #${r.visitNumber}'
                    : 'Single visit',
              )
            else if (r.reason != null)
              _InfoRow(Icons.cancel_rounded, 'Reason', r.reason!),
            if (r.remarks != null && r.remarks!.isNotEmpty)
              _InfoRow(Icons.notes_rounded, 'Remarks', r.remarks!),
            _InfoRow(
              Icons.schedule_rounded,
              'Requested',
              _fmtDateTime(r.createdAt.toLocal()),
            ),
            if (r.resolvedAt != null)
              _InfoRow(
                Icons.check_circle_rounded,
                'Resolved',
                _fmtDateTime(r.resolvedAt!.toLocal()),
              ),

            if (r.isPending) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: (_rejecting || _approving) ? null : _reject,
                    icon: _rejecting
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          )
                        : const Icon(Icons.close_rounded, size: 15),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: (_approving || _rejecting) ? null : _approve,
                    icon: _approving
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 15),
                    label: Text(r.isVisit ? 'Approve' : 'Approve Cancel'),
                    style: FilledButton.styleFrom(
                      backgroundColor: r.isVisit
                          ? const Color(0xFF3182CE)
                          : AppColors.error,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _approve() async {
    final r = widget.request;
    final messenger = ScaffoldMessenger.of(context);

    final dialogTitle = r.isVisit
        ? 'Approve Visit Cancellation'
        : 'Approve Membership Cancellation';
    final dialogBody = r.isVisit
        ? 'Approve cancellation of ${r.visitNumber != null ? "Visit #${r.visitNumber}" : "this visit"} '
              'for "${r.planName}"?\n\n'
              'Only this visit will be cancelled. The AMC membership stays active.'
        : 'Approve full cancellation of "${r.planName}"?\n\n'
              'All pending and scheduled visits will be cancelled. '
              'This cannot be undone.';
    final confirmLabel = r.isVisit
        ? 'Approve Visit Cancel'
        : 'Approve Cancellation';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(dialogTitle),
        content: Text(dialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: r.isVisit
                  ? const Color(0xFF3182CE)
                  : AppColors.error,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _approving = true);
    try {
      final client = Supabase.instance.client;
      await client
          .from('amc_cancellation_requests')
          .update({
            'status': 'approved',
            'resolved_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', r.id);

      if (r.isVisit) {
        // Cancel only the specific visit booking
        if (r.bookingId != null) {
          await client
              .from('bookings')
              .update({'status': 'cancelled'})
              .eq('id', r.bookingId!);
        }
        if (r.customerId.isNotEmpty) {
          try {
            final visitLabel = r.visitNumber != null
                ? 'Visit #${r.visitNumber}'
                : 'Your visit';
            await client.from('notifications').insert({
              'user_type': 'customer',
              'user_id': r.customerId,
              'title': 'Visit Cancellation Approved',
              'message':
                  '$visitLabel of your "${r.planName}" AMC has been cancelled. '
                  'Your membership remains active.',
              'notification_type': 'amc_visit_cancellation_approved',
              'is_read': false,
              'entity_type': 'amc_contract',
              'entity_id': r.contractId,
            });
          } catch (_) {}
        }
        widget.onRefresh();
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                r.visitNumber != null
                    ? 'Visit #${r.visitNumber} cancelled. Membership stays active.'
                    : 'Visit cancelled. Membership stays active.',
              ),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } else {
        // Cancel the full contract + all pending visits + scheduling requests
        final updated = await client
            .from('amc_contracts')
            .update({
              'status': 'cancelled',
              if (r.reason != null) 'cancellation_reason': r.reason,
              if (r.remarks != null) 'cancellation_remarks': r.remarks,
              'cancellation_requested_at': r.createdAt
                  .toUtc()
                  .toIso8601String(),
            })
            .eq('id', r.contractId)
            .select('id');
        if ((updated as List).isEmpty) {
          throw Exception(
            'Contract update failed — apply pending database migrations.',
          );
        }
        await client
            .from('bookings')
            .update({'status': 'cancelled'})
            .eq('amc_contract_id', r.contractId)
            .inFilter('status', [
              'pending',
              'assigned',
              'assigned_to_dodo_team',
              'accepted',
            ]);
        await client
            .from('amc_scheduling_requests')
            .update({'status': 'cancelled'})
            .eq('amc_contract_id', r.contractId)
            .eq('status', 'pending');
        if (r.customerId.isNotEmpty) {
          try {
            await client.from('notifications').insert({
              'user_type': 'customer',
              'user_id': r.customerId,
              'title': 'AMC Cancellation Approved',
              'message':
                  'Your request to cancel the "${r.planName}" AMC contract has been approved. '
                  'Your membership is now cancelled.',
              'notification_type': 'amc_cancellation_approved',
              'is_read': false,
              'entity_type': 'amc_contract',
              'entity_id': r.contractId,
            });
          } catch (_) {}
        }
        widget.onRefresh();
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('AMC contract "${r.planName}" cancelled.'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _approving = false);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to approve: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _reject() async {
    final r = widget.request;
    final messenger = ScaffoldMessenger.of(context);

    final dialogTitle = r.isVisit
        ? 'Reject Visit Cancellation'
        : 'Reject Membership Cancellation';
    final dialogBody = r.isVisit
        ? 'Reject the visit cancellation request for "${r.planName}"?\n\n'
              'The visit remains as scheduled.'
        : 'Reject the cancellation request for "${r.planName}"?\n\n'
              'The contract will be restored to Active status.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(dialogTitle),
        content: Text(dialogBody),
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
      await client
          .from('amc_cancellation_requests')
          .update({
            'status': 'rejected',
            'resolved_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', r.id);

      if (!r.isVisit) {
        // Restore membership contract to active
        await client
            .from('amc_contracts')
            .update({
              'status': 'active',
              'cancellation_reason': null,
              'cancellation_remarks': null,
              'cancellation_requested_at': null,
            })
            .eq('id', r.contractId);
      }

      if (r.customerId.isNotEmpty) {
        try {
          final (title, message, notifType) = r.isVisit
              ? (
                  'Visit Cancellation Rejected',
                  'Your request to cancel ${r.visitNumber != null ? "Visit #${r.visitNumber}" : "a visit"} '
                      'of "${r.planName}" has been rejected. The visit remains as scheduled.',
                  'amc_visit_cancellation_rejected',
                )
              : (
                  'AMC Cancellation Rejected',
                  'Your request to cancel the "${r.planName}" AMC contract has been rejected. '
                      'Your membership remains active.',
                  'amc_cancellation_rejected',
                );
          await client.from('notifications').insert({
            'user_type': 'customer',
            'user_id': r.customerId,
            'title': title,
            'message': message,
            'notification_type': notifType,
            'is_read': false,
            'entity_type': 'amc_contract',
            'entity_id': r.contractId,
          });
        } catch (_) {}
      }
      widget.onRefresh();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              r.isVisit
                  ? 'Visit cancellation rejected — visit remains scheduled.'
                  : 'Cancellation rejected — membership restored to Active.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _rejecting = false);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to reject: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String? statusFilter;
  const _EmptyState({this.statusFilter});

  @override
  Widget build(BuildContext context) {
    final isPending = statusFilter == 'pending';
    final title = isPending ? 'All caught up!' : 'No requests found';
    final sub = statusFilter == null
        ? 'No AMC scheduling requests yet.'
        : 'No ${_requestStatusLabel(statusFilter!).toLowerCase()} AMC scheduling requests.';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.green.withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline_rounded,
              size: 36,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            sub,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Pause empty state ─────────────────────────────────────────────────────────

class _PauseEmptyState extends StatelessWidget {
  final String? filter;
  final String label; // 'pause' | 'resume'
  const _PauseEmptyState({this.filter, this.label = 'pause'});

  @override
  Widget build(BuildContext context) {
    final isPending = filter == 'pending';
    final title = isPending ? 'No pending requests' : 'No requests found';
    final sub = filter == null
        ? 'No AMC $label requests yet.'
        : 'No ${_pauseStatusLabel(filter!).toLowerCase()} $label requests.';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.green.withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline_rounded,
              size: 36,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            sub,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Pause request card ────────────────────────────────────────────────────────

class _PauseRequestCard extends ConsumerStatefulWidget {
  final _AmcPauseRequest request;
  final VoidCallback onRefresh;

  const _PauseRequestCard({required this.request, required this.onRefresh});

  @override
  ConsumerState<_PauseRequestCard> createState() => _PauseRequestCardState();
}

class _PauseRequestCardState extends ConsumerState<_PauseRequestCard> {
  bool _approving = false;
  bool _rejecting = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final tt = Theme.of(context).textTheme;
    final (statusColor, statusBg) = _pauseStatusColors(r.status);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.pause_circle_rounded,
                    size: 20,
                    color: AppColors.warning,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.serviceName,
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        r.planName,
                        style: tt.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.4),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    _pauseStatusLabel(r.status),
                    style: TextStyle(
                      fontSize: 10,
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

            _InfoRow(Icons.person_rounded, 'Customer', r.customerName),
            _InfoRow(Icons.phone_rounded, 'Phone', r.customerPhone),
            if (r.reason.isNotEmpty)
              _InfoRow(Icons.notes_rounded, 'Reason', r.reason),
            _InfoRow(
              Icons.schedule_rounded,
              'Requested',
              _fmtDateTime(r.createdAt.toLocal()),
            ),
            if (r.resolvedAt != null)
              _InfoRow(
                Icons.check_circle_rounded,
                'Resolved',
                _fmtDateTime(r.resolvedAt!.toLocal()),
              ),

            if (r.isPending) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: (_rejecting || _approving) ? null : _reject,
                    icon: _rejecting
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          )
                        : const Icon(Icons.close_rounded, size: 15),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: (_approving || _rejecting) ? null : _approve,
                    icon: _approving
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.pause_rounded, size: 15),
                    label: const Text('Approve Pause'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.warning,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _approve() async {
    final r = widget.request;
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Approve Pause Request'),
        content: Text(
          'Approve pausing "${r.planName}"?\n\n'
          'Scheduling will be disabled until the customer submits a '
          'resume request and admin approves it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
            child: const Text('Approve Pause'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _approving = true);
    try {
      final client = Supabase.instance.client;
      final now = DateTime.now().toUtc().toIso8601String();

      await client
          .from('amc_pause_requests')
          .update({'status': 'approved', 'resolved_at': now})
          .eq('id', r.id);

      await client
          .from('amc_contracts')
          .update({'status': 'paused', 'pause_started_at': now})
          .eq('id', r.contractId);

      if (r.customerId.isNotEmpty) {
        try {
          await client.from('notifications').insert({
            'user_type': 'customer',
            'user_id': r.customerId,
            'title': 'AMC Pause Approved',
            'message':
                'Your pause request for "${r.planName}" has been approved. '
                'Your membership is now paused. '
                'Request a resume when you are ready to continue.',
            'notification_type': 'amc_pause_approved',
            'is_read': false,
            'entity_type': 'amc_contract',
            'entity_id': r.contractId,
          });
        } catch (_) {}
      }
      widget.onRefresh();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('"${r.planName}" paused successfully.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _approving = false);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to approve: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _reject() async {
    final r = widget.request;
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Reject Pause Request'),
        content: Text(
          'Reject the pause request for "${r.planName}"?\n\n'
          'The membership will remain active.',
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
      await client
          .from('amc_pause_requests')
          .update({
            'status': 'rejected',
            'resolved_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', r.id);

      if (r.customerId.isNotEmpty) {
        try {
          await client.from('notifications').insert({
            'user_type': 'customer',
            'user_id': r.customerId,
            'title': 'AMC Pause Request Rejected',
            'message':
                'Your pause request for "${r.planName}" has been rejected. '
                'Your membership remains active.',
            'notification_type': 'amc_pause_rejected',
            'is_read': false,
            'entity_type': 'amc_contract',
            'entity_id': r.contractId,
          });
        } catch (_) {}
      }
      widget.onRefresh();
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Pause request rejected — membership remains active.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _rejecting = false);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to reject: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

// ── Resume request card ───────────────────────────────────────────────────────

class _ResumeRequestCard extends ConsumerStatefulWidget {
  final _AmcResumeRequest request;
  final VoidCallback onRefresh;

  const _ResumeRequestCard({required this.request, required this.onRefresh});

  @override
  ConsumerState<_ResumeRequestCard> createState() => _ResumeRequestCardState();
}

class _ResumeRequestCardState extends ConsumerState<_ResumeRequestCard> {
  bool _approving = false;
  bool _rejecting = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final tt = Theme.of(context).textTheme;
    final (statusColor, statusBg) = _pauseStatusColors(r.status);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.play_circle_rounded,
                    size: 20,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.serviceName,
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        r.planName,
                        style: tt.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.4),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    _pauseStatusLabel(r.status),
                    style: TextStyle(
                      fontSize: 10,
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

            _InfoRow(Icons.person_rounded, 'Customer', r.customerName),
            _InfoRow(Icons.phone_rounded, 'Phone', r.customerPhone),
            if (r.pauseStartDate != null)
              _InfoRow(
                Icons.pause_rounded,
                'Paused Since',
                _fmtDate(r.pauseStartDate!.toLocal()),
              ),
            if (r.pauseDurationDays != null && r.pauseDurationDays! > 0)
              _InfoRow(
                Icons.timer_rounded,
                'Pause Duration',
                '${r.pauseDurationDays} day${r.pauseDurationDays == 1 ? '' : 's'}',
              ),
            if (r.reason != null && r.reason!.isNotEmpty)
              _InfoRow(Icons.notes_rounded, 'Reason', r.reason!),
            _InfoRow(
              Icons.schedule_rounded,
              'Requested',
              _fmtDateTime(r.createdAt.toLocal()),
            ),
            if (r.resolvedAt != null)
              _InfoRow(
                Icons.check_circle_rounded,
                'Resolved',
                _fmtDateTime(r.resolvedAt!.toLocal()),
              ),

            if (r.isPending) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: (_rejecting || _approving) ? null : _reject,
                    icon: _rejecting
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          )
                        : const Icon(Icons.close_rounded, size: 15),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: (_approving || _rejecting) ? null : _approve,
                    icon: _approving
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.play_arrow_rounded, size: 15),
                    label: const Text('Approve Resume'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _approve() async {
    final r = widget.request;
    final messenger = ScaffoldMessenger.of(context);

    final pausedSince = r.pauseStartDate != null
        ? ' (paused since ${_fmtDate(r.pauseStartDate!.toLocal())})'
        : '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Approve Resume Request'),
        content: Text(
          'Resume "${r.planName}"$pausedSince?\n\n'
          'The membership will be set to Active and all upcoming visit '
          'due dates will be shifted forward by the pause duration.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.success),
            child: const Text('Approve Resume'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _approving = true);
    try {
      final client = Supabase.instance.client;
      final today = DateTime.now();
      final nowUtc = today.toUtc().toIso8601String();

      // Compute pause duration and shift planned_due_dates
      int pauseDays = 0;
      final pauseStart = r.pauseStartDate;
      if (pauseStart != null) {
        pauseDays = today.difference(pauseStart).inDays;
        if (pauseDays > 0) {
          final futureBookings = await client
              .from('bookings')
              .select('id, planned_due_date')
              .eq('amc_contract_id', r.contractId)
              .inFilter('status', [
                'pending',
                'assigned',
                'assigned_to_dodo_team',
                'accepted',
              ]);
          for (final b in futureBookings as List) {
            final pdRaw = b['planned_due_date'] as String?;
            if (pdRaw == null) continue;
            final pd = DateTime.tryParse(pdRaw);
            if (pd == null) continue;
            final shifted = pd.add(Duration(days: pauseDays));
            await client
                .from('bookings')
                .update({
                  'planned_due_date':
                      '${shifted.year.toString().padLeft(4, '0')}-'
                      '${shifted.month.toString().padLeft(2, '0')}-'
                      '${shifted.day.toString().padLeft(2, '0')}',
                })
                .eq('id', b['id'] as String);
          }
        }
      }

      await client
          .from('amc_resume_requests')
          .update({
            'status': 'approved',
            'pause_duration_days': pauseDays,
            'resolved_at': nowUtc,
          })
          .eq('id', r.id);

      await client
          .from('amc_contracts')
          .update({
            'status': 'active',
            'pause_started_at': null,
            'resumed_at': nowUtc,
          })
          .eq('id', r.contractId);

      if (r.customerId.isNotEmpty) {
        try {
          await client.from('notifications').insert({
            'user_type': 'customer',
            'user_id': r.customerId,
            'title': 'AMC Membership Resumed',
            'message':
                'Your "${r.planName}" AMC membership has been resumed. '
                'You can now request your next visit.',
            'notification_type': 'amc_resumed',
            'is_read': false,
            'entity_type': 'amc_contract',
            'entity_id': r.contractId,
          });
        } catch (_) {}
      }
      widget.onRefresh();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '"${r.planName}" resumed. '
              '${pauseDays > 0 ? 'Visit dates shifted by $pauseDays day${pauseDays == 1 ? '' : 's'}.' : ''}',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _approving = false);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to approve: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _reject() async {
    final r = widget.request;
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Reject Resume Request'),
        content: Text(
          'Reject the resume request for "${r.planName}"?\n\n'
          'The membership will remain paused.',
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
      await client
          .from('amc_resume_requests')
          .update({
            'status': 'rejected',
            'resolved_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', r.id);

      if (r.customerId.isNotEmpty) {
        try {
          await client.from('notifications').insert({
            'user_type': 'customer',
            'user_id': r.customerId,
            'title': 'AMC Resume Request Rejected',
            'message':
                'Your resume request for "${r.planName}" has been rejected. '
                'Your membership remains paused.',
            'notification_type': 'amc_resume_rejected',
            'is_read': false,
            'entity_type': 'amc_contract',
            'entity_id': r.contractId,
          });
        } catch (_) {}
      }
      widget.onRefresh();
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Resume request rejected — membership remains paused.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _rejecting = false);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to reject: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

// ── Request card (compact list item) ──────────────────────────────────────────

class _RequestCard extends ConsumerStatefulWidget {
  final _AmcSchedulingRequest request;
  final VoidCallback onRefresh;

  const _RequestCard({required this.request, required this.onRefresh});

  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard> {
  bool _approving = false;
  bool _rejecting = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final tt = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.blue.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.autorenew_rounded,
                    size: 20,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.serviceName,
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        r.planName,
                        style: tt.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                _RequestStatusBadge(status: r.status),
              ],
            ),

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // ── Key info ───────────────────────────────────────────────────
            _InfoRow(Icons.person_rounded, 'Customer', r.customerName),
            _InfoRow(Icons.phone_rounded, 'Phone', r.customerPhone),
            _InfoRow(
              Icons.schedule_rounded,
              'Requested',
              _fmtDateTime(r.requestedAt.toLocal()),
            ),
            if (r.preferredDate != null)
              _InfoRow(
                Icons.event_available_rounded,
                'Preferred Date',
                _fmtDate(r.preferredDate!),
              ),
            if (r.notes != null && r.notes!.isNotEmpty)
              _InfoRow(Icons.notes_rounded, 'Notes', r.notes!),

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // ── Actions ────────────────────────────────────────────────────
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _openDetails(),
                  icon: const Icon(Icons.open_in_new_rounded, size: 14),
                  label: const Text('View Details'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                ),
                if (r.isPending) ...[
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: (_rejecting || _approving) ? null : _reject,
                    icon: _rejecting
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          )
                        : const Icon(Icons.close_rounded, size: 15),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: (_approving || _rejecting) ? null : _approve,
                    icon: _approving
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.calendar_month_rounded, size: 15),
                    label: const Text('Approve & Schedule'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openDetails() {
    showDialog(
      context: context,
      builder: (_) => _AmcRequestDetailDialog(
        request: widget.request,
        onRefresh: widget.onRefresh,
      ),
    );
  }

  Future<void> _reject() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Reject Request'),
        content: const Text(
          'Reject this scheduling request? '
          'The customer will be able to submit a new request.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _rejecting = true);
    try {
      await Supabase.instance.client
          .from('amc_scheduling_requests')
          .update({'status': 'rejected'})
          .eq('id', widget.request.id);
      if (mounted) widget.onRefresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reject: $e'),
            backgroundColor: AppColors.error,
          ),
        );
        setState(() => _rejecting = false);
      }
    }
  }

  Future<void> _approve() async {
    setState(() => _approving = true);
    try {
      // Guard: block scheduling while contract is paused
      final contractRow = await Supabase.instance.client
          .from('amc_contracts')
          .select('status')
          .eq('id', widget.request.contractId)
          .single();
      if ((contractRow['status'] as String?) == 'paused') {
        if (mounted) {
          setState(() => _approving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Cannot schedule: this AMC membership is currently paused.',
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }
      final rows = await Supabase.instance.client
          .from('bookings')
          .select()
          .eq('amc_contract_id', widget.request.contractId)
          .inFilter('status', ['pending', 'assigned'])
          .isFilter('service_date', null)
          .order('created_at', ascending: false)
          .limit(1);

      if (!mounted) return;
      setState(() => _approving = false);

      if ((rows as List).isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No unscheduled visit found. '
              'The visit may already have a date assigned.',
            ),
          ),
        );
        return;
      }

      final booking = Booking.fromMap(
        Map<String, dynamic>.from(rows.first as Map),
      );
      final requestId = widget.request.id;

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => BookingAssignmentDialog(
          booking: booking,
          preferredDate: widget.request.preferredDate,
          onSave:
              ({
                required assignmentType,
                vendorId,
                dodoTeamId,
                required serviceDate,
                notes,
              }) async {
                await ref
                    .read(bookingsNotifierProvider.notifier)
                    .updateBookingAssignment(
                      booking.id,
                      assignmentType: assignmentType,
                      vendorId: vendorId,
                      dodoTeamId: dodoTeamId,
                      serviceDate: serviceDate,
                      notes: notes,
                    );
                await Supabase.instance.client
                    .from('amc_scheduling_requests')
                    .update({'status': 'scheduled'})
                    .eq('id', requestId);
                widget.onRefresh();
              },
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _approving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

// ── AMC Request Detail Dialog ──────────────────────────────────────────────────

class _AmcRequestDetailDialog extends ConsumerStatefulWidget {
  final _AmcSchedulingRequest request;
  final VoidCallback onRefresh;

  const _AmcRequestDetailDialog({
    required this.request,
    required this.onRefresh,
  });

  @override
  ConsumerState<_AmcRequestDetailDialog> createState() =>
      _AmcRequestDetailDialogState();
}

class _AmcRequestDetailDialogState
    extends ConsumerState<_AmcRequestDetailDialog> {
  bool _approving = false;
  bool _rejecting = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        ref.invalidate(_amcContractDetailProvider(widget.request.contractId));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final contractAsync = ref.watch(_amcContractDetailProvider(r.contractId));

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 660, maxHeight: 780),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Dialog header ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.schedule_send_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AMC Scheduling Request',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${r.serviceName} · ${r.planName}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(30),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _requestStatusLabel(r.status),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // ── Body ──────────────────────────────────────────────────────
            Flexible(
              child: contractAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Error loading contract: $e'),
                  ),
                ),
                data: (contract) => SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Request Info
                      _DetailSection(
                        title: 'REQUEST',
                        icon: Icons.inbox_rounded,
                        children: [
                          if (r.preferredDate != null)
                            _DetailRow(
                              icon: Icons.event_available_rounded,
                              label: 'Preferred Date',
                              value: _fmtDate(r.preferredDate!),
                              highlight: true,
                            ),
                          _DetailRow(
                            icon: Icons.schedule_rounded,
                            label: 'Requested On',
                            value: _fmtDateTime(r.requestedAt.toLocal()),
                          ),
                          if (r.notes != null && r.notes!.isNotEmpty)
                            _DetailRow(
                              icon: Icons.chat_bubble_outline_rounded,
                              label: 'Customer Message',
                              value: r.notes!,
                            ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // Customer Info
                      _DetailSection(
                        title: 'CUSTOMER',
                        icon: Icons.person_rounded,
                        children: [
                          _DetailRow(
                            icon: Icons.badge_rounded,
                            label: 'Name',
                            value: r.customerName,
                          ),
                          _DetailRow(
                            icon: Icons.phone_rounded,
                            label: 'Phone',
                            value: r.customerPhone,
                          ),
                          if (contract?.serviceAddress != null &&
                              contract!.serviceAddress!.isNotEmpty)
                            _DetailRow(
                              icon: Icons.location_on_rounded,
                              label: 'Service Address',
                              value: contract.serviceAddress!,
                            ),
                        ],
                      ),

                      if (contract != null) ...[
                        const SizedBox(height: 14),

                        // AMC Contract Info
                        _DetailSection(
                          title: 'AMC CONTRACT',
                          icon: Icons.autorenew_rounded,
                          children: [
                            _DetailRow(
                              icon: Icons.tag_rounded,
                              label: 'Contract #',
                              value: contract.id.length > 8
                                  ? contract.id.substring(0, 8).toUpperCase()
                                  : contract.id.toUpperCase(),
                            ),
                            _DetailRow(
                              icon: Icons.circle_rounded,
                              label: 'Status',
                              value: _contractStatusLabel(contract.status),
                              valueColor: _contractStatusColor(contract.status),
                            ),
                            _DetailRow(
                              icon: Icons.calendar_today_rounded,
                              label: 'Start Date',
                              value: _fmtDate(contract.createdAt.toLocal()),
                            ),
                            _DetailRow(
                              icon: Icons.checklist_rounded,
                              label: 'Progress',
                              value:
                                  '${contract.completedCount} of ${contract.effectiveTotal} visits completed',
                            ),
                            _DetailRow(
                              icon: Icons.pending_actions_rounded,
                              label: 'Remaining Visits',
                              value: '${contract.remainingCount}',
                              valueColor: contract.remainingCount > 0
                                  ? AppColors.warning
                                  : AppColors.textSecondary,
                            ),
                            if (contract.lastServiceDate != null)
                              _DetailRow(
                                icon: Icons.history_rounded,
                                label: 'Last Service Date',
                                value: _fmtDate(
                                  contract.lastServiceDate!.toLocal(),
                                ),
                              ),
                            if (contract.nextScheduledDate != null)
                              _DetailRow(
                                icon: Icons.event_rounded,
                                label: 'Next Scheduled Visit',
                                value: _fmtDate(
                                  contract.nextScheduledDate!.toLocal(),
                                ),
                                highlight: true,
                              ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // Plan Info
                        _DetailSection(
                          title: 'PLAN',
                          icon: Icons.description_rounded,
                          children: [
                            _DetailRow(
                              icon: Icons.home_repair_service_rounded,
                              label: 'Service',
                              value: contract.serviceName,
                            ),
                            _DetailRow(
                              icon: Icons.workspace_premium_rounded,
                              label: 'Plan Name',
                              value: contract.planName,
                            ),
                            if (contract.recurrenceInterval.isNotEmpty)
                              _DetailRow(
                                icon: Icons.repeat_rounded,
                                label: 'Interval',
                                value: contract.recurrenceInterval,
                              ),
                            _DetailRow(
                              icon: Icons.numbers_rounded,
                              label: 'Total Visits',
                              value: '${contract.effectiveTotal}',
                            ),
                            if (contract.quantity > 1)
                              _DetailRow(
                                icon: Icons.devices_rounded,
                                label: 'Units Covered',
                                value: '${contract.quantity}',
                              ),
                            if (contract.finalPrice != null &&
                                contract.finalPrice! > 0)
                              _DetailRow(
                                icon: Icons.currency_rupee_rounded,
                                label: 'Contract Value',
                                value:
                                    '₹${contract.finalPrice!.toStringAsFixed(2)}',
                              )
                            else if (contract.originalTotal != null &&
                                contract.originalTotal! > 0)
                              _DetailRow(
                                icon: Icons.currency_rupee_rounded,
                                label: 'Contract Value',
                                value:
                                    '₹${contract.originalTotal!.toStringAsFixed(2)}',
                              ),
                            if (contract.discountAmount != null &&
                                contract.discountAmount! > 0)
                              _DetailRow(
                                icon: Icons.local_offer_outlined,
                                label: 'Discount',
                                value: _discountLabel(contract),
                              ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // Visit History
                        _VisitHistorySection(contract: contract),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // ── Footer actions ─────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: r.isPending
                    ? [
                        OutlinedButton.icon(
                          onPressed: (_rejecting || _approving)
                              ? null
                              : _reject,
                          icon: _rejecting
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                  ),
                                )
                              : const Icon(Icons.close_rounded, size: 15),
                          label: const Text('Reject'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.error),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: (_approving || _rejecting)
                              ? null
                              : _approve,
                          icon: _approving
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.calendar_month_rounded,
                                  size: 15,
                                ),
                          label: const Text('Approve & Schedule'),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ]
                    : [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close'),
                        ),
                      ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _contractStatusLabel(String s) => switch (s) {
    'active' => 'Active',
    'paused' => 'Paused',
    'completed' => 'Completed',
    'cancelled' => 'Cancelled',
    _ => s,
  };

  Color _contractStatusColor(String s) => switch (s) {
    'active' => const Color(0xFF276749),
    'paused' => const Color(0xFF744210),
    'completed' => AppColors.primary,
    'cancelled' => AppColors.error,
    _ => AppColors.textSecondary,
  };

  String _discountLabel(_AmcContractFull c) {
    final amt = c.discountAmount ?? 0;
    if (c.discountType == 'percentage' && c.discountValue != null) {
      return '−₹${amt.toStringAsFixed(2)} (${c.discountValue!.toStringAsFixed(0)}%)';
    }
    return '−₹${amt.toStringAsFixed(2)}';
  }

  Future<void> _reject() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Reject Request'),
        content: const Text(
          'Reject this scheduling request? '
          'The customer will be able to submit a new request.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _rejecting = true);
    try {
      await Supabase.instance.client
          .from('amc_scheduling_requests')
          .update({'status': 'rejected'})
          .eq('id', widget.request.id);
      if (mounted) {
        Navigator.of(context).pop();
        widget.onRefresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reject: $e'),
            backgroundColor: AppColors.error,
          ),
        );
        setState(() => _rejecting = false);
      }
    }
  }

  Future<void> _approve() async {
    setState(() => _approving = true);
    try {
      // Guard: block scheduling while contract is paused
      final contractRow = await Supabase.instance.client
          .from('amc_contracts')
          .select('status')
          .eq('id', widget.request.contractId)
          .single();
      if ((contractRow['status'] as String?) == 'paused') {
        if (mounted) {
          setState(() => _approving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Cannot schedule: this AMC membership is currently paused.',
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }
      final rows = await Supabase.instance.client
          .from('bookings')
          .select()
          .eq('amc_contract_id', widget.request.contractId)
          .inFilter('status', ['pending', 'assigned'])
          .isFilter('service_date', null)
          .order('created_at', ascending: false)
          .limit(1);

      if (!mounted) return;
      setState(() => _approving = false);

      if ((rows as List).isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No unscheduled visit found. '
              'The visit may already have a date assigned.',
            ),
          ),
        );
        return;
      }

      final booking = Booking.fromMap(
        Map<String, dynamic>.from(rows.first as Map),
      );
      final requestId = widget.request.id;

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => BookingAssignmentDialog(
          booking: booking,
          preferredDate: widget.request.preferredDate,
          onSave:
              ({
                required assignmentType,
                vendorId,
                dodoTeamId,
                required serviceDate,
                notes,
              }) async {
                await ref
                    .read(bookingsNotifierProvider.notifier)
                    .updateBookingAssignment(
                      booking.id,
                      assignmentType: assignmentType,
                      vendorId: vendorId,
                      dodoTeamId: dodoTeamId,
                      serviceDate: serviceDate,
                      notes: notes,
                    );
                await Supabase.instance.client
                    .from('amc_scheduling_requests')
                    .update({'status': 'scheduled'})
                    .eq('id', requestId);
                widget.onRefresh();
              },
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _approving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

// ── Visit history helpers ─────────────────────────────────────────────────────

DateTime _addCalendarMonths(DateTime base, int months) {
  final total = (base.month - 1) + months;
  final targetYear = base.year + total ~/ 12;
  final targetMonth = total % 12 + 1;
  final daysInMonth = DateTime.utc(targetYear, targetMonth + 1, 0).day;
  return DateTime.utc(targetYear, targetMonth, base.day.clamp(1, daysInMonth));
}

DateTime? _visitPlannedDate(
  DateTime createdAt,
  String? interval,
  int visitNumber,
) {
  if (interval == null) return null;
  final n = visitNumber - 1;
  final base = DateTime.utc(createdAt.year, createdAt.month, createdAt.day);
  return switch (interval) {
    'monthly' => _addCalendarMonths(base, n),
    'quarterly' => _addCalendarMonths(base, 3 * n),
    'half_yearly' => _addCalendarMonths(base, 6 * n),
    'yearly' => _addCalendarMonths(base, 12 * n),
    _ => null,
  };
}

// ── Visit history section ──────────────────────────────────────────────────────

class _VisitHistorySection extends StatelessWidget {
  final _AmcContractFull contract;

  const _VisitHistorySection({required this.contract});

  @override
  Widget build(BuildContext context) {
    final total = contract.effectiveTotal;
    final displayCount = total > 0 ? total : contract.visits.length;
    final visitMap = _buildVisitMap(contract.visits);

    return _DetailSection(
      title: 'VISIT HISTORY',
      icon: Icons.history_rounded,
      children: displayCount == 0
          ? [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'No visits linked to this contract yet.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ]
          : List.generate(displayCount, (i) {
              final n = i + 1;
              return _VisitRow(
                visit: visitMap[n],
                visitNumber: n,
                plannedDueDate: _visitPlannedDate(
                  contract.createdAt,
                  contract.serviceInterval,
                  n,
                ),
              );
            }),
    );
  }

  static Map<int, _AmcVisitDetail> _buildVisitMap(
    List<_AmcVisitDetail> visits,
  ) {
    final map = <int, _AmcVisitDetail>{};
    for (final v in visits) {
      final n = v.visitNumber;
      if (n != null && n >= 1) {
        final existing = map[n];
        if (existing == null || _rank(v.status) > _rank(existing.status)) {
          map[n] = v;
        }
      }
    }
    return map;
  }

  static int _rank(String s) => switch (s) {
    'completed' => 5,
    'awaiting_verification' => 4,
    'in_progress' || 'started' => 3,
    'assigned' || 'accepted' || 'en_route' => 2,
    'pending' => 1,
    _ => 0,
  };
}

class _VisitRow extends StatelessWidget {
  final _AmcVisitDetail? visit;
  final int visitNumber;
  final DateTime? plannedDueDate;

  const _VisitRow({
    required this.visit,
    required this.visitNumber,
    this.plannedDueDate,
  });

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: visit != null
            ? AppColors.primary.withAlpha(20)
            : AppColors.border,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Text(
          '$visitNumber',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: visit != null ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );

    if (visit == null) {
      final dueSuffix = plannedDueDate != null
          ? ' · Due: ${_fmtDate(plannedDueDate!)}'
          : '';
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            badge,
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Visit #$visitNumber$dueSuffix',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            _StatusChip('Remaining', AppColors.textSecondary, AppColors.border),
          ],
        ),
      );
    }

    final v = visit!;
    final (statusLabel, statusColor, statusBg) = _statusMeta(v.status);
    final scheduledStr = v.serviceDate != null
        ? _fmtDate(v.serviceDate!.toLocal())
        : null;
    final timeStr = v.timeSlot.isNotEmpty ? ' · ${v.timeSlot}' : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          badge,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Visit #$visitNumber',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (plannedDueDate != null)
                  Text(
                    'Due: ${_fmtDate(plannedDueDate!)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                if (scheduledStr != null)
                  Text(
                    'Scheduled: $scheduledStr$timeStr',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                if (v.completedAt != null)
                  Text(
                    'Completed: ${_fmtDate(v.completedAt!.toLocal())}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF276749),
                    ),
                  ),
              ],
            ),
          ),
          _StatusChip(statusLabel, statusColor, statusBg),
        ],
      ),
    );
  }

  (String, Color, Color) _statusMeta(String status) => switch (status) {
    'completed' => (
      'Completed',
      const Color(0xFF276749),
      const Color(0xFFF0FFF4),
    ),
    'cancelled' => (
      'Cancelled',
      AppColors.error,
      AppColors.error.withAlpha(15),
    ),
    'in_progress' || 'started' => (
      'In Progress',
      const Color(0xFF805AD5),
      const Color(0xFFFAF5FF),
    ),
    'awaiting_verification' => (
      'Awaiting OTP',
      const Color(0xFFDD6B20),
      const Color(0xFFFEEBC8),
    ),
    'assigned' || 'accepted' || 'en_route' => (
      'Scheduled',
      const Color(0xFF2C7A7B),
      const Color(0xFFE6FFFA),
    ),
    _ => ('Pending', const Color(0xFFDD6B20), const Color(0xFFFEEBC8)),
  };
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color textColor;
  final Color bgColor;

  const _StatusChip(this.label, this.textColor, this.bgColor);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }
}

// ── Request status badge ──────────────────────────────────────────────────────

class _RequestStatusBadge extends StatelessWidget {
  final String status;
  const _RequestStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (textColor, bgColor) = _requestStatusColors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: textColor.withAlpha(70)),
      ),
      child: Text(
        _requestStatusLabel(status),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }
}

// ── Type toggle button (Pause / Resume sub-tab) ───────────────────────────────

class _TypeToggleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TypeToggleButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status filter chip ────────────────────────────────────────────────────────

class _StatusFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _StatusFilterChip({
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
          color: selected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ── Detail section card ───────────────────────────────────────────────────────

class _DetailSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _DetailSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

// ── Detail row ────────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool highlight;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 7),
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
                color:
                    valueColor ??
                    (highlight ? AppColors.primary : AppColors.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info row (compact list card) ──────────────────────────────────────────────

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: AppColors.textSecondary),
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
