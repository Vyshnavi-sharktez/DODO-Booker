import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/booking_model.dart';

/// Shows the booking-confirmed floating dialog on desktop/web (≥768 px).
/// Callers provide [onClose] and [onViewBookings] callbacks so that
/// navigation/cleanup happens in the caller's scope where Navigator is valid.
Future<void> showBookingSuccessDialog(
  BuildContext context,
  BookingModel booking, {
  required VoidCallback onClose,
  required VoidCallback onViewBookings,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, _, __) => _BookingSuccessDialog(
      booking: booking,
      onClose: onClose,
      onViewBookings: onViewBookings,
    ),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.95, end: 1.0).animate(
          CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    ),
  );
}

class _BookingSuccessDialog extends StatelessWidget {
  final BookingModel booking;
  final VoidCallback onClose;
  final VoidCallback onViewBookings;

  const _BookingSuccessDialog({
    required this.booking,
    required this.onClose,
    required this.onViewBookings,
  });

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String get _formattedDate {
    final d = booking.scheduledDate;
    return '${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final modalW = (size.width * 0.88).clamp(320.0, 780.0);
    final tt = Theme.of(context).textTheme;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: [
          // Blurred dim backdrop
          Positioned.fill(
            child: GestureDetector(
              onTap: onClose,
              behavior: HitTestBehavior.opaque,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: const ColoredBox(color: Color(0x70000000)),
              ),
            ),
          ),

          // Dialog card
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: modalW,
                maxHeight: size.height * 0.82,
              ),
              child: Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                elevation: 24,
                shadowColor: Colors.black38,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Close button row
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: onClose,
                          style: IconButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Success icon
                      Center(
                        child: Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.success.withAlpha(60),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            size: 34,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      Text(
                        'Booking Confirmed!',
                        textAlign: TextAlign.center,
                        style: tt.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Your booking is confirmed. We\'ll see you on $_formattedDate.',
                        textAlign: TextAlign.center,
                        style: tt.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 22),

                      // Booking summary card
                      _SummaryCard(
                        booking: booking,
                        formattedDate: _formattedDate,
                      ),
                      const SizedBox(height: 24),

                      // Footer actions — right-aligned
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: onClose,
                            child: const Text('Continue Browsing'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: onViewBookings,
                            child: const Text('View My Bookings'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Booking summary card ──────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final BookingModel booking;
  final String formattedDate;

  const _SummaryCard({required this.booking, required this.formattedDate});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Column(
        children: [
          _SummaryRow(
            label: 'Booking ID',
            value: booking.id,
            valueBold: true,
            valueColor: AppColors.primary,
          ),
          const Divider(height: 20),
          _SummaryRow(label: 'Service', value: booking.serviceName),
          const SizedBox(height: 10),
          _SummaryRow(
            label: 'Date & Time',
            value: '$formattedDate · ${booking.timeSlot}',
          ),
          if (booking.addressLabel.isNotEmpty) ...[
            const SizedBox(height: 10),
            _SummaryRow(label: 'Address', value: booking.addressLabel),
          ],
          const SizedBox(height: 10),
          _SummaryRow(
            label: 'Amount Paid',
            value: '₹${booking.totalAmount.toStringAsFixed(2)}',
            valueBold: true,
            valueColor: AppColors.success,
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 100,
                child: Text(
                  'Status',
                  style: tt.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.success.withAlpha(25),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.success.withAlpha(80)),
                ),
                child: Text(
                  booking.status.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool valueBold;
  final Color? valueColor;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueBold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: tt.labelSmall?.copyWith(color: AppColors.textSecondary),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: tt.labelSmall?.copyWith(
              fontWeight: valueBold ? FontWeight.w700 : FontWeight.w500,
              color: valueColor,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
