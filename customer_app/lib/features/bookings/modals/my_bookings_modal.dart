import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_modal_dialog.dart';
import '../services/bookings_providers.dart';
import '../widgets/bookings_tab_content.dart';
import '../widgets/empty_bookings_widget.dart';

/// My Bookings as a centered modal with blurred backdrop.
/// Opens from the Bookings nav-bar item and the Profile screen's menu.
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
    final screenH = MediaQuery.of(context).size.height;
    final modalH = min(600.0, screenH * 0.78);

    return AppModalDialog(
      title: 'My Bookings',
      scrollable: false,
      contentPadding: EdgeInsets.zero,
      maxWidth: 560,
      child: SizedBox(
        height: modalH,
        child: Column(
          children: [
            // Tab bar
            Container(
              color: AppColors.surface,
              child: TabBar(
                controller: _tabController,
                isScrollable: false,
                labelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                indicatorColor: AppColors.primary,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                tabs: _tabs.map((t) => Tab(text: t.$2)).toList(),
              ),
            ),
            const Divider(height: 1),
            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _tabs
                    .map((t) => BookingTabContent(
                          tab: t.$1,
                          onRefresh: _refresh,
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
