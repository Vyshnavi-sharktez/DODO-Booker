import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../services/bookings_providers.dart';
import '../widgets/bookings_tab_content.dart';
import '../widgets/empty_bookings_widget.dart';

/// My Bookings tab content. Intended to run inside [PageSheet] so it inherits
/// the shared dialog dimensions, header, and close button.
class MyBookingsModal extends ConsumerStatefulWidget {
  const MyBookingsModal({super.key});

  @override
  ConsumerState<MyBookingsModal> createState() => _MyBookingsModalState();
}

class _MyBookingsModalState extends ConsumerState<MyBookingsModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabs = [
    (BookingsTab.upcoming, 'Upcoming'),
    (BookingsTab.ongoing, 'Ongoing'),
    (BookingsTab.completed, 'Completed'),
    (BookingsTab.cancelled, 'Cancelled'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(myBookingsProvider);
    try {
      await ref.read(myBookingsProvider.future);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: AppColors.surface,
          child: TabBar(
            controller: _tabController,
            isScrollable: false,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            tabs: _tabs.map((t) => Tab(text: t.$2)).toList(),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: _tabs
                .map((t) => BookingTabContent(tab: t.$1, onRefresh: _refresh))
                .toList(),
          ),
        ),
      ],
    );
  }
}
