import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../routes/app_router.dart';
import '../../bookings/screens/booking_details_screen.dart';
import '../../bookings/services/bookings_providers.dart';

/// Opened when a customer taps a booking notification deep-link on mobile,
/// or navigates directly to /notification-booking/:id.
/// On desktop (≥ 768 px), notification taps go through the notification
/// handlers which show a PageSheet directly over the current page instead.
class NotificationBookingScreen extends ConsumerWidget {
  const NotificationBookingScreen({super.key, required this.bookingId});

  final String bookingId;

  Widget _closeButton(BuildContext context) => IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: 'Close',
        onPressed: () => context.go(AppRoutes.home),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[NOTIF][Customer] destination reached — bookingId=$bookingId');
    final asyncBooking = ref.watch(bookingByIdProvider(bookingId));

    return asyncBooking.when(
      loading: () => Scaffold(
        appBar: AppBar(actions: [_closeButton(context)]),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) {
        debugPrint('[NOTIF][Customer] booking load ERROR — $e');
        return Scaffold(
          appBar: AppBar(
            title: const Text('Booking'),
            actions: [_closeButton(context)],
          ),
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
            appBar: AppBar(
              title: const Text('Booking'),
              actions: [_closeButton(context)],
            ),
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
        return BookingDetailsScreen(
          booking: booking,
          onClose: () => context.go(AppRoutes.home),
        );
      },
    );
  }
}
