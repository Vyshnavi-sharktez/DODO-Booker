import 'package:flutter/material.dart';
import '../../domain/models/refund_request.dart';

class RefundRejectDialog extends StatefulWidget {
  final RefundRequest request;

  const RefundRejectDialog({super.key, required this.request});

  @override
  State<RefundRejectDialog> createState() => _RefundRejectDialogState();
}

class _RefundRejectDialogState extends State<RefundRejectDialog> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) return;
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Reject Refund Request',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D3748),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Ticket ${widget.request.ticketNumber}',
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF718096)),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _reasonController,
                maxLines: 4,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Rejection reason *',
                  hintText:
                      'Explain why this request is being rejected…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _reasonController,
                    builder: (context, value, _) => FilledButton(
                      onPressed:
                          value.text.trim().isEmpty ? null : _submit,
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFE53E3E)),
                      child: const Text('Reject'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
