import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class RejectDialog extends StatefulWidget {
  const RejectDialog({super.key, required this.bookingNumber});

  final String bookingNumber;

  @override
  State<RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<RejectDialog> {
  static const _presetReasons = [
    'Too far away',
    'Not available at scheduled time',
    'Service not supported',
    'Personal emergency',
    'Other',
  ];

  String? _selected;
  final _otherController = TextEditingController();

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

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      title: Row(
        children: [
          Icon(Icons.cancel_outlined, color: AppColors.error, size: 20),
          const SizedBox(width: 8),
          const Text('Reject Service'),
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
            const SizedBox(height: 4),
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
                  Icon(Icons.info_outline_rounded,
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
          child: const Text('Reject'),
        ),
      ],
    );
  }
}
