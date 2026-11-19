import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/cancellation_fee_info.dart';

// ── Fee banner ────────────────────────────────────────────────────────────────

class _CancellationFeeBanner extends StatelessWidget {
  final CancellationFeeInfo feeInfo;
  const _CancellationFeeBanner({required this.feeInfo});

  @override
  Widget build(BuildContext context) {
    if (!feeInfo.hasFee) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF16A34A).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF16A34A).withValues(alpha: 0.3)),
        ),
        child: Row(
          children: const [
            Icon(Icons.check_circle_outline_rounded, size: 16, color: Color(0xFF16A34A)),
            SizedBox(width: 8),
            Text('Free cancellation',
                style: TextStyle(fontSize: 13, color: Color(0xFF16A34A), fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }

    final feeText = '₹${feeInfo.feeAmount.toStringAsFixed(0)}';
    final String subtitle;
    if (feeInfo.isCod) {
      subtitle = '$feeText will be added to your outstanding balance and collected at next checkout.';
    } else {
      final refundText = '₹${feeInfo.refundAmount.toStringAsFixed(0)}';
      subtitle = '$feeText cancellation fee — $refundText will be refunded.';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.error),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(feeInfo.reasonMessage,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.error, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(fontSize: 12, color: AppColors.error)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CancelBookingResult {
  final String reason;
  final String? remarks;

  const CancelBookingResult({
    required this.reason,
    this.remarks,
  });
}

class CancelBookingReasonOption {
  final String key;
  final String label;

  const CancelBookingReasonOption(this.key, this.label);
}

const List<CancelBookingReasonOption> kCancellationReasonOptions = [
  CancelBookingReasonOption(
    'vendor_did_not_arrive',
    'Vendor did not arrive / delayed',
  ),
  CancelBookingReasonOption(
    'vendor_unreachable',
    'Vendor unreachable / no response',
  ),
  CancelBookingReasonOption(
    'found_another_provider',
    'Found another service provider',
  ),
  CancelBookingReasonOption(
    'plans_changed',
    'Plans changed / No longer needed',
  ),
  CancelBookingReasonOption(
    'booked_by_mistake',
    'Booked by mistake / duplicate',
  ),
  CancelBookingReasonOption(
    'other',
    'Other',
  ),
];

class CancelBookingReasonDialog extends StatefulWidget {
  const CancelBookingReasonDialog({super.key, CancellationFeeInfo? feeInfo})
      : feeInfo = feeInfo ?? const CancellationFeeInfo(
            feeAmount: 0, refundAmount: 0, isCod: false);
  final CancellationFeeInfo feeInfo;

  @override
  State<CancelBookingReasonDialog> createState() =>
      _CancelBookingReasonDialogState();
}

class _CancelBookingReasonDialogState
    extends State<CancelBookingReasonDialog> {
  String? _selectedReasonKey;
  final _remarksController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _remarksController.addListener(_onRemarksChanged);
  }

  @override
  void dispose() {
    _remarksController.removeListener(_onRemarksChanged);
    _remarksController.dispose();
    super.dispose();
  }

  void _onRemarksChanged() {
    if (_selectedReasonKey == 'other') {
      setState(() {});
    }
  }

  bool get _isValid {
    if (_selectedReasonKey == null) return false;
    if (_selectedReasonKey == 'other') {
      return _remarksController.text.trim().isNotEmpty;
    }
    return true;
  }

  void _onConfirm() {
    if (!_isValid) return;

    final selectedOpt = kCancellationReasonOptions.firstWhere(
      (opt) => opt.key == _selectedReasonKey,
    );

    final remarks = _remarksController.text.trim();

    Navigator.of(context).pop(
      CancelBookingResult(
        reason: selectedOpt.label,
        remarks: remarks.isNotEmpty ? remarks : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.cancel_outlined,
                      color: AppColors.error,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Cancel Booking',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Please select a reason for cancellation',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 12),

              // Cancellation fee banner
              _CancellationFeeBanner(feeInfo: widget.feeInfo),
              const SizedBox(height: 12),

              // Reason List
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final opt in kCancellationReasonOptions)
                        InkWell(
                          onTap: () {
                            setState(() {
                              _selectedReasonKey = opt.key;
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Row(
                              children: [
                                Radio<String>(
                                  value: opt.key,
                                  groupValue: _selectedReasonKey,
                                  activeColor: AppColors.primary,
                                  onChanged: (val) {
                                    setState(() {
                                      _selectedReasonKey = val;
                                    });
                                  },
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    opt.label,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Remarks input if 'Other' selected
                      if (_selectedReasonKey == 'other') ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _remarksController,
                          maxLines: 3,
                          maxLength: 250,
                          decoration: InputDecoration(
                            hintText: 'Please specify reason for cancellation...',
                            hintStyle: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textHint,
                            ),
                            contentPadding: const EdgeInsets.all(12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: AppColors.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: AppColors.primary),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Actions
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: _isValid ? _onConfirm : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.error,
                      disabledBackgroundColor:
                          AppColors.error.withValues(alpha: 0.35),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Confirm Cancellation',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      side: const BorderSide(color: AppColors.border),
                    ),
                    child: const Text(
                      'Keep Booking',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
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
