import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../routes/app_router.dart';
import '../models/booking_for_refund_model.dart';
import '../services/refund_queries_providers.dart';
import '../services/refund_queries_service.dart';

class BookingSelectionScreen extends ConsumerWidget {
  const BookingSelectionScreen({
    super.key,
    this.inModal = false,
    this.onBookingSelected,
  });

  final bool inModal;
  final void Function(BookingForRefundModel booking)? onBookingSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final bookingsAsync = ref.watch(bookingsForRefundProvider);
    final service = ref.read(refundQueriesServiceProvider);

    final body = bookingsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: AppColors.textHint,
              ),
              const SizedBox(height: 12),
              Text(
                'Could not load bookings',
                style: tt.titleSmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  e.toString(),
                  style: tt.bodySmall?.copyWith(
                    color: AppColors.textHint,
                    fontSize: 11,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.invalidate(bookingsForRefundProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (bookings) {
          if (bookings.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(
                        Icons.receipt_long_outlined,
                        size: 32,
                        color: AppColors.textHint,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'No eligible bookings',
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Only completed or cancelled bookings\nwithout an active refund query are shown.',
                      style: tt.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Which booking is this refund for?',
                  style: tt.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 32),
                  itemCount: bookings.length,
                  itemBuilder: (ctx, i) {
                    final b = bookings[i];
                    final periodDays =
                        service.lastFetchedRefundPeriodDays;
                    final periodExpired =
                        b.isRefundPeriodExpired(periodDays);
                    final disabled =
                        b.hasCompletedRefund || b.isCancelledCod || periodExpired;
                    return _BookingTile(
                      booking: b,
                      periodExpired: periodExpired,
                      onTap: disabled
                          ? null
                          : () => onBookingSelected != null
                              ? onBookingSelected!(b)
                              : context.push(
                                  AppRoutes.refundQueryForm,
                                  extra: b,
                                ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      );

    if (inModal) return body;

    return Scaffold(
      backgroundColor: AppColors.surfaceVariant,
      appBar: AppBar(title: const Text('Select Booking')),
      body: body,
    );
  }
}

class _BookingTile extends StatelessWidget {
  const _BookingTile({
    required this.booking,
    this.periodExpired = false,
    this.onTap,
  });

  final BookingForRefundModel booking;
  final bool periodExpired;
  final VoidCallback? onTap;

  bool get _disabled => onTap == null;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isCancelled = booking.status == 'cancelled';

    final tile = Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      decoration: BoxDecoration(
        color: _disabled ? AppColors.surfaceVariant : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: _disabled
            ? null
            : const [
                BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(
                isCancelled
                    ? Icons.cancel_outlined
                    : Icons.check_circle_outline_rounded,
                size: 22,
                color: _disabled
                    ? AppColors.textHint
                    : (isCancelled
                        ? AppColors.error.withAlpha(180)
                        : AppColors.success),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    booking.serviceName,
                    style: tt.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: _disabled
                          ? AppColors.textHint
                          : AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${booking.displayBookingNumber}  ·  ${booking.formattedDate}',
                    style: tt.bodySmall?.copyWith(
                      color: _disabled
                          ? AppColors.textHint
                          : AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (_disabled)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: booking.isCancelledCod
                            ? const Color(0xFFF7F7F7)
                            : periodExpired
                                ? const Color(0xFFFFF3CD)
                                : const Color(0xFFEBF8FF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: booking.isCancelledCod
                              ? const Color(0xFFD1D1D1)
                              : periodExpired
                                  ? const Color(0xFFFFCA28)
                                  : const Color(0xFFBEE3F8),
                        ),
                      ),
                      child: Text(
                        booking.isCancelledCod
                            ? 'COD — No Refund Required'
                            : periodExpired
                                ? 'Refund Period Expired'
                                : 'Refund Already Processed',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: booking.isCancelledCod
                              ? const Color(0xFF6B6B6B)
                              : periodExpired
                                  ? const Color(0xFF7B5800)
                                  : const Color(0xFF2B6CB0),
                        ),
                      ),
                    )
                  else
                    Row(
                      children: [
                        Text(
                          booking.formattedAmount,
                          style: tt.bodySmall?.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            booking.paymentMethodLabel,
                            style: tt.labelSmall?.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (!_disabled)
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textHint,
                size: 20,
              ),
          ],
        ),
      ),
    );

    if (_disabled) return tile;
    return GestureDetector(onTap: onTap, child: tile);
  }
}
