import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../providers/bookings_provider.dart';

class CodCashConfirmationDialog extends ConsumerStatefulWidget {
  const CodCashConfirmationDialog({super.key, required this.bookingId});

  final String bookingId;

  static Future<bool?> show(BuildContext context, {required String bookingId}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CodCashConfirmationDialog(bookingId: bookingId),
    );
  }

  @override
  ConsumerState<CodCashConfirmationDialog> createState() =>
      _CodCashConfirmationDialogState();
}

class _CodCashConfirmationDialogState
    extends ConsumerState<CodCashConfirmationDialog> {
  bool? _collected;
  final _reasonController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_collected == null) {
      setState(() => _error = 'Please select an option.');
      return;
    }
    if (_collected == false && _reasonController.text.trim().isEmpty) {
      setState(() => _error = 'Please provide a reason.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(bookingsRepositoryProvider).confirmCodCashCollection(
            bookingId: widget.bookingId,
            cashCollected: _collected!,
            notCollectedReason: _collected! ? null : _reasonController.text.trim(),
          );
      ref.invalidate(vendorBookingsProvider);
      if (mounted) Navigator.of(context).pop(_collected);
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Row(
        children: [
          Icon(Icons.payments_outlined, color: AppColors.primary, size: 22),
          SizedBox(width: 10),
          Text('Cash Collection'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Did you collect cash payment from the customer?',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _OptionTile(
            label: 'Yes, cash collected',
            selected: _collected == true,
            color: AppColors.success,
            onTap: () => setState(() {
              _collected = true;
              _error = null;
            }),
          ),
          const SizedBox(height: 8),
          _OptionTile(
            label: 'No, cash not collected',
            selected: _collected == false,
            color: AppColors.error,
            onTap: () => setState(() {
              _collected = false;
              _error = null;
            }),
          ),
          if (_collected == false) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _reasonController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Reason (e.g. customer refused, UPI used instead)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(null),
          child: const Text('Skip'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Confirm'),
        ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18,
              color: selected ? color : AppColors.textHint,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? color : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
