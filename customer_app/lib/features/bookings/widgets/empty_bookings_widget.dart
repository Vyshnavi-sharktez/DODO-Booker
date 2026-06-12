import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

enum BookingsTab { upcoming, ongoing, completed, cancelled }

class EmptyBookingsWidget extends StatelessWidget {
  final BookingsTab tab;
  final VoidCallback? onBookNow;

  const EmptyBookingsWidget({
    super.key,
    required this.tab,
    this.onBookNow,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final (icon, title, subtitle) = _content;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: AppColors.textHint),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: tt.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            if (tab == BookingsTab.upcoming && onBookNow != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onBookNow,
                icon: const Icon(Icons.search_rounded, size: 18),
                label: const Text('Browse Services'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(180, 48),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  (IconData, String, String) get _content {
    switch (tab) {
      case BookingsTab.upcoming:
        return (
          Icons.calendar_today_outlined,
          'No Upcoming Bookings',
          'You have no scheduled services.\nBrowse and book your first service today.',
        );
      case BookingsTab.ongoing:
        return (
          Icons.construction_outlined,
          'No Active Services',
          'Your ongoing services will appear here\nonce a technician is on the way.',
        );
      case BookingsTab.completed:
        return (
          Icons.check_circle_outline_rounded,
          'No Completed Bookings',
          'Your completed service history\nwill be shown here.',
        );
      case BookingsTab.cancelled:
        return (
          Icons.cancel_outlined,
          'No Cancelled Bookings',
          'You haven\'t cancelled any\nbookings — great job!',
        );
    }
  }
}
