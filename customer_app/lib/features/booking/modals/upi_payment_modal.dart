import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_modal_dialog.dart';

/// Shows DODO's UPI ID and QR code. Customer copies/scans and confirms payment.
/// Pops with a String: 'upi_dodo' or 'upi_dodo:$utr' (if UTR provided), or null (dismissed).
class UpiPaymentModal extends StatefulWidget {
  final String upiId;
  final String? qrImageUrl;
  final double totalAmount;

  const UpiPaymentModal({
    super.key,
    required this.upiId,
    this.qrImageUrl,
    required this.totalAmount,
  });

  @override
  State<UpiPaymentModal> createState() => _UpiPaymentModalState();
}

class _UpiPaymentModalState extends State<UpiPaymentModal> {
  final _utrCtrl = TextEditingController();

  @override
  void dispose() {
    _utrCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    final utr = _utrCtrl.text.trim();
    final result = utr.isEmpty ? 'upi_dodo' : 'upi_dodo:$utr';
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return AppModalDialog(
      title: 'Pay via UPI',
      subtitle: const Text('Scan or copy the UPI ID below'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),

          // Amount due
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Amount to Pay',
                  style: tt.labelMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '₹${widget.totalAmount.toStringAsFixed(2)}',
                  style: tt.titleMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // QR code image
          if (widget.qrImageUrl != null && widget.qrImageUrl!.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                widget.qrImageUrl!,
                height: 200,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // UPI ID row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.qr_code_rounded, color: AppColors.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('UPI ID',
                          style: tt.labelSmall
                              ?.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 2),
                      Text(
                        widget.upiId,
                        style: tt.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: widget.upiId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('UPI ID copied'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded,
                      color: AppColors.primary, size: 18),
                  tooltip: 'Copy UPI ID',
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Instructions
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF9C4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '1. Open any UPI app (PhonePe, GPay, Paytm, etc.)\n'
              '2. Send the exact amount to the UPI ID above\n'
              '3. Note down the UTR/transaction ID and enter below\n'
              '4. Tap "I have paid" to confirm',
              style: TextStyle(fontSize: 12, color: Color(0xFF795548)),
            ),
          ),

          const SizedBox(height: 16),

          // Optional UTR field
          TextField(
            controller: _utrCtrl,
            decoration: InputDecoration(
              labelText: 'UTR / Transaction ID (optional)',
              hintText: 'e.g. 416123456789',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              prefixIcon: const Icon(Icons.receipt_long_outlined, size: 18),
            ),
          ),

          const SizedBox(height: 20),

          FilledButton.icon(
            onPressed: _confirm,
            icon: const Icon(Icons.check_circle_rounded, size: 18),
            label: const Text('I have paid'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F9D58),
              minimumSize: const Size(double.infinity, 50),
            ),
          ),

          const SizedBox(height: 10),

          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text('Cancel',
                style: tt.bodyMedium?.copyWith(color: AppColors.textSecondary)),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
