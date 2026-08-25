import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class CodCashConfirmationDialog extends StatefulWidget {
  const CodCashConfirmationDialog({
    super.key,
    required this.bookingNumber,
    required this.totalAmount,
  });

  final String bookingNumber;
  final double totalAmount;

  @override
  State<CodCashConfirmationDialog> createState() =>
      _CodCashConfirmationDialogState();
}

class _CodCashConfirmationDialogState
    extends State<CodCashConfirmationDialog> {
  bool? _cashCollected;
  final TextEditingController _reasonController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    if (_cashCollected == null) {
      setState(() => _error = 'Please select whether cash was collected.');
      return;
    }

    if (_cashCollected == false && _reasonController.text.trim().isEmpty) {
      setState(
          () => _error = 'Reason is required when cash is not collected.');
      return;
    }

    Navigator.of(context).pop({
      'cashCollected': _cashCollected!,
      'reason': _cashCollected == false ? _reasonController.text.trim() : null,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.payments_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'COD Cash Confirmation',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Booking #${widget.bookingNumber}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Collectable Cash Amount:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '₹${widget.totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Did you collect the cash payment from the customer?',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _cashCollected = true;
                        _error = null;
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _cashCollected == true
                            ? AppColors.success.withValues(alpha: 0.12)
                            : Colors.white,
                        border: Border.all(
                          color: _cashCollected == true
                              ? AppColors.success
                              : Colors.grey.shade300,
                          width: _cashCollected == true ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            color: _cashCollected == true
                                ? AppColors.success
                                : Colors.grey.shade400,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Cash Collected',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _cashCollected == true
                                  ? AppColors.success
                                  : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _cashCollected = false;
                        _error = null;
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _cashCollected == false
                            ? AppColors.warning.withValues(alpha: 0.12)
                            : Colors.white,
                        border: Border.all(
                          color: _cashCollected == false
                              ? AppColors.warning
                              : Colors.grey.shade300,
                          width: _cashCollected == false ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.cancel_rounded,
                            color: _cashCollected == false
                                ? AppColors.warning
                                : Colors.grey.shade400,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Cash Not Collected',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _cashCollected == false
                                  ? AppColors.warning
                                  : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_cashCollected == false) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _reasonController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Reason for non-collection *',
                  hintText: 'Enter reason why cash was not collected...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.error,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Submit Confirmation'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
