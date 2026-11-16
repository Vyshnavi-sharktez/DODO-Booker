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
  late final TabController _sectionController; // 0 = My Orders, 1 = InstaHelp
  late final TabController _statusController;
  late final bool _isDodoTeam;

  static const _vendorStatusTabs = [
    'Assigned',
    'In Progress',
    'Completed',
    'Rejected',
    'Cancelled',
    'Today',
  ];
  static const _dodoStatusTabs = [
    'In Progress',
    'Completed',
    'Cancelled',
    'Today',
  ];

  List<String> get _statusTabs =>
      _isDodoTeam ? _dodoStatusTabs : _vendorStatusTabs;

  @override
  void initState() {
    super.initState();
    _isDodoTeam = ref.read(currentVendorUserProvider)?.isDodoTeam ?? false;
    _sectionController = TabController(length: 2, vsync: this);
    _statusController = TabController(
      length: _statusTabs.length,
      vsync: this,
    );
    _sectionController.addListener(_onSectionChanged);
  }

  void _onSectionChanged() {
    if (!_sectionController.indexIsChanging && mounted) {
      _statusController.animateTo(0);
      setState(() {});
    }
  }

  @override
  void dispose() {
    _sectionController.removeListener(_onSectionChanged);
    _sectionController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(activeBookingTrackerObserver, (prev, next) {});
    final bookingsAsync = ref.watch(vendorBookingsProvider);

    return Column(
      children: [
        // ── Section tabs: My Orders | ⚡ InstaHelp ──────────────────────────
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _sectionController,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.textPrimary,
            dividerColor: AppColors.border,
            labelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            tabs: const [
              Tab(text: 'My Orders'),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.flash_on_rounded, size: 14),
                    SizedBox(width: 4),
                    Text('InstaHelp'),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Status sub-tabs ─────────────────────────────────────────────────
        Material(
          color: AppColors.background,
          child: TabBar(
            controller: _statusController,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.textPrimary,
            dividerColor: AppColors.border,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            tabs: _statusTabs.map((t) => Tab(text: t)).toList(),
          ),
        ),

        // ── Content ─────────────────────────────────────────────────────────
        Expanded(
          child: bookingsAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(
              message: e.toString(),
              onRetry: () => ref.invalidate(vendorBookingsProvider),
            ),
            data: (bookings) {
              final isInstaHelp = _sectionController.index == 1;
              final sectionBookings = bookings
                  .where((b) => isInstaHelp
                      ? b.bookingSource == 'instahelp'
                      : b.bookingSource != 'instahelp')
                  .toList();

              return TabBarView(
                controller: _statusController,
                children: _isDodoTeam
                    ? [
                        _buildList(sectionBookings,
                            {'in_progress', 'en_route', 'awaiting_verification'},
                            isInstaHelp),
                        _buildList(sectionBookings, {'completed'}, isInstaHelp),
                        _buildList(sectionBookings, {'cancelled'}, isInstaHelp),
                        _buildTodayList(sectionBookings, isInstaHelp),
                      ]
                    : [
                        _buildList(sectionBookings, {'assigned', 'accepted'},
                            isInstaHelp),
                        _buildList(sectionBookings,
                            {'in_progress', 'en_route', 'awaiting_verification'},
                            isInstaHelp),
                        _buildList(sectionBookings, {'completed'}, isInstaHelp),
                        _buildList(sectionBookings, {'rejected'}, isInstaHelp),
                        _buildList(sectionBookings, {'cancelled'}, isInstaHelp),
                        _buildTodayList(sectionBookings, isInstaHelp),
                      ],
              );
            },
          ),
        ),
      ],
    );
  }

  // ── List builders ─────────────────────────────────────────────────────────

  Widget _buildList(
      List<Booking> bookings, Set<String> statuses, bool isInstaHelp) {
    final primary = statuses.first;
    final filtered = bookings.where((b) {
      if (statuses.contains(b.status)) return true;
      // Warranty rework jobs surface under 'Assigned' for regular bookings.
      if (!isInstaHelp &&
          statuses.contains('assigned') &&
          b.isWarrantyRework &&
          (b.status == 'pending' || b.status == 'assigned')) return true;
      return false;
    }).toList();

    if (filtered.isEmpty) return _emptyState(primary, isInstaHelp);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(vendorBookingsProvider),
      child: ListView.builder(
        key: PageStorageKey<String>(
            '${isInstaHelp ? "insta" : "orders"}_$primary'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: filtered.length,
        itemBuilder: (_, i) => BookingCard(booking: filtered[i]),
      ),
    );
  }

  Widget _buildTodayList(List<Booking> bookings, bool isInstaHelp) {
    final now = DateTime.now();
    final filtered = bookings.where((b) {
      final d = b.serviceDate;
      return d != null &&
          d.year == now.year &&
          d.month == now.month &&
          d.day == now.day;
    }).toList();

    if (filtered.isEmpty) return _emptyState('today', isInstaHelp);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(vendorBookingsProvider),
      child: ListView.builder(
        key: PageStorageKey<String>(
            '${isInstaHelp ? "insta" : "orders"}_today'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: filtered.length,
        itemBuilder: (_, i) => BookingCard(booking: filtered[i]),
      ),
    );
  }

  // ── Empty states ──────────────────────────────────────────────────────────

  Widget _emptyState(String status, bool isInstaHelp) {
    if (status == 'today') {
      return EmptyStateView(
        icon: isInstaHelp ? Icons.flash_on_outlined : Icons.today_outlined,
        title: isInstaHelp
            ? 'No InstaHelp bookings today'
            : 'No bookings today',
        subtitle: isInstaHelp
            ? 'InstaHelp bookings scheduled for today will appear here.'
            : 'Bookings scheduled for today will appear here.',
      );
    }

    if (isInstaHelp) {
      return EmptyStateView(
        icon: Icons.flash_on_outlined,
        title: 'No ${status.replaceAll('_', ' ')} InstaHelp bookings',
        subtitle: null,
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
