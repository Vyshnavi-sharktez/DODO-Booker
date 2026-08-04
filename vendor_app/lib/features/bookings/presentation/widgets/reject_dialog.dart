import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../wallet/presentation/providers/wallet_provider.dart';

class RejectDialog extends ConsumerStatefulWidget {
  const RejectDialog({super.key, required this.bookingNumber});

  final String bookingNumber;

  @override
  ConsumerState<RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends ConsumerState<RejectDialog> {
  static const _presetReasons = [
    'Too far away',
    'Not available at scheduled time',
    'Service not supported',
    'Personal emergency',
    'Other',
  ];

  String? _selected;
  final _otherController = TextEditingController();

  bool _penaltyEnabled = false;
  double _penaltyAmount = 0.0;
  bool _loadingRule = true;

  @override
  void initState() {
    super.initState();
    _loadPenaltyRule();
  }

  Future<void> _loadPenaltyRule() async {
    try {
      final rule = await ref
          .read(walletRepositoryProvider)
          .fetchPenaltyRule('rejection');
      if (mounted) {
        setState(() {
          _penaltyEnabled = rule.isEnabled;
          _penaltyAmount = rule.amount;
          _loadingRule = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingRule = false);
      }
    }
  }

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  bool get _canConfirm {
    if (_selected == null) return false;
    if (_selected == 'Other') return _otherController.text.trim().isNotEmpty;
    return true;
  }

  String get _effectiveReason =>
      _selected == 'Other' ? _otherController.text.trim() : _selected!;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPenalty = _penaltyEnabled && _penaltyAmount > 0;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      title: Row(
        children: [
          Icon(
            hasPenalty ? Icons.warning_amber_rounded : Icons.cancel_outlined,
            color: hasPenalty ? AppColors.warning : AppColors.error,
            size: 22,
          ),
          const SizedBox(width: 8),
          Text(hasPenalty ? 'Reject Service (Penalty Warning)' : 'Reject Service'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Booking #${widget.bookingNumber}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),

            // Penalty Warning Card or Normal Info Banner
            if (_loadingRule)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (hasPenalty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Automatic Penalty Warning',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Rejecting this booking will incur an automatic penalty of ₹${_penaltyAmount.toStringAsFixed(2)} which will be deducted from your wallet balance.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textPrimary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Reason: Vendor Rejection Penalty',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 14, color: AppColors.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'This booking will be returned to the admin queue '
                        'for reassignment to another vendor.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _selected,
              hint: const Text('Select a reason *'),
              isExpanded: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.list_alt_rounded),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
              items: _presetReasons
                  .map(
                    (r) => DropdownMenuItem(value: r, child: Text(r)),
                  )
                  .toList(),
              onChanged: (v) => setState(() {
                _selected = v;
                if (v != 'Other') _otherController.clear();
              }),
            ),
            if (_selected == 'Other') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _otherController,
                decoration: const InputDecoration(
                  hintText: 'Describe your reason…',
                  prefixIcon: Icon(Icons.edit_note_rounded),
                  alignLabelWithHint: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 4),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canConfirm
              ? () => Navigator.of(context).pop(_effectiveReason)
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.error,
            disabledBackgroundColor: AppColors.error.withValues(alpha: 0.3),
          ),
          child: Text(
            hasPenalty
                ? 'Proceed & Pay ₹${_penaltyAmount.toStringAsFixed(2)}'
                : 'Reject',
          ),
        ),
      ],
    );
  }
}
