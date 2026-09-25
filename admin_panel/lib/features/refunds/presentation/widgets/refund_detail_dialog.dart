import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/rbac/permission_guard.dart';
import '../../application/refund_providers.dart';
import '../../domain/models/refund_request.dart';
import '../../domain/models/refund_transaction.dart';
import 'refund_approve_dialog.dart';
import 'refund_reject_dialog.dart';
import 'refund_status_timeline_widget.dart';
import 'refund_transaction_history_widget.dart';
import 'refund_messages_tab.dart';

class RefundDetailDialog extends ConsumerStatefulWidget {
  final String requestId;

  const RefundDetailDialog({super.key, required this.requestId});

  @override
  ConsumerState<RefundDetailDialog> createState() => _RefundDetailDialogState();
}

class _RefundDetailDialogState extends ConsumerState<RefundDetailDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    ref.invalidate(refundRequestDetailProvider(widget.requestId));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _reload();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleMarkUnderReview(RefundRequest r) async {
    await _run(() =>
        ref.read(refundRepositoryProvider).markUnderReview(r.id));
  }

  Future<void> _handleRequestMoreInfo(RefundRequest r) async {
    final ctrl = TextEditingController();
    final msg = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request More Information'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'What information do you need from the customer?',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              child: const Text('Send')),
        ],
      ),
    );
    ctrl.dispose();
    if (msg == null || msg.isEmpty) return;
    await _run(() =>
        ref.read(refundRepositoryProvider).requestMoreInfo(r.id, msg));
  }

  Future<void> _handleApprove(RefundRequest r) async {
    final result = await showDialog<ApproveResult>(
      context: context,
      builder: (_) => RefundApproveDialog(request: r),
    );
    if (result == null) return;
    await _run(() => ref.read(refundRepositoryProvider).approveRequest(
          r.id,
          approvedAmount: result.approvedAmount,
          notes: result.notes,
        ));
  }

  Future<void> _handleReject(RefundRequest r) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => RefundRejectDialog(request: r),
    );
    if (reason == null) return;
    await _run(() =>
        ref.read(refundRepositoryProvider).rejectRequest(r.id, reason: reason));
  }

  Future<void> _handleRequestBankDetails(RefundRequest r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request Bank/UPI Details'),
        content: const Text(
          'This will send the customer a message asking them to provide '
          'their bank account or UPI details for the manual refund transfer.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Send Request')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() =>
        ref.read(refundRepositoryProvider).requestCodBankDetails(r.id));
  }

  Future<void> _handleInitiateTransaction(RefundRequest r) async {
    if (r.isCodBooking) {
      await _handleInitiateCodRefund(r);
    } else {
      await _handleInitiateOnlineRefund(r);
    }
  }

  Future<void> _handleInitiateCodRefund(RefundRequest r) async {
    final amount = r.approvedAmount ?? r.requestedAmount;
    final fmt = NumberFormat('#,##0.00', 'en_IN');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Initiate Refund'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Transfer ₹${fmt.format(amount)} to the customer\'s '
                'bank/UPI account.'),
            if (r.bankUpiDetails != null) ...[
              const SizedBox(height: 12),
              _BankUpiDetailsSection(details: r.bankUpiDetails!),
            ],
            const SizedBox(height: 12),
            const Text(
              'The refund will be marked as completed immediately. '
              'Make the bank/UPI transfer before or after confirming.',
              style: TextStyle(fontSize: 12, color: Color(0xFF718096)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF805AD5)),
            child: const Text('Initiate Refund'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      () => ref.read(refundRepositoryProvider).initiateCodRefund(r.id),
    );
    if (mounted && _error == null) {
      await _showInitiateSuccessPopup(
        'The refund has been marked as initiated. Please complete the '
        'manual bank or UPI transfer to the customer.',
      );
    }
  }

  Future<void> _handleInitiateOnlineRefund(RefundRequest r) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? refundResult;
    try {
      final balance = await ref
          .read(refundRepositoryProvider)
          .getRefundableBalance(r.id);
      if (balance <= 0) {
        throw Exception('No refundable balance remaining.');
      }
      final txnId = await ref
          .read(refundRepositoryProvider)
          .initiateRefundTransaction(
            requestId: r.id,
            amount: balance,
            gateway: 'razorpay',
            refundMethod: 'original_payment_method',
          );
      refundResult = await ref
          .read(refundRepositoryProvider)
          .processRazorpayRefund(txnId);
      await _reload();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    if (refundResult == 'confirmed') {
      await _showInitiateSuccessPopup(
        'The refund has been submitted to Razorpay and will be returned '
        'to the customer\'s original payment method.',
      );
    } else if (refundResult == 'pending') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Refund queued by Razorpay — will be confirmed automatically '
            'within 5–7 business days via webhook.',
          ),
          backgroundColor: Color(0xFF805AD5),
          duration: Duration(seconds: 8),
        ),
      );
    } else if (refundResult == 'uncertain') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Razorpay API response was uncertain. '
            'Check the Razorpay dashboard and mark the transaction '
            'complete or failed manually.',
          ),
          backgroundColor: Color(0xFFDD6B20),
          duration: Duration(seconds: 8),
        ),
      );
    }
  }

  Future<void> _showInitiateSuccessPopup(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEBFBF0),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Refund Initiated Successfully!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2D3748),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF718096),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF805AD5),
                    minimumSize: const Size(120, 40),
                  ),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleProcessViaRazorpay(RefundTransaction txn) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(refundRepositoryProvider)
          .processRazorpayRefund(txn.id);
      await _reload();
      if (!mounted) return;
      if (result == 'pending') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Refund queued by Razorpay — will be confirmed automatically '
              'within 5–7 business days via webhook.',
            ),
            backgroundColor: Color(0xFF805AD5),
            duration: Duration(seconds: 8),
          ),
        );
      } else if (result == 'uncertain') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Razorpay API response was uncertain. '
              'Check the Razorpay dashboard and mark the transaction '
              'complete or failed manually.',
            ),
            backgroundColor: Color(0xFFDD6B20),
            duration: Duration(seconds: 8),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleMarkTxnComplete(RefundTransaction txn) async {
    final isManual = txn.gateway == 'manual';
    final ctrl = TextEditingController();
    final refundId = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark Transaction Complete'),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            labelText: isManual
                ? 'UTR / Transfer Reference (optional)'
                : 'Gateway refund ID (optional)',
            hintText: isManual
                ? 'e.g. UTR123456789012'
                : 'e.g. rfnd_XXXXXXXXXXXXX',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              style:
                  FilledButton.styleFrom(backgroundColor: const Color(0xFF38A169)),
              child: const Text('Confirm Complete')),
        ],
      ),
    );
    ctrl.dispose();
    if (refundId == null) return;
    await _run(() => ref.read(refundRepositoryProvider).markTransactionComplete(
          txn.id,
          gatewayRefundId: refundId.isEmpty ? null : refundId,
        ));
  }

  Future<void> _handleMarkTxnFailed(RefundTransaction txn) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark Transaction Failed'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Failure reason *',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE53E3E)),
              child: const Text('Mark Failed')),
        ],
      ),
    );
    ctrl.dispose();
    if (reason == null || reason.isEmpty) return;
    await _run(() => ref.read(refundRepositoryProvider).markTransactionFailed(
          txn.id,
          failureReason: reason,
        ));
  }

  Future<void> _handleClose(RefundRequest r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close Ticket?'),
        content: const Text(
            'This will close the ticket. No further actions can be taken.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Close Ticket')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => ref.read(refundRepositoryProvider).closeRequest(r.id));
  }

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(refundRequestDetailProvider(widget.requestId));

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 720),
        child: asyncData.when(
          loading: () => const Center(
              child: Padding(
                  padding: EdgeInsets.all(48),
                  child: CircularProgressIndicator())),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (request) {
            if (request == null) {
              return const Center(child: Text('Ticket not found.'));
            }
            return _buildContent(request);
          },
        ),
      ),
    );
  }

  Widget _buildContent(RefundRequest r) {
    return Column(
      children: [
        _Header(request: r, onClose: () => Navigator.of(context).pop()),
        const Divider(height: 1),
        TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: const Color(0xFF718096),
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Timeline'),
            Tab(text: 'Transactions'),
            Tab(text: 'Messages'),
          ],
        ),
        const Divider(height: 1),
        if (_error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFFFFF5F5),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    size: 14, color: Color(0xFFE53E3E)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_error!,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFFE53E3E))),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 14),
                  onPressed: () => setState(() => _error = null),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _OverviewTab(request: r),
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child:
                    RefundStatusTimeline(events: r.statusHistory),
              ),
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: RefundTransactionHistoryWidget(
                  transactions: r.transactions,
                  onMarkComplete: r.isCodBooking ? null : _handleMarkTxnComplete,
                  onMarkFailed: _handleMarkTxnFailed,
                  onProcessViaRazorpay: _handleProcessViaRazorpay,
                ),
              ),
              RefundMessagesTab(requestId: r.id),
            ],
          ),
        ),
        const Divider(height: 1),
        _ActionBar(
          request: r,
          busy: _busy,
          onMarkUnderReview: () => _handleMarkUnderReview(r),
          onRequestMoreInfo: () => _handleRequestMoreInfo(r),
          onApprove: () => _handleApprove(r),
          onReject: () => _handleReject(r),
          onRequestBankDetails: () => _handleRequestBankDetails(r),
          onInitiateTransaction: () => _handleInitiateTransaction(r),
          onClose: () => _handleClose(r),
        ),
      ],
    );
  }
}

