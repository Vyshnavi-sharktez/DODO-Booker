import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/empty_state_view.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/vendor_scaffold.dart';
import '../../domain/models/booking.dart';
import '../providers/bookings_provider.dart';
import '../widgets/booking_card.dart';

class BookingsPage extends ConsumerStatefulWidget {
  const BookingsPage({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  ConsumerState<BookingsPage> createState() => _BookingsPageState();
}

class _BookingsPageState extends ConsumerState<BookingsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _tabs = [
    'Assigned',
    'In Progress',
    'Completed',
    'Rejected',
    'Cancelled',
    'Today',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, _tabs.length - 1),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(vendorBookingsProvider);

    return VendorScaffold(
      title: 'Bookings',
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: _tabs.map((t) => Tab(text: t)).toList(),
            ),
          ),
          Expanded(
            child: bookingsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(
                message: e.toString(),
                onRetry: () => ref.invalidate(vendorBookingsProvider),
              ),
              data: (bookings) => TabBarView(
                controller: _tabController,
                children: [
                  _buildBookingsList(bookings, 'assigned'),
                  _buildBookingsList(bookings, 'in_progress', 'awaiting_verification'),
                  _buildBookingsList(bookings, 'completed'),
                  _buildBookingsList(bookings, 'rejected'),
                  _buildBookingsList(bookings, 'cancelled'),
                  _buildTodayList(bookings),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingsList(List<Booking> bookings, String status,
      [String? additionalStatus]) {
    final filtered = bookings
        .where((b) =>
            b.status == status ||
            (additionalStatus != null && b.status == additionalStatus))
        .toList();
    if (filtered.isEmpty) return _emptyState(status);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(vendorBookingsProvider),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: filtered.length,
        itemBuilder: (_, i) => BookingCard(booking: filtered[i]),
      ),
    );
  }

  Widget _buildTodayList(List<Booking> bookings) {
    final now = DateTime.now();
    final filtered = bookings.where((b) {
      final d = b.serviceDate;
      return d != null &&
          d.year == now.year &&
          d.month == now.month &&
          d.day == now.day;
    }).toList();
    if (filtered.isEmpty) return _emptyState('today');
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(vendorBookingsProvider),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: filtered.length,
        itemBuilder: (_, i) => BookingCard(booking: filtered[i]),
      ),
    );
  }

  Widget _emptyState(String status) {
    if (status == 'today') {
      return const EmptyStateView(
        icon: Icons.today_outlined,
        title: 'No bookings today',
        subtitle: 'Bookings scheduled for today will appear here.',
      );
    }
    final label = status.replaceAll('_', ' ');
    final subtitle = switch (status) {
      'assigned' => 'New bookings will appear here once assigned to you.',
      'in_progress' => 'Tap "Start Service" on an assigned booking to begin.',
      'rejected' => 'Bookings you reject will appear here for your records.',
      _ => null,
    };
    return EmptyStateView(
      icon: status == 'rejected'
          ? Icons.block_outlined
          : Icons.receipt_long_outlined,
      title: 'No $label bookings',
      subtitle: subtitle,
    );
  }
}
