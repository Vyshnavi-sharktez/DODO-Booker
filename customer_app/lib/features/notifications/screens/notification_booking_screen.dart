import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../bookings/screens/booking_details_screen.dart';
import '../../bookings/services/bookings_providers.dart';

/// Opened when a customer taps a booking notification deep-link.
/// Fetches the booking by ID from Supabase and shows BookingDetailsScreen.
class NotificationBookingScreen extends ConsumerWidget {
  const NotificationBookingScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[NOTIF][Customer] destination reached — bookingId=$bookingId');
    final asyncBooking = ref.watch(bookingByIdProvider(bookingId));

    return asyncBooking.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) {
        debugPrint('[NOTIF][Customer] booking load ERROR — $e');
        return Scaffold(
          appBar: AppBar(title: const Text('Booking')),
          body: Center(
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
                    'Unable to load booking details.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      data: (booking) {
        debugPrint('[NOTIF][Customer] booking loaded — ${booking == null ? "null (not found)" : "id=${booking.id}"}');
        if (booking == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Booking')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.search_off_rounded,
                      size: 48,
                      color: AppColors.textHint,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'This booking no longer exists.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return BookingDetailsScreen(booking: booking);
      },
    );
  }
}
