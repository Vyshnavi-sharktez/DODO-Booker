import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/service_model.dart';
import '../../../models/address_model.dart';
import '../../../models/time_slot_model.dart';
import '../widgets/booking_summary_card.dart';

class BookingSummaryScreen extends StatelessWidget {
  final ServiceModel service;
  final AddressModel address;
  final DateTime date;
  final TimeSlotModel slot;

  const BookingSummaryScreen({
    super.key,
    required this.service,
    required this.address,
    required this.date,
    required this.slot,
  });

  @override
  Widget build(BuildContext context) {
    debugPrint('SUMMARY SCREEN ACTIVE');
    final tt = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Review Your Booking',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Please confirm the details before proceeding to payment.',
              style: tt.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          BookingSummaryCard(
            service: service,
            address: address,
            date: date,
            slot: slot,
          ),
          // Payment notice
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.lock_rounded, size: 14, color: AppColors.success),
                const SizedBox(width: 6),
                Text(
                  'Secure payment integration coming soon',
                  style: tt.labelSmall?.copyWith(color: AppColors.success),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
