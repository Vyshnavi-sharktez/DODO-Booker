import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/subscription_plan.dart';
import '../../domain/models/vendor_subscription.dart';

class VendorSubscriptionDialog extends StatefulWidget {
  const VendorSubscriptionDialog({
    super.key,
    this.existing,
    required this.plans,
    required this.vendorId,
    required this.vendorName,
    required this.onSave,
    this.onAddPayment,
    this.onRenew,
  });

  final VendorSubscription? existing;
  final List<SubscriptionPlan> plans;
  final String vendorId;
  final String vendorName;
  final Future<void> Function({
    required String? planId,
    required String status,
    DateTime? startDate,
    DateTime? expiryDate,
    String? notes,
  }) onSave;
  final Future<void> Function({
    required String paymentType,
    required double amount,
    required String status,
    String? paymentReference,
    DateTime? paidAt,
    String? notes,
  })? onAddPayment;
  final Future<void> Function(DateTime newExpiry)? onRenew;

  @override
  State<VendorSubscriptionDialog> createState() => _VendorSubscriptionDialogState();
}

class _VendorSubscriptionDialogState extends State<VendorSubscriptionDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _formKey = GlobalKey<FormState>();
  late String? _planId;
  late String _status;
  DateTime? _startDate;
  DateTime? _expiryDate;
  late final TextEditingController _notesCtrl;
  bool _saving = false;

  // Payment form
  final _payFormKey = GlobalKey<FormState>();
  final _payAmtCtrl = TextEditingController();
  final _payRefCtrl = TextEditingController();
  final _payNotesCtrl = TextEditingController();
  String _payType = 'subscription_fee';
  String _payStatus = 'paid';
  DateTime? _paidAt;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
        length: widget.existing != null ? 3 : 1, vsync: this);
    final s = widget.existing;
    // For catalog subscriptions plan_id is always null; don't fall back to the
    // first global plan or the admin would accidentally assign a global plan.
    final isCatalogSub = s?.catalogNodeId != null;
    _planId = s?.planId ?? (isCatalogSub ? null : (widget.plans.isNotEmpty ? widget.plans.first.id : null));
    _status = s?.status ?? 'active';
    _startDate = s?.startDate;
    _expiryDate = s?.expiryDate;
    _notesCtrl = TextEditingController(text: s?.notes ?? '');
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _notesCtrl.dispose();
    _payAmtCtrl.dispose();
    _payRefCtrl.dispose();
    _payNotesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _startDate : _expiryDate) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _expiryDate = picked;
      }
    });
  }

  Future<void> _submitSubscription() async {
    if (!_formKey.currentState!.validate()) return;
    final isCatalogSub = widget.existing?.catalogNodeId != null;
    if (!isCatalogSub && _planId == null) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        planId: _planId,
        status: _status,
        startDate: _startDate,
        expiryDate: _expiryDate,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submitPayment() async {
    if (!_payFormKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onAddPayment!(
        paymentType: _payType,
        amount: double.parse(_payAmtCtrl.text.trim()),
        status: _payStatus,
        paymentReference: _payRefCtrl.text.trim().isEmpty ? null : _payRefCtrl.text.trim(),
        paidAt: _paidAt,
        notes: _payNotesCtrl.text.trim().isEmpty ? null : _payNotesCtrl.text.trim(),
      );
      if (mounted) {
        _payAmtCtrl.clear();
        _payRefCtrl.clear();
        _payNotesCtrl.clear();
        setState(() => _paidAt = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment recorded')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final fmt = DateFormat('d MMM yyyy');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.card_membership_rounded,
                        color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEdit ? 'Manage Subscription' : 'Assign Subscription',
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary),
                        ),
                        Text(widget.vendorName,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            if (isEdit)
              TabBar(
                controller: _tabCtrl,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.primary,
                tabs: const [
                  Tab(text: 'Details'),
                  Tab(text: 'Payments'),
                  Tab(text: 'Add Payment'),
                ],
              ),

            Expanded(
              child: isEdit
                  ? TabBarView(
                      controller: _tabCtrl,
                      children: [
                        _detailsForm(fmt),
                        _paymentHistory(),
                        _addPaymentForm(fmt),
                      ],
                    )
                  : _detailsForm(fmt),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailsForm(DateFormat fmt) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.existing?.catalogNodeId != null) ...[
              _label('Catalog'),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_tree_rounded,
                        size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      widget.existing!.catalogNodeName ?? 'Catalog Subscription',
                      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
            ] else ...[
              _label('Plan'),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _planId,
                decoration: _inputDecoration(),
                validator: (v) => v == null ? 'Select a plan' : null,
                items: widget.plans
                    .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                    .toList(),
                onChanged: (v) => setState(() => _planId = v),
              ),
            ],
            const SizedBox(height: 14),

            _label('Status'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: _inputDecoration(),
              items: kSubscriptionStatuses
                  .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(s[0].toUpperCase() + s.substring(1)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _status = v!),
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(child: _datePicker('Start Date', _startDate, fmt, () => _pickDate(true))),
                const SizedBox(width: 12),
                Expanded(child: _datePicker('Expiry Date', _expiryDate, fmt, () => _pickDate(false))),
              ],
            ),
            const SizedBox(height: 14),

            _label('Notes'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: _inputDecoration(hint: 'Optional internal notes'),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _saving ? null : _submitSubscription,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                  child: _saving
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(widget.existing != null ? 'Update' : 'Assign'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentHistory() {
    final payments = widget.existing?.payments ?? [];
    if (payments.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, size: 40, color: AppColors.textSecondary),
            SizedBox(height: 10),
            Text('No payments recorded', style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }
    final fmt = DateFormat('d MMM yyyy');
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: payments.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final p = payments[i];
        final statusColor = p.status == 'paid'
            ? AppColors.success
            : p.status == 'failed'
                ? AppColors.error
                : AppColors.warning;
        return ListTile(
          dense: true,
          leading: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.receipt_outlined, size: 18, color: statusColor),
          ),
          title: Text('${p.paymentType.replaceAll('_', ' ').toUpperCase()} • ₹${p.amount.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: Text(p.paidAt != null ? fmt.format(p.paidAt!) : 'Not paid'),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(p.status, style: TextStyle(color: statusColor, fontSize: 11)),
          ),
        );
      },
    );
  }

  Widget _addPaymentForm(DateFormat fmt) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Form(
        key: _payFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Payment Type'),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _payType,
                        decoration: _inputDecoration(),
                        items: kPaymentTypes
                            .map((t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(t.replaceAll('_', ' ').toUpperCase()),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _payType = v!),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Status'),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _payStatus,
                        decoration: _inputDecoration(),
                        items: kPaymentStatuses
                            .map((s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(s[0].toUpperCase() + s.substring(1)),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _payStatus = v!),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _label('Amount'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _payAmtCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
              decoration: _inputDecoration(hint: '0.00'),
              validator: (v) {
                if (v?.trim().isEmpty == true) return 'Required';
                if (double.tryParse(v!) == null) return 'Invalid number';
                return null;
              },
            ),
            const SizedBox(height: 14),
            _label('Payment Reference'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _payRefCtrl,
              decoration: _inputDecoration(hint: 'e.g. TXN12345 (optional)'),
            ),
            const SizedBox(height: 14),
            _datePicker('Paid At', _paidAt, fmt,
                () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _paidAt ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) setState(() => _paidAt = picked);
                }),
            const SizedBox(height: 14),
            _label('Notes'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _payNotesCtrl,
              maxLines: 2,
              decoration: _inputDecoration(hint: 'Optional'),
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving ? null : _submitPayment,
                style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                icon: _saving
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add_rounded, size: 18),
                label: const Text('Record Payment'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _datePicker(String label, DateTime? date, DateFormat fmt, VoidCallback onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  date != null ? fmt.format(date) : 'Select date',
                  style: TextStyle(
                    fontSize: 14,
                    color: date != null ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary));

  InputDecoration _inputDecoration({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        filled: true,
        fillColor: AppColors.background,
      );
}
