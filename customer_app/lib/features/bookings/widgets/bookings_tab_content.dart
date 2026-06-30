import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/my_booking_model.dart';
import '../services/bookings_providers.dart';
import '../utils/booking_detail_launcher.dart';
import 'booking_card.dart';
import 'empty_bookings_widget.dart';

/// Reusable tab body used by both [MyBookingsScreen] and [MyBookingsModal].
class BookingTabContent extends ConsumerWidget {
  final BookingsTab tab;
  final Future<void> Function() onRefresh;

  const BookingTabContent({
    super.key,
    required this.tab,
    required this.onRefresh,
  });

  List<MyBookingModel> _filter(List<MyBookingModel> all) {
    return switch (tab) {
      BookingsTab.upcoming => all.where((b) => b.isUpcoming).toList(),
      BookingsTab.ongoing => all.where((b) => b.isOngoing).toList(),
      BookingsTab.completed => all.where((b) => b.isCompleted).toList(),
      BookingsTab.cancelled => all.where((b) => b.isCancelled).toList(),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncBookings = ref.watch(myBookingsProvider);

    return asyncBookings.when(
      loading: () => const BookingsLoadingSkeleton(),
      error: (e, _) =>
          BookingsErrorState(onRetry: () => ref.invalidate(myBookingsProvider)),
      data: (all) {
        final bookings = _filter(all);
        if (bookings.isEmpty) {
          return RefreshIndicator(
            onRefresh: onRefresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: 360,
                child: EmptyBookingsWidget(
                  tab: tab,
                  onBookNow: tab == BookingsTab.upcoming
                      ? () => context.go('/')
                      : null,
                ),
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: bookings.length,
            itemBuilder: (_, i) => BookingCard(
              booking: bookings[i],
              onTap: () => openBookingDetail(context, bookings[i]),
            ),
          ),
        );
      },
    );
  }
}

// ── Shared loading skeleton ───────────────────────────────────────────────────

class BookingsLoadingSkeleton extends StatelessWidget {
  const BookingsLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 4,
      itemBuilder: (_, i) => Container(
        height: 140,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.shimmerBase,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

// ── Shared error state ────────────────────────────────────────────────────────

class BookingsErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const BookingsErrorState({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 48,
            color: AppColors.error,
          ),
          const SizedBox(height: 12),
          Text(
            'Could not load bookings',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
