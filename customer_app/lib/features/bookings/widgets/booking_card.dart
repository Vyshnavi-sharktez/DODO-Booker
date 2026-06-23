import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/my_booking_model.dart';

class BookingCard extends StatelessWidget {
  final MyBookingModel booking;
  final VoidCallback onTap;

  const BookingCard({super.key, required this.booking, required this.onTap});

  static const _monthAbbrevs = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String get _formattedDate {
    final d = booking.scheduledDate;
    return '${d.day} ${_monthAbbrevs[d.month - 1]} ${d.year}';
  }

  String get _addressLine {
    final addr = booking.address;
    if (addr.label.isNotEmpty && addr.city.isNotEmpty) {
      return '${addr.label}, ${addr.city}';
    }
    if (addr.city.isNotEmpty) return addr.city;
    return addr.line1;
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final (statusColor, statusLabel) = _statusMeta(booking.status);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: service name + status chip
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _iconForCategory(booking.categoryName),
                      size: 18,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          booking.serviceName,
                          style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (booking.items.length > 1) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${booking.items.length} services',
                                style: tt.labelSmall?.copyWith(
                                  color: AppColors.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          ...booking.items.take(2).map(
                                (item) => Text(
                                  item.serviceName,
                                  style: tt.labelSmall?.copyWith(
                                      color: AppColors.textSecondary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          if (booking.items.length > 2)
                            Text(
                              '+${booking.items.length - 2} more',
                              style: tt.labelSmall
                                  ?.copyWith(color: AppColors.textHint),
                            ),
                        ] else if (booking.subcategoryName != null)
                          Text(
                            booking.subcategoryName!,
                            style: tt.labelSmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  _StatusChip(label: statusLabel, color: statusColor),
                ],
              ),

              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // Booking details row
              Row(
                children: [
                  // Left: date, time, address
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _InfoRow(
                          icon: Icons.confirmation_number_outlined,
                          text: booking.id,
                          textStyle: tt.labelSmall?.copyWith(
                            color: AppColors.textSecondary,
                            fontFamily: 'monospace',
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _InfoRow(
                          icon: Icons.calendar_today_rounded,
                          text: '$_formattedDate  ·  ${booking.timeSlot}',
                        ),
                        const SizedBox(height: 4),
                        _InfoRow(
                          icon: Icons.location_on_outlined,
                          text: _addressLine,
                        ),
                      ],
                    ),
                  ),
                  // Right: amount
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₹${booking.totalAmount.toStringAsFixed(0)}',
                        style: tt.titleMedium?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'incl. tax',
                        style: tt.labelSmall?.copyWith(
                          color: AppColors.textHint,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // View details link
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'View Details',
                    style: tt.labelSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 12,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

(Color, String) _statusMeta(String status) {
  switch (status) {
    case BookingStatus.pending:
      return (AppColors.warning, 'Pending');
    case BookingStatus.assigned:
      return (AppColors.primary, 'Assigned');
    case BookingStatus.accepted:
      return (const Color(0xFF00ACC1), 'Accepted');
    case BookingStatus.enRoute:
      return (const Color(0xFF5C6BC0), 'En Route');
    case BookingStatus.started:
      return (const Color(0xFFFF6D00), 'In Progress');
    case BookingStatus.completed:
      return (AppColors.success, 'Completed');
    case BookingStatus.cancelled:
      return (AppColors.error, 'Cancelled');
    default:
      return (AppColors.textHint, status);
  }
}

IconData _iconForCategory(String? category) {
  switch ((category ?? '').toLowerCase()) {
    case 'cleaning':
      return Icons.cleaning_services_rounded;
    case 'plumbing':
      return Icons.plumbing_rounded;
    case 'electrical':
      return Icons.electrical_services_rounded;
    case 'appliances':
      return Icons.ac_unit_rounded;
    case 'painting':
      return Icons.format_paint_rounded;
    case 'pest control':
      return Icons.bug_report_rounded;
    case 'shifting':
      return Icons.local_shipping_rounded;
    case 'carpentry':
      return Icons.chair_rounded;
    default:
      return Icons.home_repair_service_rounded;
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final TextStyle? textStyle;

  const _InfoRow({required this.icon, required this.text, this.textStyle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 12, color: AppColors.textHint),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            style: textStyle ??
                Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
