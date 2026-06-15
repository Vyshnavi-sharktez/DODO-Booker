import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../providers/bookings_provider.dart';
import '../widgets/booking_card.dart';

/// Shown when a vendor taps a booking notification deep-link.
/// Fetches the booking by ID and renders BookingCard (which handles all statuses).
class BookingDetailPage extends ConsumerWidget {
  const BookingDetailPage({super.key, required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[NOTIF][Vendor] destination reached — bookingId=$bookingId');
    final asyncBooking = ref.watch(bookingDetailProvider(bookingId));

    return Scaffold(
      appBar: AppBar(title: const Text('Booking Detail')),
      body: asyncBooking.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) {
          debugPrint('[NOTIF][Vendor] booking load ERROR — $e');
          return _ErrorState(message: e.toString());
        },
        data: (booking) {
          debugPrint('[NOTIF][Vendor] booking loaded — ${booking == null ? "null (not found)" : "id=${booking.id}"}');
          if (booking == null) {
            return const _ErrorState(
              message: 'This booking no longer exists or you do not have access.',
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: BookingCard(booking: booking),
          );
        },
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
