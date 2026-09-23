import 'package:intl/intl.dart';

class BookingForRefundModel {
  final String id;
  final String? bookingNumber;
  final String serviceName;
  final DateTime scheduledDate;
  final double totalAmount;
  final String paymentMethod; // 'online' | 'razorpay' (legacy) | 'cod' | 'cash'
  final String? paymentId;   // booking_payments.id for online bookings
  final String status;
  final String? paymentStatus; // bookings.payment_status — 'success' means payment captured
  final bool hasCompletedRefund;
  final DateTime? completedAt; // set when booking transitioned to 'completed'

  const BookingForRefundModel({
    required this.id,
    this.bookingNumber,
    required this.serviceName,
    required this.scheduledDate,
    required this.totalAmount,
    required this.paymentMethod,
    this.paymentId,
    required this.status,
    this.paymentStatus,
    this.hasCompletedRefund = false,
    this.completedAt,
  });

  BookingForRefundModel copyWith({
    bool? hasCompletedRefund,
    DateTime? completedAt,
  }) =>
      BookingForRefundModel(
        id: id,
        bookingNumber: bookingNumber,
        serviceName: serviceName,
        scheduledDate: scheduledDate,
        totalAmount: totalAmount,
        paymentMethod: paymentMethod,
        paymentId: paymentId,
        status: status,
        paymentStatus: paymentStatus,
        hasCompletedRefund: hasCompletedRefund ?? this.hasCompletedRefund,
        completedAt: completedAt ?? this.completedAt,
      );

  /// Returns true when the refund eligibility window has closed for this
  /// completed booking.  Always returns false for cancelled bookings — the
  /// period only applies to completed service deliveries.
  bool isRefundPeriodExpired(int periodDays) {
    if (status != 'completed') return false;
    if (completedAt == null) return false;
    final deadline = completedAt!.add(Duration(days: periodDays));
    return DateTime.now().isAfter(deadline);
  }

  String get displayBookingNumber {
    if (bookingNumber != null && bookingNumber!.isNotEmpty) {
      return bookingNumber!;
    }
    return 'BK-${id.substring(0, 8).toUpperCase()}';
  }

  bool get isOnlinePayment =>
      paymentMethod == 'online' || paymentMethod == 'razorpay';

  // COD cancelled before delivery: no cash was ever collected.
  bool get isCancelledCod => status == 'cancelled' && !isOnlinePayment;

  String get paymentMethodLabel => isOnlinePayment ? 'Online' : 'COD';

  String get formattedDate =>
      DateFormat('dd MMM yyyy').format(scheduledDate);

  String get formattedAmount =>
      '₹${totalAmount.toStringAsFixed(0)}';

  factory BookingForRefundModel.fromMap(Map<String, dynamic> map) {
    final paymentMethod =
        map['payment_method'] as String? ?? 'cash';

    // Resolve service name from booking_items → catalog_nodes
    final rawItems = map['booking_items'] as List<dynamic>? ?? [];
    String serviceName = '';
    if (rawItems.isNotEmpty) {
      final first = rawItems.first as Map<String, dynamic>?;
      final node = first?['catalog_nodes'] as Map<String, dynamic>?;
      serviceName = node?['name'] as String? ?? '';
      if (serviceName.isEmpty) {
        serviceName = first?['vendor_service_requests'] != null
            ? ((first!['vendor_service_requests']
                    as Map<String, dynamic>?)?['service_name'] as String? ??
                '')
            : '';
      }
      if (rawItems.length > 1 && serviceName.isNotEmpty) {
        serviceName = '$serviceName + ${rawItems.length - 1} more';
      }
    }
    if (serviceName.isEmpty) {
      final notes = map['notes'] as String?;
      if (notes != null && notes.contains(' · ')) {
        serviceName = notes.split(' · ').first;
      }
    }

    // Resolve payment_id from joined booking_payments
    final rawPayments = map['booking_payments'] as List<dynamic>? ?? [];
    String? paymentId;
    final isOnline = paymentMethod == 'online' || paymentMethod == 'razorpay';
    if (isOnline && rawPayments.isNotEmpty) {
      paymentId =
          (rawPayments.first as Map<String, dynamic>?)?['id'] as String?;
    }

    return BookingForRefundModel(
      id: map['id'] as String,
      bookingNumber: map['booking_number'] as String?,
      serviceName: serviceName.isNotEmpty ? serviceName : 'Service',
      scheduledDate: DateTime.tryParse(
            (map['service_date'] ?? map['created_at'] ?? '') as String,
          ) ??
          DateTime(2000),
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: paymentMethod,
      paymentId: paymentId,
      status: map['status'] as String? ?? 'completed',
      paymentStatus: map['payment_status'] as String?,
      completedAt: map['completed_at'] != null
          ? DateTime.tryParse(map['completed_at'] as String)
          : null,
    );
  }
}
