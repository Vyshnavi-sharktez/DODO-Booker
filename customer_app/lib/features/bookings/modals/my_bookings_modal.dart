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
    with TickerProviderStateMixin {
  late TabController _topController;
  late TabController _ordersController;
  late TabController _instaHelpController;

  static const _statusTabs = [
    (BookingsTab.upcoming, 'Upcoming'),
    (BookingsTab.ongoing, 'Ongoing'),
    (BookingsTab.completed, 'Completed'),
    (BookingsTab.cancelled, 'Cancelled'),
    (BookingsTab.failed, 'Failed'),
  ];

  @override
  void initState() {
    super.initState();
    _topController = TabController(length: 2, vsync: this);
    _ordersController = TabController(length: _statusTabs.length, vsync: this);
    _instaHelpController =
        TabController(length: _statusTabs.length, vsync: this);
  }

  @override
  void dispose() {
    _topController.dispose();
    _ordersController.dispose();
    _instaHelpController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(myBookingsProvider);
    try {
      await ref.read(processedBookingsProvider.future);
    } catch (_) {}
  }

  Widget _statusTabBar(TabController controller) => Container(
        color: AppColors.surface,
        child: TabBar(
          controller: controller,
          isScrollable: false,
          labelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          unselectedLabelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: _statusTabs.map((t) => Tab(text: t.$2)).toList(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Top-level tabs: My Orders | InstaHelp ──────────────────────────
        Container(
          color: AppColors.surface,
          child: TabBar(
            controller: _topController,
            isScrollable: false,
            labelStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            unselectedLabelStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            indicatorColor: AppColors.primary,
            indicatorWeight: 3,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
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
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: _topController,
            children: [
              // ── My Orders section ───────────────────────────────────────
              Column(
                children: [
                  _statusTabBar(_ordersController),
                  const Divider(height: 1),
                  Expanded(
                    child: TabBarView(
                      controller: _ordersController,
                      children: _statusTabs
                          .map((t) => BookingTabContent(
                                tab: t.$1,
                                onRefresh: _refresh,
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ),
              // ── InstaHelp section ────────────────────────────────────────
              Column(
                children: [
                  _statusTabBar(_instaHelpController),
                  const Divider(height: 1),
                  Expanded(
                    child: TabBarView(
                      controller: _instaHelpController,
                      children: _statusTabs
                          .map((t) => BookingTabContent(
                                tab: t.$1,
                                onRefresh: _refresh,
                                instaHelpOnly: true,
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
