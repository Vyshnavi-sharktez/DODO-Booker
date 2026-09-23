import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../routes/app_router.dart';
import '../models/booking_for_refund_model.dart';
import '../models/customer_refund_model.dart';
import '../services/refund_queries_providers.dart';
import '../widgets/refund_status_badge.dart';

class RefundQueriesScreen extends ConsumerStatefulWidget {
  const RefundQueriesScreen({
    super.key,
    this.inModal = false,
    this.onRequestRefund,
    this.onViewQuery,
  });

  final bool inModal;
  final VoidCallback? onRequestRefund;
  final void Function(String id)? onViewQuery;

  @override
  ConsumerState<RefundQueriesScreen> createState() =>
      _RefundQueriesScreenState();
}

class _RefundQueriesScreenState extends ConsumerState<RefundQueriesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  static const _activeStatuses = {
    'submitted',
    'under_review',
    'more_info_requested',
    'approved',
    'partially_approved',
    'processing',
    'failed',
  };
  static const _closedStatuses = {'completed', 'rejected', 'closed'};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(myRefundQueriesProvider);
    ref.invalidate(bookingsForRefundProvider);
    try {
      await Future.wait([
        ref.read(myRefundQueriesProvider.future),
        ref.read(bookingsForRefundProvider.future),
      ]);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final policyAsync = ref.watch(refundPolicyDescriptionProvider);
    final queriesAsync = ref.watch(myRefundQueriesProvider);
    final bookingsAsync = ref.watch(bookingsForRefundProvider);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Refund policy banner ─────────────────────────────────────────────
        policyAsync.maybeWhen(
          data: (desc) {
            if (desc == null || desc.isEmpty) return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.gold.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.gold.withAlpha(60)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: AppColors.gold,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      desc,
                      style: tt.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
          orElse: () => const SizedBox.shrink(),
        ),

        // ── Request a Refund CTA ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: FilledButton.icon(
            onPressed: () => widget.onRequestRefund != null
                ? widget.onRequestRefund!()
                : context.push(AppRoutes.bookingSelectionForRefund),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Request a Refund'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // ── Tab bar ──────────────────────────────────────────────────────────
        Material(
          color: AppColors.surface,
          child: TabBar(
            controller: _tabs,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            indicatorWeight: 2.5,
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            tabs: const [
              Tab(text: 'Active'),
              Tab(text: 'Closed'),
              Tab(text: 'Not Eligible'),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.divider),

        // ── Tab views ────────────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _QueriesTab(
                queriesAsync: queriesAsync,
                filter: (q) => _activeStatuses.contains(q.status),
                onRefresh: _refresh,
                onViewQuery: widget.onViewQuery,
                emptyTitle: 'No active queries',
                emptySubtitle:
                    'Tap "Request a Refund" above to raise a new query.',
              ),
              _QueriesTab(
                queriesAsync: queriesAsync,
                filter: (q) => _closedStatuses.contains(q.status),
                onRefresh: _refresh,
                onViewQuery: widget.onViewQuery,
                emptyTitle: 'No closed queries',
                emptySubtitle:
                    'Completed and rejected queries will appear here.',
              ),
              _NotEligibleTab(
                bookingsAsync: bookingsAsync,
                periodDays: ref
                    .read(refundQueriesServiceProvider)
                    .lastFetchedRefundPeriodDays,
                onRefresh: _refresh,
              ),
            ],
          ),
        ),
      ],
    );

    if (widget.inModal) return body;

    return Scaffold(
      backgroundColor: AppColors.surfaceVariant,
      appBar: AppBar(title: const Text('Refund Queries')),
      body: body,
    );
  }
}

// ── Active / Closed tab ────────────────────────────────────────────────────────

class _QueriesTab extends StatelessWidget {
  const _QueriesTab({
    required this.queriesAsync,
    required this.filter,
    required this.onRefresh,
    required this.onViewQuery,
    required this.emptyTitle,
    required this.emptySubtitle,
  });

  final AsyncValue<List<CustomerRefundModel>> queriesAsync;
  final bool Function(CustomerRefundModel) filter;
  final Future<void> Function() onRefresh;
  final void Function(String id)? onViewQuery;
  final String emptyTitle;
  final String emptySubtitle;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: onRefresh,
      child: queriesAsync.when(
        loading: () => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(
              height: 260,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
          ],
        ),
        error: (e, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 260,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 40,
                      color: AppColors.textHint,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Could not load queries',
                      style: tt.titleSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Pull down to retry',
                      style: tt.bodySmall?.copyWith(
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        data: (all) {
          final items = all.where(filter).toList();
          if (items.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: 260,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceVariant,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.border),
                            ),
                            child: const Icon(
                              Icons.receipt_long_outlined,
                              size: 28,
                              color: AppColors.textHint,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            emptyTitle,
                            style: tt.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            emptySubtitle,
                            style: tt.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 6, bottom: 32),
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final q = items[i];
              return _RefundQueryCard(
                query: q,
                onTap: () => onViewQuery != null
                    ? onViewQuery!(q.id)
                    : ctx.push(
                        AppRoutes.refundQueryDetail.replaceFirst(':id', q.id),
                      ),
              );
            },
          );
        },
      ),
    );
  }
}

// ── Not Eligible tab ───────────────────────────────────────────────────────────

