import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/my_booking_model.dart';
import '../../amc/models/amc_contract_summary.dart';
import '../services/bookings_providers.dart';
import '../utils/booking_detail_launcher.dart';
import 'amc_contract_card.dart';
import 'booking_card.dart';
import 'empty_bookings_widget.dart';

// Union type for the merged booking list.
sealed class _Entry {}

class _RegularEntry extends _Entry {
  final MyBookingModel booking;
  _RegularEntry(this.booking);
}

class _AmcEntry extends _Entry {
  final AmcContractSummary contract;
  _AmcEntry(this.contract);
}

/// Reusable tab body used by both [MyBookingsScreen] and [MyBookingsModal].
class BookingTabContent extends ConsumerWidget {
  final BookingsTab tab;
  final Future<void> Function() onRefresh;

  const BookingTabContent({
    super.key,
    required this.tab,
    required this.onRefresh,
  });

  List<_Entry> _filter(ProcessedBookings data) {
    final entries = <_Entry>[];

    switch (tab) {
      case BookingsTab.upcoming:
        entries.addAll(
          data.regular.where((b) => b.isUpcoming).map(_RegularEntry.new),
        );
        entries.addAll(
          data.amcContracts.where((c) => c.isUpcoming).map(_AmcEntry.new),
        );
      case BookingsTab.ongoing:
        entries.addAll(
          data.regular.where((b) => b.isOngoing).map(_RegularEntry.new),
        );
        entries.addAll(
          data.amcContracts.where((c) => c.isOngoing).map(_AmcEntry.new),
        );
      case BookingsTab.completed:
        entries.addAll(
          data.regular.where((b) => b.isCompleted).map(_RegularEntry.new),
        );
        entries.addAll(
          data.amcContracts.where((c) => c.isCompleted).map(_AmcEntry.new),
        );
      case BookingsTab.cancelled:
        entries.addAll(
          data.regular.where((b) => b.isCancelled).map(_RegularEntry.new),
        );
        entries.addAll(
          data.amcContracts.where((c) => c.isCancelled).map(_AmcEntry.new),
        );
    }

    return entries;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(processedBookingsProvider);

    return asyncData.when(
      loading: () => const BookingsLoadingSkeleton(),
      error: (e, _) => BookingsErrorState(
        onRetry: () => ref.invalidate(processedBookingsProvider),
      ),
      data: (processed) {
        final entries = _filter(processed);
        if (entries.isEmpty) {
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
            itemCount: entries.length,
            itemBuilder: (_, i) {
              final entry = entries[i];
              return switch (entry) {
                _RegularEntry(booking: final b) => BookingCard(
                    booking: b,
                    onTap: () => openBookingDetail(context, b),
                  ),
                _AmcEntry(contract: final c) => AmcContractCard(contract: c),
              };
            },
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
