import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../models/customer_refund_model.dart';
import '../models/refund_transaction_model.dart';
import '../services/refund_queries_providers.dart';
import '../services/refund_queries_service.dart';
import '../widgets/refund_status_badge.dart';
import '../widgets/refund_timeline_widget.dart';
import '../widgets/refund_message_item.dart';

class RefundQueryDetailScreen extends ConsumerStatefulWidget {
  const RefundQueryDetailScreen({
    super.key,
    required this.requestId,
    this.inModal = false,
  });

  final String requestId;
  final bool inModal;

  @override
  ConsumerState<RefundQueryDetailScreen> createState() =>
      _RefundQueryDetailScreenState();
}

class _RefundQueryDetailScreenState
    extends ConsumerState<RefundQueryDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _msgCtrl = TextEditingController();
  bool _sending = false;
  final List<_PendingAttachment> _pendingAttachments = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImages(CustomerRefundModel refund) async {
    if (_pendingAttachments.length >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum 4 images per message.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(imageQuality: 85);
    if (images.isEmpty) return;

    final toProcess = images.take(4 - _pendingAttachments.length);
    final newPending = <_PendingAttachment>[];

    for (final img in toProcess) {
      final bytes = await img.readAsBytes();
      final ext = img.name.split('.').last.toLowerCase();
      final mime = ext == 'png'
          ? 'image/png'
          : ext == 'webp'
              ? 'image/webp'
              : 'image/jpeg';
      // Validate before adding to preview list
      if (bytes.length > RefundQueriesService.maxBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${img.name} is too large (max 5 MB).'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        continue;
      }
      newPending.add(_PendingAttachment(
          bytes: bytes, filename: img.name, mimeType: mime));
    }

    if (mounted && newPending.isNotEmpty) {
      setState(() => _pendingAttachments.addAll(newPending));
    }
  }

  Future<void> _sendMessage(CustomerRefundModel refund) async {
    final msg = _msgCtrl.text.trim();
    if (msg.isEmpty && _pendingAttachments.isEmpty) return;
    setState(() => _sending = true);
    try {
      final svc = ref.read(refundQueriesServiceProvider);
      final paths = <String>[];

      // Upload attachments first; abort entire send on any failure.
      for (final att in _pendingAttachments) {
        final path = await svc.uploadMessageAttachment(
          refundRequestId: refund.id,
          bytes: att.bytes,
          filename: att.filename,
          mimeType: att.mimeType,
        );
        paths.add(path);
      }

      final messageText = msg.isEmpty ? '📎 Image attachment' : msg;
      await svc.addMessage(refund.id, messageText,
          attachmentPaths: paths);

      _msgCtrl.clear();
      _pendingAttachments.clear();
      ref.invalidate(refundQueryDetailProvider(widget.requestId));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync =
        ref.watch(refundQueryDetailProvider(widget.requestId));

    void refresh() =>
        ref.invalidate(refundQueryDetailProvider(widget.requestId));

    Widget bodyContent(CustomerRefundModel? refund) {
      if (refund == null) return const Center(child: Text('Query not found.'));
      return TabBarView(
        controller: _tabs,
        children: [
          _OverviewTab(refund: refund),
          _TimelineTab(refund: refund),
          _MessagesTab(
            refund: refund,
            msgCtrl: _msgCtrl,
            sending: _sending,
            pendingAttachments: List.unmodifiable(_pendingAttachments),
            onSend: () => _sendMessage(refund),
            onPickImages: () => _pickImages(refund),
            onRemoveAttachment: (i) =>
                setState(() => _pendingAttachments.removeAt(i)),
          ),
        ],
      );
    }

    if (widget.inModal) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: AppColors.surface,
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _tabs,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: AppColors.textSecondary,
                    indicatorColor: AppColors.primary,
                    tabs: const [
                      Tab(text: 'Overview'),
                      Tab(text: 'Timeline'),
                      Tab(text: 'Messages'),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  onPressed: refresh,
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          Expanded(
            child: detailAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        size: 40, color: AppColors.textHint),
                    const SizedBox(height: 12),
                    Text(
                      'Could not load query',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: refresh, child: const Text('Retry')),
                  ],
                ),
              ),
              data: bodyContent,
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surfaceVariant,
      appBar: AppBar(
        title: const Text('Refund Query'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: refresh,
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Timeline'),
            Tab(text: 'Messages'),
          ],
        ),
      ),
      body: detailAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 40, color: AppColors.textHint),
              const SizedBox(height: 12),
              Text(
                'Could not load query',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: refresh, child: const Text('Retry')),
            ],
          ),
        ),
        data: bodyContent,
      ),
    );
  }
}

