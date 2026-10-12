import 'package:flutter/material.dart';
import '../../support/screens/support_chat_screen.dart';

/// True when [e] was thrown because the customer's account is not permitted
/// to place new bookings — either from the DB trigger (ERRCODE P0003) or the
/// service-layer pre-check in BookingService._getCustomerId().
bool isBookingRestrictionError(Object e) {
  final s = e.toString().toLowerCase();
  return s.contains('unable to place new bookings') ||
      s.contains('p0003') ||
      s.contains('account is currently unable');
}

/// Shows the "Booking Unavailable" dialog.
/// Tapping Contact Support closes the dialog then opens the existing
/// SupportChatScreen (get-or-create conversation flow).
Future<void> showBookingRestrictedDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogCtx) => _BookingRestrictedDialog(
      onContactSupport: () {
        Navigator.of(dialogCtx).pop();
        SupportChatScreen.show(context);
      },
      onClose: () => Navigator.of(dialogCtx).pop(),
    ),
  );
}

class _BookingRestrictedDialog extends StatelessWidget {
  final VoidCallback onContactSupport;
  final VoidCallback onClose;

  const _BookingRestrictedDialog({
    required this.onContactSupport,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFE53E3E).withAlpha(18),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.block_rounded,
                size: 32,
                color: Color(0xFFE53E3E),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Booking Unavailable',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A202C),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'Your account is currently unable to place new bookings. '
              'Please contact our support team for assistance.',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF718096),
                height: 1.55,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onContactSupport,
              icon: const Icon(Icons.chat_outlined, size: 17),
              label: const Text(
                'Contact Support',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onClose,
              style: TextButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
              ),
              child: const Text(
                'Close',
                style: TextStyle(fontSize: 14, color: Color(0xFF718096)),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
