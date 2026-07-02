import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/service_model.dart';
import '../../../models/address_model.dart';
import '../../../models/time_slot_model.dart';

class BookingSummaryCard extends StatelessWidget {
  final ServiceModel service;
  final AddressModel address;
  final DateTime date;
  final TimeSlotModel slot;
  final double discountAmount;
  final String? couponCode;

  const BookingSummaryCard({
    super.key,
    required this.service,
    required this.address,
    required this.date,
    required this.slot,
    this.discountAmount = 0.0,
    this.couponCode,
  });

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  String get _formattedDate =>
      '${_weekdays[date.weekday - 1]}, ${date.day} ${_monthNames[date.month - 1]} ${date.year}';

  double get _tax => service.startingPrice * 0.18;
  double get _originalTotal => service.startingPrice + _tax;
  double get _finalTotal => (_originalTotal - discountAmount).clamp(0.0, double.infinity);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final hasDiscount = discountAmount > 0;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Service ──────────────────────────────────────────────────────
            Text('Service', style: tt.labelMedium?.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.home_repair_service_rounded, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(service.name, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      if (service.subcategoryName != null)
                        Text(service.subcategoryName!, style: tt.labelSmall?.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Divider(height: 1),
            ),

            // ── Address ──────────────────────────────────────────────────────
            Text('Address', style: tt.labelMedium?.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_rounded, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(address.label, style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        address.fullAddress,
                        style: tt.bodySmall?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Divider(height: 1),
            ),

            // ── Date & Time ──────────────────────────────────────────────────
            Text('Date & Time', style: tt.labelMedium?.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(_formattedDate, style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w500))),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(slot.label, style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w500))),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    slot.period.label,
                    style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Divider(height: 1),
            ),

            // ── Price breakdown ───────────────────────────────────────────────
            Text('Price Details', style: tt.labelMedium?.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            _PriceRow(label: 'Base Price', amount: service.startingPrice),
            const SizedBox(height: 6),
            _PriceRow(label: 'GST (18%)', amount: _tax),
            if (hasDiscount) ...[
              const SizedBox(height: 6),
              _DiscountRow(
                label: couponCode != null ? 'Discount ($couponCode)' : 'Discount',
                amount: discountAmount,
              ),
            ],
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            _PriceRow(
              label: 'Total Amount',
              amount: _finalTotal,
              isTotal: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final double amount;
  final bool isTotal;

  const _PriceRow({required this.label, required this.amount, this.isTotal = false});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: isTotal
                ? tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)
                : tt.bodySmall?.copyWith(color: AppColors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '₹${amount.toStringAsFixed(2)}',
          style: isTotal
              ? tt.titleMedium?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)
              : tt.bodySmall?.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

class _DiscountRow extends StatelessWidget {
  final String label;
  final double amount;

  const _DiscountRow({required this.label, required this.amount});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: tt.bodySmall?.copyWith(color: AppColors.success),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '−₹${amount.toStringAsFixed(2)}',
          style: tt.bodySmall?.copyWith(
            color: AppColors.success,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