class _NotEligibleTab extends StatelessWidget {
  const _NotEligibleTab({
    required this.bookingsAsync,
    required this.periodDays,
    required this.onRefresh,
  });

  final AsyncValue<List<BookingForRefundModel>> bookingsAsync;
  final int periodDays;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: onRefresh,
      child: bookingsAsync.when(
        loading: () => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(
              height: 260,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
          ],
        ),
        error: (e, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 260,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 40,
                      color: AppColors.textHint,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Could not load bookings',
                      style: tt.titleSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Pull down to retry',
                      style: tt.bodySmall?.copyWith(
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        data: (all) {
          final ineligible = all
              .where((b) =>
                  b.isCancelledCod || b.isRefundPeriodExpired(periodDays))
              .toList();

          if (ineligible.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: 260,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceVariant,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.border),
                            ),
                            child: const Icon(
                              Icons.check_circle_outline_rounded,
                              size: 28,
                              color: AppColors.success,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'All bookings eligible',
                            style: tt.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Bookings whose refund period has expired, or cancelled COD bookings with no payment collected, will appear here.',
                            style: tt.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 6, bottom: 32),
            itemCount: ineligible.length,
            itemBuilder: (_, i) {
              final b = ineligible[i];
              return _NotEligibleBookingCard(
                booking: b,
                periodExpired: !b.isCancelledCod,
              );
            },
          );
        },
      ),
    );
  }
}

// ── Refund query card (existing) ───────────────────────────────────────────────

class _RefundQueryCard extends StatelessWidget {
  const _RefundQueryCard({
    required this.query,
    required this.onTap,
  });

  final CustomerRefundModel query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 0.8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ────────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: Text(
                      query.ticketNumber,
                      style: tt.labelMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  RefundStatusBadge(refund: query),
                ],
              ),

              const SizedBox(height: 8),

              // ── Service / booking info ─────────────────────────────────────
              if (query.serviceName != null)
                Text(
                  query.serviceName!,
                  style: tt.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),

              if (query.bookingNumber != null)
                Text(
                  query.bookingNumber!,
                  style: tt.bodySmall?.copyWith(
                    color: AppColors.textHint,
                    fontSize: 11,
                  ),
                ),

              const SizedBox(height: 10),
              const Divider(height: 1, color: AppColors.divider),
              const SizedBox(height: 10),

              // ── Amount row ────────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _InfoChip(
                      label: 'Requested',
                      value: '₹${query.requestedAmount.toStringAsFixed(0)}',
                    ),
                  ),
                  if (query.approvedAmount != null)
                    Expanded(
                      child: _InfoChip(
                        label: 'Approved',
                        value: '₹${query.approvedAmount!.toStringAsFixed(0)}',
                        valueColor: AppColors.success,
                      ),
                    ),
                  Expanded(
                    child: _InfoChip(
                      label: 'Submitted',
                      value: DateFormat('d MMM yy')
                          .format(query.createdAt.toLocal()),
                    ),
                  ),
                ],
              ),

              // ── Needs action indicator ────────────────────────────────────
              if (query.needsCustomerAction) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withAlpha(24),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.warning.withAlpha(60),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.notifications_active_rounded,
                        size: 13,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'More information requested — tap to respond',
                        style: tt.labelSmall?.copyWith(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Not eligible booking card ──────────────────────────────────────────────────

class _NotEligibleBookingCard extends StatelessWidget {
  const _NotEligibleBookingCard({
    required this.booking,
    required this.periodExpired,
  });

  final BookingForRefundModel booking;
  final bool periodExpired;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isCancelled = booking.status == 'cancelled';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Status icon ───────────────────────────────────────────────
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(
                isCancelled
                    ? Icons.cancel_outlined
                    : Icons.check_circle_outline_rounded,
                size: 20,
                color: AppColors.textHint,
              ),
            ),
            const SizedBox(width: 12),

            // ── Info ──────────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    booking.serviceName,
                    style: tt.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textHint,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${booking.displayBookingNumber}  ·  ${booking.formattedDate}',
                    style: tt.bodySmall?.copyWith(
                      color: AppColors.textHint,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _IneligibilityBadge(
                    booking: booking,
                    periodExpired: periodExpired,
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // ── Amount ────────────────────────────────────────────────────
            Text(
              booking.formattedAmount,
              style: tt.bodySmall?.copyWith(
                color: AppColors.textHint,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IneligibilityBadge extends StatelessWidget {
  const _IneligibilityBadge({
    required this.booking,
    required this.periodExpired,
  });

  final BookingForRefundModel booking;
  final bool periodExpired;

  @override
  Widget build(BuildContext context) {
    final isCod = booking.isCancelledCod;
    final Color bg;
    final Color border;
    final Color textColor;
    final String label;

    if (isCod) {
      bg = const Color(0xFFF7F7F7);
      border = const Color(0xFFD1D1D1);
      textColor = const Color(0xFF6B6B6B);
      label = 'COD — No Refund Required';
    } else {
      bg = const Color(0xFFFFF3CD);
      border = const Color(0xFFFFCA28);
      textColor = const Color(0xFF7B5800);
      label = 'Refund Period Expired';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}

// ── Info chip (existing) ───────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: tt.labelSmall?.copyWith(
            color: AppColors.textHint,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: tt.bodySmall?.copyWith(
            color: valueColor ?? AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
