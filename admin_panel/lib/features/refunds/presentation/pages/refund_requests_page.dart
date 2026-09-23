import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/admin_search_bar.dart';
import '../../application/refund_providers.dart';
import '../../domain/models/refund_request.dart';
import '../widgets/refund_detail_dialog.dart';
import '../widgets/admin_create_refund_dialog.dart';

class RefundRequestsPage extends ConsumerStatefulWidget {
  const RefundRequestsPage({super.key});

  @override
  ConsumerState<RefundRequestsPage> createState() => _RefundRequestsPageState();
}

class _RefundRequestsPageState extends ConsumerState<RefundRequestsPage> {
  static const _statusTabs = [
    ('all', 'All'),
    ('awaiting_refund', 'Awaiting Refund'),
    ('submitted', 'Submitted'),
    ('under_review', 'Under Review'),
    ('more_info_requested', 'More Info'),
    ('approved', 'Approved'),
    ('partially_approved', 'Partial'),
    ('rejected', 'Rejected'),
    ('processing', 'Processing'),
    ('completed', 'Completed'),
    ('failed', 'Failed'),
    ('closed', 'Closed'),
  ];

  Future<void> _openCreateDialog() async {
    final ticketNumber = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AdminCreateRefundDialog(),
    );
    if (!mounted) return;
    if (ticketNumber != null) {
      ref.invalidate(refundRequestsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Refund ticket $ticketNumber created successfully.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentStatus = ref.watch(refundStatusFilterProvider);
    final asyncRequests = ref.watch(refundRequestsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Page header ────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Refund Requests',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A202C),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Review and manage customer refund tickets',
                            style: TextStyle(
                                fontSize: 13, color: Color(0xFF718096)),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => _openCreateDialog(),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Create Request'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        textStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () =>
                          ref.invalidate(refundRequestsProvider),
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip: 'Refresh',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Search
                AdminSearchBar(
                  hintText: 'Search by ticket #, booking #, customer…',
                  onChanged: (v) => ref
                      .read(refundSearchQueryProvider.notifier)
                      .state = v,
                ),
                const SizedBox(height: 12),
                // Status tabs
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _statusTabs.map((tab) {
                      final (key, label) = tab;
                      final selected = currentStatus == key;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: selected,
                          onSelected: (_) => ref
                              .read(refundStatusFilterProvider.notifier)
                              .state = key,
                          selectedColor:
                              AppColors.primary.withAlpha(25),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: selected
                                ? AppColors.primary
                                : const Color(0xFF718096),
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                          side: BorderSide(
                            color: selected
                                ? AppColors.primary.withAlpha(100)
                                : const Color(0xFFE2E8F0),
                          ),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          const Divider(height: 1),
          // ── List ──────────────────────────────────────────────────────────
          Expanded(
            child: asyncRequests.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorView(error: e.toString(),
                  onRetry: () => ref.invalidate(refundRequestsProvider)),
              data: (requests) => requests.isEmpty
                  ? const _EmptyView()
                  : _RefundTable(requests: requests),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Table ──────────────────────────────────────────────────────────────────────

class _RefundTable extends StatelessWidget {
  final List<RefundRequest> requests;
  const _RefundTable({required this.requests});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: requests.length,
      itemBuilder: (context, i) => _RefundRow(request: requests[i]),
    );
  }
}

class _RefundRow extends StatefulWidget {
  final RefundRequest request;
  const _RefundRow({required this.request});

  @override
  State<_RefundRow> createState() => _RefundRowState();
}

class _RefundRowState extends State<_RefundRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final fmt = NumberFormat('#,##0.00', 'en_IN');
    final dateFmt = DateFormat('d MMM yy');

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _openDetail(context, r.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFFF7FAFC) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered
                  ? AppColors.primary.withAlpha(60)
                  : const Color(0xFFE2E8F0),
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: Colors.black.withAlpha(12),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Row(
            children: [
              // Ticket number
              SizedBox(
                width: 160,
                child: Text(
                  r.ticketNumber,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    color: Color(0xFF2D3748),
                  ),
                ),
              ),
              // Customer
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.customerName ?? '—',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    if (r.bookingNumber != null)
                      Text(
                        '#${r.bookingNumber}',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF718096)),
                      ),
                  ],
                ),
              ),
              // Issue category
              Expanded(
                flex: 2,
                child: Text(
                  r.issueCategoryLabel ?? '—',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF4A5568)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Amount
              SizedBox(
                width: 110,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${fmt.format(r.requestedAmount)}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    if (r.approvedAmount != null)
                      Text(
                        'Approved ₹${fmt.format(r.approvedAmount!)}',
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFF38A169)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Status
              SizedBox(
                width: 130,
                child: _StatusBadge(
                    label: r.statusLabel, color: r.statusColor),
              ),
              // Date
              SizedBox(
                width: 80,
                child: Text(
                  dateFmt.format(r.createdAt.toLocal()),
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF718096)),
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: Color(0xFFCBD5E0)),
            ],
          ),
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, String id) {
    showDialog(
      context: context,
      builder: (_) => RefundDetailDialog(requestId: id),
    );
  }
}

// ── Status badge ───────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ── Empty / Error views ───────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 48, color: Color(0xFFCBD5E0)),
          SizedBox(height: 12),
          Text(
            'No refund tickets found',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF718096)),
          ),
          SizedBox(height: 4),
          Text(
            'Tickets submitted by customers will appear here.',
            style:
                TextStyle(fontSize: 13, color: Color(0xFFA0AEC0)),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline,
              size: 40, color: Color(0xFFE53E3E)),
          const SizedBox(height: 12),
          Text(
            'Failed to load refund requests',
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            error,
            style: const TextStyle(
                fontSize: 12, color: Color(0xFF718096)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton(
              onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
