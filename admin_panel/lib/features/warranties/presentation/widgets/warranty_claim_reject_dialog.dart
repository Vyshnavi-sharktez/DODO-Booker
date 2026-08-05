import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/service_warranty.dart';
import '../../application/warranties_providers.dart';

class WarrantyClaimRejectDialog extends ConsumerStatefulWidget {
  final ServiceWarranty warranty;

  const WarrantyClaimRejectDialog({
    super.key,
    required this.warranty,
  });

  @override
  ConsumerState<WarrantyClaimRejectDialog> createState() =>
      _WarrantyClaimRejectDialogState();
}

class _WarrantyClaimRejectDialogState
    extends ConsumerState<WarrantyClaimRejectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reasonCtrl = TextEditingController();
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitRejection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(warrantiesRepositoryProvider);
      final bookingNum = widget.warranty.bookingNumber ?? widget.warranty.bookingId;

      await repo.rejectWarrantyClaim(
        warrantyId: widget.warranty.id,
        reworkBookingId: widget.warranty.reworkBookingId,
        customerId: widget.warranty.customerId,
        bookingNumber: bookingNum,
        reason: _reasonCtrl.text,
      );

      ref.invalidate(adminWarrantiesProvider);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookingNum = widget.warranty.bookingNumber ?? widget.warranty.bookingId;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cancel_outlined, color: AppColors.error, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reject Warranty Claim',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Booking #$bookingNum',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: AppColors.error, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const Text(
                'Mandatory Rejection Reason *',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _reasonCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Provide a clear explanation for the customer regarding why this claim is rejected...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.all(12),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Rejection reason is mandatory.';
                  }
                  if (val.trim().length < 5) {
                    return 'Please enter a valid rejection reason (min 5 chars).';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'Note: This reason will be sent directly to the customer in their status notification.',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _submitRejection,
          icon: _submitting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Icon(Icons.close_rounded, size: 16),
          label: Text(_submitting ? 'Rejecting...' : 'Confirm Rejection'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.error,
          ),
        ),
      ],
    );
  }
}
