import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../domain/models/refund_request.dart';

class RefundApproveDialog extends StatefulWidget {
  final RefundRequest request;

  const RefundApproveDialog({super.key, required this.request});

  @override
  State<RefundApproveDialog> createState() => _RefundApproveDialogState();
}

class _RefundApproveDialogState extends State<RefundApproveDialog> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _error;

  @override
  void initState() {
    super.initState();
    // Default to the full requested amount
    _amountController.text =
        widget.request.requestedAmount.toStringAsFixed(2);
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
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    if (amount > widget.request.amountPaidSnapshot) {
      setState(() => _error =
          'Amount cannot exceed the collected payment (₹${widget.request.amountPaidSnapshot.toStringAsFixed(2)}).');
      return;
    }
    setState(() => _error = null);
    Navigator.of(context).pop(_ApproveResult(
      approvedAmount: amount,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final isPartial = () {
      final v = double.tryParse(_amountController.text.trim());
      return v != null && v < r.requestedAmount;
    }();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Approve Refund',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2D3748),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ticket ${r.ticketNumber}  ·  Requested ₹${r.requestedAmount.toStringAsFixed(2)}',
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFF718096)),
                ),
                const SizedBox(height: 20),
                _InfoRow('Collected amount',
                    '₹${r.amountPaidSnapshot.toStringAsFixed(2)}'),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Approved amount (₹)',
                    border: OutlineInputBorder(),
                    prefixText: '₹ ',
                  ),
                  validator: (v) {
                    final d = double.tryParse(v ?? '');
                    if (d == null || d <= 0) return 'Enter a valid amount';
                    if (d > r.amountPaidSnapshot) {
                      return 'Cannot exceed ₹${r.amountPaidSnapshot.toStringAsFixed(2)}';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                if (isPartial)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3CD),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 14, color: Color(0xFF856404)),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Amount is less than requested — this will be a partial approval.',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF856404)),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Decision notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: const TextStyle(
                          color: Color(0xFFE53E3E), fontSize: 13)),
                ],
                const SizedBox(height: 24),
                const Text(
                  'Approval does NOT initiate any money movement. '
                  'A separate "Initiate Refund" action is required.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF718096)),
                ),
                const SizedBox(height: 16),
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
                          backgroundColor: const Color(0xFF38A169)),
                      child: Text(isPartial ? 'Partially Approve' : 'Approve'),
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

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 13, color: Color(0xFF718096))),
        const Spacer(),
        Text(value,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2D3748))),
      ],
    );
  }
}

class _ApproveResult {
  final double approvedAmount;
  final String? notes;
  const _ApproveResult({required this.approvedAmount, this.notes});
}

// Expose the result type
typedef ApproveResult = _ApproveResult;
