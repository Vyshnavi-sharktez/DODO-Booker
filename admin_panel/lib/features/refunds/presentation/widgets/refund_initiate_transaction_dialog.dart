import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../domain/models/refund_request.dart';

class InitiateTransactionResult {
  final double amount;
  final String gateway;
  final String refundMethod;
  final String? notes;

  const InitiateTransactionResult({
    required this.amount,
    required this.gateway,
    required this.refundMethod,
    this.notes,
  });
}

class RefundInitiateTransactionDialog extends StatefulWidget {
  final RefundRequest request;
  final double refundableBalance;

  const RefundInitiateTransactionDialog({
    super.key,
    required this.request,
    required this.refundableBalance,
  });

  @override
  State<RefundInitiateTransactionDialog> createState() =>
      _RefundInitiateTransactionDialogState();
}

class _RefundInitiateTransactionDialogState
    extends State<RefundInitiateTransactionDialog> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool get _isCod =>
      widget.request.paymentMethodSnapshot == 'cash' ||
      widget.request.paymentMethodSnapshot == 'cod';

  String get _gateway => _isCod ? 'manual' : 'razorpay';
  String get _refundMethod =>
      _isCod ? 'manual' : 'original_payment_method';

  @override
  void initState() {
    super.initState();
    final approved = widget.request.approvedAmount;
    final balance = widget.refundableBalance;
    final defaultAmount = approved != null
        ? (approved < balance ? approved : balance)
        : balance;
    _amountController.text = defaultAmount.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) return;

    Navigator.of(context).pop(InitiateTransactionResult(
      amount: amount,
      gateway: _gateway,
      refundMethod: _refundMethod,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isCod
                      ? 'Initiate Manual Bank/UPI Transfer'
                      : 'Initiate Razorpay Refund',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2D3748)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ticket ${r.ticketNumber}',
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF718096)),
                ),
                const SizedBox(height: 20),

                // ── Financial summary ─────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      if (!_isCod)
                        _Row('Payment gateway', 'Razorpay'),
                      if (!_isCod)
                        const SizedBox(height: 4),
                      _Row('Approved amount',
                          '₹${(r.approvedAmount ?? r.requestedAmount).toStringAsFixed(2)}'),
                      const SizedBox(height: 4),
                      _Row('Already refunded',
                          '₹${r.processedAmount.toStringAsFixed(2)}'),
                      const Divider(height: 16),
                      _Row(
                        'Remaining refundable',
                        '₹${widget.refundableBalance.toStringAsFixed(2)}',
                        valueColor: const Color(0xFF38A169),
                      ),
                    ],
                  ),
                ),

                // ── COD: customer bank/UPI details ────────────────────────
                if (_isCod && r.bankUpiDetails != null) ...[
                  const SizedBox(height: 16),
                  _BankUpiDetailsCard(details: r.bankUpiDetails!),
                ],

                const SizedBox(height: 16),

                // ── Amount field ──────────────────────────────────────────
                TextFormField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}'))
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Transaction amount (₹)',
                    border: OutlineInputBorder(),
                    prefixText: '₹ ',
                  ),
                  validator: (v) {
                    final d = double.tryParse(v ?? '');
                    if (d == null || d <= 0) return 'Enter a valid amount';
                    if (d > widget.refundableBalance) {
                      return 'Exceeds remaining refundable balance '
                          '(₹${widget.refundableBalance.toStringAsFixed(2)})';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                TextField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Context-specific info box ─────────────────────────────
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3CD),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _isCod
                        ? 'After initiating, manually transfer the approved amount '
                          'to the customer\'s bank account or UPI ID above. '
                          'Record the transfer reference (UTR) when marking '
                          'the transaction complete.'
                        : 'After initiating, use "Process via Razorpay" in the '
                          'Transactions tab to send the refund. The amount will be '
                          'returned to the customer\'s original payment method.',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF856404)),
                  ),
                ),

                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _submit,
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF805AD5)),
                      child: Text(_isCod
                          ? 'Initiate Transfer'
                          : 'Initiate Refund'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Bank/UPI details display card ─────────────────────────────────────────────

class _BankUpiDetailsCard extends StatelessWidget {
  final Map<String, dynamic> details;
  const _BankUpiDetailsCard({required this.details});

  @override
  Widget build(BuildContext context) {
    final type = details['type'] as String? ?? '';
    final isBank = type == 'bank';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEBF8FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF90CDF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isBank ? Icons.account_balance : Icons.phone_android,
                size: 14,
                color: const Color(0xFF2B6CB0),
              ),
              const SizedBox(width: 6),
              Text(
                isBank
                    ? 'Customer Bank Account'
                    : 'Customer UPI ID',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2B6CB0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (isBank) ...[
            if (details['account_holder_name'] != null)
              _DetailLine('Account holder',
                  details['account_holder_name'] as String),
            _DetailLine('Account number',
                details['account_number'] as String? ?? '—'),
            _DetailLine('IFSC code',
                details['ifsc_code'] as String? ?? '—'),
            if (details['bank_name'] != null &&
                (details['bank_name'] as String).isNotEmpty)
              _DetailLine('Bank', details['bank_name'] as String),
          ] else ...[
            _DetailLine('UPI ID', details['upi_id'] as String? ?? '—'),
          ],
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  final String label;
  final String value;
  const _DetailLine(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF4A5568))),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2D3748),
                  fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _Row(this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 13, color: Color(0xFF718096))),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: valueColor ?? const Color(0xFF2D3748),
          ),
        ),
      ],
    );
  }
}