// ── Header ─────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final RefundRequest request;
  final VoidCallback onClose;

  const _Header({required this.request, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final r = request;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      r.ticketNumber,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2D3748),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _StatusBadge(
                        label: r.statusLabel, color: r.statusColor),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (r.bookingNumber != null)
                      Text(
                        'Booking #${r.bookingNumber}',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF718096)),
                      ),
                    if (r.bookingNumber != null && r.customerName != null)
                      const Text(' · ',
                          style: TextStyle(color: Color(0xFF718096))),
                    if (r.customerName != null)
                      Text(
                        r.customerName!,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF718096)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

// ── Overview tab ───────────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  final RefundRequest request;

  const _OverviewTab({required this.request});

  @override
  Widget build(BuildContext context) {
    final r = request;
    final fmt = NumberFormat('#,##0.00', 'en_IN');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Section(
            title: 'Customer & Booking',
            child: Column(
              children: [
                if (r.customerName != null)
                  _InfoRow('Customer', r.customerName!),
                if (r.customerPhone != null)
                  _InfoRow('Phone', r.customerPhone!),
                if (r.bookingNumber != null)
                  _InfoRow('Booking', '#${r.bookingNumber}'),
                _InfoRow('Submitted',
                    DateFormat('d MMM yyyy, h:mm a').format(r.createdAt.toLocal())),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Refund Request',
            child: Column(
              children: [
                _InfoRow(
                    'Issue category', r.issueCategoryLabel ?? 'Not specified'),
                _InfoRow('Payment method', r.paymentMethodLabel),
                _InfoRow('Amount paid', '₹${fmt.format(r.amountPaidSnapshot)}'),
                _InfoRow('Requested amount',
                    '₹${fmt.format(r.requestedAmount)}'),
                if (r.description != null && r.description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Customer description:',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF4A5568)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    r.description!,
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF2D3748)),
                  ),
                ],
              ],
            ),
          ),
          if (r.evidenceUrls.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Section(
              title: 'Evidence (${r.evidenceUrls.length})',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: r.evidenceUrls
                    .map((url) => _EvidenceChip(url: url))
                    .toList(),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _Section(
            title: 'Financial Summary',
            child: Column(
              children: [
                _InfoRow('Collected', '₹${fmt.format(r.amountPaidSnapshot)}'),
                if (r.approvedAmount != null)
                  _InfoRow('Approved', '₹${fmt.format(r.approvedAmount!)}'),
                _InfoRow('Refunded so far',
                    '₹${fmt.format(r.processedAmount)}'),
                _InfoRow('Remaining refundable',
                    '₹${fmt.format(r.remainingRefundable)}',
                    valueColor: const Color(0xFF38A169)),
              ],
            ),
          ),
          if (r.bankUpiDetails != null) ...[
            const SizedBox(height: 12),
            _Section(
              title: 'Customer Bank/UPI Details',
              child: _BankUpiDetailsSection(details: r.bankUpiDetails!),
            ),
          ] else if (r.isAwaitingBankDetails) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFD69E2E)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.hourglass_top_rounded,
                      size: 16, color: Color(0xFF744210)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bank/UPI details request sent. '
                      'Waiting for customer to submit their details.',
                      style: TextStyle(
                          fontSize: 12, color: Color(0xFF744210)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (r.decisionNotes != null && r.decisionNotes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Section(
              title: 'Admin Decision Notes',
              child: Text(
                r.decisionNotes!,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF2D3748)),
              ),
            ),
          ],
          if (r.adminNotes != null && r.adminNotes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Section(
              title: 'Internal Notes',
              child: Text(
                r.adminNotes!,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF2D3748)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Action bar ─────────────────────────────────────────────────────────────────

class _ActionBar extends ConsumerWidget {
  final RefundRequest request;
  final bool busy;
  final VoidCallback onMarkUnderReview;
  final VoidCallback onRequestMoreInfo;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onRequestBankDetails;
  final VoidCallback onInitiateTransaction;
  final VoidCallback onClose;

  const _ActionBar({
    required this.request,
    required this.busy,
    required this.onMarkUnderReview,
    required this.onRequestMoreInfo,
    required this.onApprove,
    required this.onReject,
    required this.onRequestBankDetails,
    required this.onInitiateTransaction,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = request;
    if (busy) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          if (r.canClose && r.status != RefundTicketStatus.closed)
            OutlinedButton(
              onPressed: onClose,
              child: const Text('Close Ticket'),
            ),
          if (r.canMarkUnderReview)
            PermissionGuard(
              permission: 'refund.review',
              child: OutlinedButton(
                onPressed: onMarkUnderReview,
                child: const Text('Mark Under Review'),
              ),
            ),
          if (r.canRequestMoreInfo)
            PermissionGuard(
              permission: 'refund.review',
              child: OutlinedButton(
                onPressed: onRequestMoreInfo,
                child: const Text('Request Info'),
              ),
            ),
          if (r.canReject)
            PermissionGuard(
              permission: 'refund.approve',
              child: OutlinedButton(
                onPressed: onReject,
                style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE53E3E),
                    side: const BorderSide(color: Color(0xFFE53E3E))),
                child: const Text('Reject'),
              ),
            ),
          if (r.canApprove)
            PermissionGuard(
              permission: 'refund.approve',
              child: FilledButton(
                onPressed: onApprove,
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF38A169)),
                child: const Text('Approve'),
              ),
            ),
          // COD: request bank/UPI details from customer
          if (r.canRequestBankDetails)
            PermissionGuard(
              permission: 'refund.process',
              child: OutlinedButton.icon(
                onPressed: onRequestBankDetails,
                icon: const Icon(Icons.account_balance_wallet_outlined,
                    size: 15),
                label: Text(r.hasBankDetailsRequested
                    ? 'Re-send Bank Details Request'
                    : 'Request Bank/UPI Details'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF805AD5),
                    side: const BorderSide(color: Color(0xFF805AD5))),
              ),
            ),
          // COD: awaiting customer details (not clickable)
          if (r.isAwaitingBankDetails)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD69E2E)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.hourglass_top_rounded,
                      size: 14, color: Color(0xFF744210)),
                  SizedBox(width: 6),
                  Text(
                    'Awaiting Bank/UPI Details',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF744210)),
                  ),
                ],
              ),
            ),
          if (r.canInitiateTransaction)
            PermissionGuard(
              permission: 'refund.process',
              child: FilledButton.icon(
                onPressed: onInitiateTransaction,
                icon: const Icon(Icons.payments_outlined, size: 16),
                label: const Text('Initiate Refund'),
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF805AD5)),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Shared UI components ───────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4A5568),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoRow(this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF718096)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: valueColor ?? const Color(0xFF2D3748),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BankUpiDetailsSection extends StatelessWidget {
  final Map<String, dynamic> details;
  const _BankUpiDetailsSection({required this.details});

  @override
  Widget build(BuildContext context) {
    final type = details['type'] as String? ?? '';
    final isBank = type == 'bank';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              isBank ? Icons.account_balance : Icons.phone_android,
              size: 14,
              color: const Color(0xFF4A5568),
            ),
            const SizedBox(width: 6),
            Text(
              isBank ? 'Bank Transfer' : 'UPI Transfer',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4A5568),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (isBank) ...[
          if (details['account_holder_name'] != null)
            _InfoRow('Account holder',
                details['account_holder_name'] as String),
          _InfoRow('Account number',
              details['account_number'] as String? ?? '—'),
          _InfoRow('IFSC code',
              details['ifsc_code'] as String? ?? '—'),
          if (details['bank_name'] != null &&
              (details['bank_name'] as String).isNotEmpty)
            _InfoRow('Bank', details['bank_name'] as String),
        ] else ...[
          _InfoRow('UPI ID', details['upi_id'] as String? ?? '—'),
        ],
      ],
    );
  }
}

class _EvidenceChip extends StatelessWidget {
  final String url;
  const _EvidenceChip({required this.url});

  @override
  Widget build(BuildContext context) {
    final filename = url.split('/').last.split('?').first;
    return ActionChip(
      avatar: const Icon(Icons.attachment, size: 14),
      label: Text(
        filename.length > 24 ? '${filename.substring(0, 24)}…' : filename,
        style: const TextStyle(fontSize: 11),
      ),
      onPressed: () {
        // URL is a public storage link; open in browser (web) or show snackbar.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Evidence: $url')),
        );
      },
    );
  }
}