// ── Overview tab ───────────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.refund});
  final CustomerRefundModel refund;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        // ── Header card ──────────────────────────────────────────────────
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      refund.ticketNumber,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  RefundStatusBadge(refund: refund),
                ],
              ),
              const SizedBox(height: 12),
              if (refund.serviceName != null)
                _DetailRow(
                  label: 'Service',
                  value: refund.serviceName!,
                ),
              if (refund.bookingNumber != null)
                _DetailRow(
                  label: 'Booking',
                  value: refund.bookingNumber!,
                ),
              _DetailRow(
                label: 'Submitted',
                value: DateFormat('d MMMM yyyy, h:mm a')
                    .format(refund.createdAt.toLocal()),
              ),
              _DetailRow(
                label: 'Payment',
                value: refund.paymentMethodSnapshot == 'online'
                    ? 'Online (Razorpay)'
                    : refund.paymentMethodSnapshot == 'cod'
                        ? 'Cash on Delivery'
                        : 'Cash',
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── Amounts card ─────────────────────────────────────────────────
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AMOUNTS',
                style: tt.labelSmall?.copyWith(
                  color: AppColors.textHint,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _AmountCell(
                    label: 'Booking Total',
                    value:
                        '₹${refund.amountPaidSnapshot.toStringAsFixed(0)}',
                  ),
                  _AmountCell(
                    label: 'Requested',
                    value:
                        '₹${refund.requestedAmount.toStringAsFixed(0)}',
                  ),
                  if (refund.approvedAmount != null)
                    _AmountCell(
                      label: 'Approved',
                      value:
                          '₹${refund.approvedAmount!.toStringAsFixed(0)}',
                      valueColor: AppColors.success,
                    ),
                  if (refund.processedAmount > 0)
                    _AmountCell(
                      label: 'Processed',
                      value:
                          '₹${refund.processedAmount.toStringAsFixed(0)}',
                      valueColor: AppColors.success,
                    ),
                ],
              ),
            ],
          ),
        ),

        // ── Issue & description ──────────────────────────────────────────
        if (refund.issueCategoryLabel != null ||
            refund.description != null) ...[
          const SizedBox(height: 12),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ISSUE DETAILS',
                  style: tt.labelSmall?.copyWith(
                    color: AppColors.textHint,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 10),
                if (refund.issueCategoryLabel != null)
                  _DetailRow(
                    label: 'Category',
                    value: refund.issueCategoryLabel!,
                  ),
                if (refund.description != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Description',
                    style: tt.labelSmall?.copyWith(
                      color: AppColors.textHint,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    refund.description!,
                    style: tt.bodySmall?.copyWith(
                      color: AppColors.textPrimary,
                      height: 1.6,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],

        // ── Decision notes ───────────────────────────────────────────────
        if (refund.decisionNotes != null) ...[
          const SizedBox(height: 12),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.admin_panel_settings_outlined,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'DODO SUPPORT NOTE',
                      style: tt.labelSmall?.copyWith(
                        color: AppColors.textHint,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  refund.decisionNotes!,
                  style: tt.bodySmall?.copyWith(
                    color: AppColors.textPrimary,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],

        // ── Transactions ─────────────────────────────────────────────────
        if (refund.transactions.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'REFUND TRANSACTIONS',
                  style: tt.labelSmall?.copyWith(
                    color: AppColors.textHint,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 10),
                ...refund.transactions.map(
                  (txn) => _TransactionTile(txn: txn),
                ),
                _RefundStatusBanner(refund: refund),
              ],
            ),
          ),
        ],

        // ── Bank/UPI details submission prompt (COD) ─────────────────────
        if (refund.needsBankDetails) ...[
          const SizedBox(height: 12),
          _BankDetailsPromptCard(refund: refund),
        ],

        // ── "Needs action" prompt (more info) ────────────────────────────
        if (refund.status == 'more_info_requested') ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.warning.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.warning.withAlpha(60)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.notifications_active_rounded,
                  color: AppColors.warning,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'DODO Support has requested more information. '
                    'Please respond in the Messages tab.',
                    style: tt.bodySmall?.copyWith(
                      color: AppColors.textPrimary,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ── Timeline tab ───────────────────────────────────────────────────────────────

class _TimelineTab extends StatelessWidget {
  const _TimelineTab({required this.refund});
  final CustomerRefundModel refund;

  @override
  Widget build(BuildContext context) {
    if (refund.statusHistory.isEmpty) {
      return Center(
        child: Text(
          'No history available.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.textHint,
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: RefundTimelineWidget(events: refund.statusHistory),
    );
  }
}

// ── Messages tab ───────────────────────────────────────────────────────────────

class _MessagesTab extends StatefulWidget {
  const _MessagesTab({
    required this.refund,
    required this.msgCtrl,
    required this.sending,
    required this.pendingAttachments,
    required this.onSend,
    required this.onPickImages,
    required this.onRemoveAttachment,
  });

  final CustomerRefundModel refund;
  final TextEditingController msgCtrl;
  final bool sending;
  final List<_PendingAttachment> pendingAttachments;
  final VoidCallback onSend;
  final VoidCallback onPickImages;
  final void Function(int index) onRemoveAttachment;

  @override
  State<_MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<_MessagesTab> {
  final _scrollCtrl = ScrollController();

  @override
  void didUpdateWidget(_MessagesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Scroll to bottom when new messages arrive.
    if (widget.refund.messages.length !=
        oldWidget.refund.messages.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final messages = widget.refund.messages;

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 36,
                        color: AppColors.textHint,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No messages yet',
                        style: tt.bodySmall?.copyWith(
                          color: AppColors.textHint,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (widget.refund.canSendMessage)
                        Text(
                          'Send a message to DODO Support below.',
                          style: tt.bodySmall?.copyWith(
                            color: AppColors.textHint,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                )
              : ListView.separated(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  itemCount: messages.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) =>
                      RefundMessageItem(message: messages[i]),
                ),
        ),

        // ── Input bar (only when open) ────────────────────────────────
        if (widget.refund.canSendMessage) ...[
          // Pending image previews
          if (widget.pendingAttachments.isNotEmpty)
            Container(
              height: 82,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: AppColors.surfaceVariant,
                border: Border(
                    top: BorderSide(color: AppColors.border)),
              ),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.pendingAttachments.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final att = widget.pendingAttachments[i];
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          att.bytes,
                          width: 62,
                          height: 62,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: -6,
                        right: -6,
                        child: GestureDetector(
                          onTap: () => widget.onRemoveAttachment(i),
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: const BoxDecoration(
                              color: AppColors.error,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                size: 11, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          const Divider(height: 1, color: AppColors.divider),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              child: Row(
                children: [
                  // Attach image button
                  IconButton(
                    icon: const Icon(Icons.attach_file_rounded,
                        color: AppColors.textSecondary),
                    onPressed: widget.sending ? null : widget.onPickImages,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                    tooltip: 'Attach image',
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: widget.msgCtrl,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Type a message…',
                        hintStyle: TextStyle(
                          color: AppColors.textHint,
                          fontSize: 14,
                        ),
                        filled: true,
                        fillColor: AppColors.surfaceVariant,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide:
                              const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide:
                              const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SendButton(
                    sending: widget.sending,
                    onSend: widget.onSend,
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          const Divider(height: 1, color: AppColors.divider),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'This query is ${widget.refund.statusLabel.toLowerCase()} — '
                'messaging is no longer available.',
                style: tt.bodySmall?.copyWith(
                  color: AppColors.textHint,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.sending, required this.onSend});
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: sending ? AppColors.primary.withAlpha(160) : AppColors.primary,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: sending ? null : onSend,
        icon: sending
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.send_rounded, size: 18, color: Colors.white),
      ),
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: tt.bodySmall?.copyWith(
                color: AppColors.textHint,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: tt.bodySmall?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountCell extends StatelessWidget {
  const _AmountCell({
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
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: tt.labelSmall?.copyWith(
              color: AppColors.textHint,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: tt.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bank details prompt card ───────────────────────────────────────────────────

class _BankDetailsPromptCard extends ConsumerStatefulWidget {
  const _BankDetailsPromptCard({required this.refund});
  final CustomerRefundModel refund;

  @override
  ConsumerState<_BankDetailsPromptCard> createState() =>
      _BankDetailsPromptCardState();
}

class _BankDetailsPromptCardState
    extends ConsumerState<_BankDetailsPromptCard> {
  bool _submitting = false;

  Future<void> _openSubmitForm() async {
    final details = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _BankDetailsForm(),
    );
    if (details == null || !mounted) return;

    setState(() => _submitting = true);
    try {
      await ref
          .read(refundQueriesServiceProvider)
          .submitBankUpiDetails(widget.refund.id, details);
      ref.invalidate(refundQueryDetailProvider(widget.refund.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEBF8FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF90CDF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_rounded,
                  size: 16, color: Color(0xFF2B6CB0)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Bank/UPI Details Required',
                  style: tt.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF2B6CB0),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your refund has been approved. Since your payment was Cash on Delivery, '
            'please provide your bank account or UPI details so we can transfer the refund.',
            style: tt.bodySmall?.copyWith(
              color: const Color(0xFF2C5282),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _openSubmitForm,
              icon: _submitting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.add_card_rounded, size: 16),
              label: Text(
                  _submitting ? 'Submitting…' : 'Submit Bank/UPI Details'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2B6CB0),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bank details submission form (bottom sheet) ───────────────────────────────

class _BankDetailsForm extends StatefulWidget {
  const _BankDetailsForm();

  @override
  State<_BankDetailsForm> createState() => _BankDetailsFormState();
}

class _BankDetailsFormState extends State<_BankDetailsForm> {
  final _formKey = GlobalKey<FormState>();
  String _type = 'bank';

  final _holderCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _ifscCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController();
  final _upiCtrl = TextEditingController();

  @override
  void dispose() {
    _holderCtrl.dispose();
    _accountCtrl.dispose();
    _ifscCtrl.dispose();
    _bankNameCtrl.dispose();
    _upiCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final Map<String, dynamic> details;
    if (_type == 'bank') {
      details = {
        'type': 'bank',
        'account_holder_name': _holderCtrl.text.trim(),
        'account_number': _accountCtrl.text.trim(),
        'ifsc_code': _ifscCtrl.text.trim().toUpperCase(),
        if (_bankNameCtrl.text.trim().isNotEmpty)
          'bank_name': _bankNameCtrl.text.trim(),
      };
    } else {
      details = {
        'type': 'upi',
        'upi_id': _upiCtrl.text.trim(),
      };
    }
    Navigator.of(context).pop(details);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Submit Bank/UPI Details',
                  style: tt.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  )),
              const SizedBox(height: 4),
              Text(
                'Your details are kept confidential and used only for this refund transfer.',
                style: tt.bodySmall?.copyWith(
                    color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 16),

              // Transfer type selector
              Row(
                children: [
                  Expanded(
                    child: _TypeButton(
                      label: 'Bank Account',
                      icon: Icons.account_balance_rounded,
                      selected: _type == 'bank',
                      onTap: () => setState(() => _type = 'bank'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TypeButton(
                      label: 'UPI',
                      icon: Icons.phone_android_rounded,
                      selected: _type == 'upi',
                      onTap: () => setState(() => _type = 'upi'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              if (_type == 'bank') ...[
                _FormField(
                  controller: _holderCtrl,
                  label: 'Account Holder Name',
                  hint: 'As per bank records',
                  validator: (v) => (v?.trim().isEmpty ?? true)
                      ? 'Required'
                      : null,
                ),
                const SizedBox(height: 12),
                _FormField(
                  controller: _accountCtrl,
                  label: 'Account Number',
                  hint: 'Enter your account number',
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return 'Required';
                    if (s.length < 8) return 'Enter a valid account number';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _FormField(
                  controller: _ifscCtrl,
                  label: 'IFSC Code',
                  hint: 'e.g. HDFC0001234',
                  textCapitalization: TextCapitalization.characters,
                  validator: (v) {
                    final s = v?.trim().toUpperCase() ?? '';
                    if (s.isEmpty) return 'Required';
                    if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(s)) {
                      return 'Enter a valid IFSC code';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _FormField(
                  controller: _bankNameCtrl,
                  label: 'Bank Name (optional)',
                  hint: 'e.g. HDFC Bank',
                ),
              ] else ...[
                _FormField(
                  controller: _upiCtrl,
                  label: 'UPI ID',
                  hint: 'e.g. name@upi or 9876543210@paytm',
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return 'Required';
                    if (!s.contains('@')) return 'Enter a valid UPI ID';
                    return null;
                  },
                ),
              ],

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Submit Details'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeButton extends StatelessWidget {
  const _TypeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withAlpha(18)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 20,
                color: selected
                    ? AppColors.primary
                    : AppColors.textSecondary),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
  });
  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

// ── Pending attachment data holder (used before upload) ───────────────────────

class _PendingAttachment {
  final Uint8List bytes;
  final String filename;
  final String mimeType;
  const _PendingAttachment(
      {required this.bytes,
      required this.filename,
      required this.mimeType});
}

// ── Refund status message banner ──────────────────────────────────────────────

class _RefundStatusBanner extends StatelessWidget {
  const _RefundStatusBanner({required this.refund});
  final CustomerRefundModel refund;

  @override
  Widget build(BuildContext context) {
    final txns = refund.transactions;

    final completedAmount = txns
        .where((t) => t.isCompleted)
        .fold<double>(0, (sum, t) => sum + t.amount);

    final activeAmount = txns
        .where((t) => t.isPending || t.isProcessing)
        .fold<double>(0, (sum, t) => sum + t.amount);

    String? message;
    Color bgColor;
    Color borderColor;
    Color iconColor;
    IconData icon;

    if (completedAmount > 0) {
      final amt = '₹${completedAmount.toStringAsFixed(0)}';
      message = refund.isCodBooking
          ? 'Your refund of $amt has been marked as transferred. '
              'Please check your bank account or UPI for the credited amount.'
          : 'Your refund of $amt has been processed successfully. '
              'Please allow a few business days for the amount to reflect in your account.';
      bgColor = AppColors.success.withAlpha(16);
      borderColor = AppColors.success.withAlpha(60);
      iconColor = AppColors.success;
      icon = Icons.check_circle_outline_rounded;
    } else if (activeAmount > 0) {
      final amt = '₹${activeAmount.toStringAsFixed(0)}';
      message = refund.isCodBooking
          ? 'Your refund of $amt has been initiated to your submitted '
              'bank account/UPI ID. It is expected to reflect within 3–4 business days.'
          : 'Your refund of $amt has been initiated to your original payment method. '
              'It is expected to reflect in your bank account within 5–7 business days.';
      bgColor = const Color(0xFF1A73E8).withAlpha(14);
      borderColor = const Color(0xFF1A73E8).withAlpha(50);
      iconColor = const Color(0xFF1A73E8);
      icon = Icons.schedule_rounded;
    } else {
      return const SizedBox.shrink();
    }

    final tt = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: tt.bodySmall?.copyWith(
                color: AppColors.textPrimary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Transaction tile ───────────────────────────────────────────────────────────

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.txn});
  final RefundTransactionModel txn;

  static Color _statusColor(RefundTransactionModel t) {
    if (t.isCompleted) return AppColors.success;
    if (t.isFailed) return AppColors.error;
    if (t.isProcessing) return const Color(0xFF9C27B0);
    return AppColors.textSecondary;
  }

  static String _statusLabel(RefundTransactionModel t) {
    if (t.isCompleted) return 'Completed';
    if (t.isFailed) return 'Failed';
    if (t.isProcessing) return 'Processing';
    return 'Pending';
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final color = _statusColor(txn);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '₹${txn.amount.toStringAsFixed(0)} via ${txn.refundMethod}',
                  style: tt.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: color.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _statusLabel(txn),
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            txn.gateway,
            style: tt.labelSmall?.copyWith(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          if (txn.completedAt != null) ...[
            const SizedBox(height: 2),
            Text(
              'Completed ${DateFormat("d MMM yyyy, h:mm a").format(txn.completedAt!.toLocal())}',
              style: tt.labelSmall?.copyWith(
                color: AppColors.textHint,
                fontSize: 10,
              ),
            ),
          ],
          if (txn.failureReason != null) ...[
            const SizedBox(height: 4),
            Text(
              txn.failureReason!,
              style: tt.bodySmall?.copyWith(
                color: AppColors.error,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
