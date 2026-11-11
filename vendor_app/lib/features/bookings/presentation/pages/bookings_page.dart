import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/empty_state_view.dart';
import '../../../../core/widgets/error_view.dart';

import '../../domain/models/booking.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../providers/bookings_provider.dart';
import '../widgets/booking_card.dart';

import '../../../location/application/location_tracking_service.dart';

class BookingsPage extends ConsumerStatefulWidget {
  const BookingsPage({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  ConsumerState<BookingsPage> createState() => _BookingsPageState();
}

class _BookingsPageState extends ConsumerState<BookingsPage>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  late final TabController _instaHelpTabController;
  late final bool _isDodoTeam;

  static const _vendorTabs = [
    'Assigned',
    'In Progress',
    'Completed',
    'Rejected',
    'Cancelled',
    'Today',
    'InstaHelp',
  ];
  static const _dodoTabs = [
    'In Progress',
    'Completed',
    'Cancelled',
    'Today',
    'InstaHelp',
  ];
  static const _instaHelpStatusTabs = [
    'Assigned',
    'In Progress',
    'Completed',
    'Rejected',
    'Cancelled',
    'Today',
  ];

  List<String> get _tabs => _isDodoTeam ? _dodoTabs : _vendorTabs;

  @override
  void initState() {
    super.initState();
    _isDodoTeam = ref.read(currentVendorUserProvider)?.isDodoTeam ?? false;
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, _tabs.length - 1),
    );
    _instaHelpTabController = TabController(
      length: _instaHelpStatusTabs.length,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _instaHelpTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(activeBookingTrackerObserver, (prev, next) {});
    final bookingsAsync = ref.watch(vendorBookingsProvider);

    return Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.textPrimary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.textPrimary,
              dividerColor: AppColors.border,
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
                children: _isDodoTeam
                    ? [
                        _buildBookingsList(bookings, {'in_progress', 'en_route', 'awaiting_verification'}),
                        _buildBookingsList(bookings, {'completed'}),
                        _buildBookingsList(bookings, {'cancelled'}),
                        _buildTodayList(bookings),
                        _buildInstaHelpTabView(bookings),
                      ]
                    : [
                        _buildBookingsList(bookings, {'assigned', 'accepted'}),
                        _buildBookingsList(bookings, {'in_progress', 'en_route', 'awaiting_verification'}),
                        _buildBookingsList(bookings, {'completed'}),
                        _buildBookingsList(bookings, {'rejected'}),
                        _buildBookingsList(bookings, {'cancelled'}),
                        _buildTodayList(bookings),
                        _buildInstaHelpTabView(bookings),
                      ],
              ),
            ),
          ),
        ],
      );
  }

  // ── Regular bookings (excludes InstaHelp) ─────────────────────────────────

  Widget _buildBookingsList(List<Booking> bookings, Set<String> statuses) {
    final primary = statuses.first;
    final filtered = bookings
        .where((b) =>
            b.bookingSource != 'instahelp' &&
            (statuses.contains(b.status) ||
            (statuses.contains('assigned') &&
                b.isWarrantyRework &&
                (b.status == 'pending' || b.status == 'assigned'))))
        .toList();
    if (filtered.isEmpty) return _emptyState(primary);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(vendorBookingsProvider),
      child: ListView.builder(
        key: PageStorageKey<String>('vendor_bookings_$primary'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: filtered.length,
        itemBuilder: (_, i) => BookingCard(booking: filtered[i]),
      ),
    );
  }

  Widget _buildTodayList(List<Booking> bookings) {
    final now = DateTime.now();
    final filtered = bookings.where((b) {
      if (b.bookingSource == 'instahelp') return false;
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
        key: const PageStorageKey<String>('vendor_bookings_today'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: filtered.length,
        itemBuilder: (_, i) => BookingCard(booking: filtered[i]),
      ),
    );
  }

  // ── InstaHelp tab with nested status sub-tabs ─────────────────────────────

  Widget _buildInstaHelpTabView(List<Booking> bookings) {
    final insta = bookings.where((b) => b.bookingSource == 'instahelp').toList();
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _instaHelpTabController,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.textPrimary,
            dividerColor: AppColors.border,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: _instaHelpStatusTabs.map((t) => Tab(text: t)).toList(),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _instaHelpTabController,
            children: [
              _buildInstaList(insta, {'assigned', 'accepted'}),
              _buildInstaList(insta, {'in_progress', 'en_route', 'awaiting_verification'}),
              _buildInstaList(insta, {'completed'}),
              _buildInstaList(insta, {'rejected'}),
              _buildInstaList(insta, {'cancelled'}),
              _buildInstaToday(insta),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInstaList(List<Booking> bookings, Set<String> statuses) {
    final filtered = bookings.where((b) => statuses.contains(b.status)).toList();
    if (filtered.isEmpty) {
      return EmptyStateView(
        icon: Icons.flash_on_outlined,
        title: 'No ${statuses.first.replaceAll('_', ' ')} InstaHelp bookings',
        subtitle: null,
      );
    }
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(vendorBookingsProvider),
      child: ListView.builder(
        key: PageStorageKey<String>('vendor_insta_${statuses.first}'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: filtered.length,
        itemBuilder: (_, i) => BookingCard(booking: filtered[i]),
      ),
    );
  }

  Widget _buildInstaToday(List<Booking> bookings) {
    final now = DateTime.now();
    final filtered = bookings.where((b) {
      final d = b.serviceDate;
      return d != null &&
          d.year == now.year &&
          d.month == now.month &&
          d.day == now.day;
    }).toList();
    if (filtered.isEmpty) {
      return const EmptyStateView(
        icon: Icons.flash_on_outlined,
        title: 'No InstaHelp bookings today',
        subtitle: 'InstaHelp bookings scheduled for today will appear here.',
      );
    }
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(vendorBookingsProvider),
      child: ListView.builder(
        key: const PageStorageKey<String>('vendor_insta_today'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: filtered.length,
        itemBuilder: (_, i) => BookingCard(booking: filtered[i]),
      ),
    );
  }

  // ── Empty states ──────────────────────────────────────────────────────────

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
      'in_progress' => _isDodoTeam
          ? 'Bookings started by admin will appear here.'
          : 'Tap "Start Service" on an assigned booking to begin.',
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
