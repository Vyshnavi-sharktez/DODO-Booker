import '../../../models/my_booking_model.dart';

class AmcContractSummary {
  final String contractId;
  final String serviceId;
  final String serviceName;
  final String planName;
  final String contractStatus;
  final int totalVisits;
  final int visitsCompleted;
  final List<MyBookingModel> visitBookings;
  final DateTime createdAt;

  // Plan snapshot fields — required to build a CartItem for Schedule Next Visit
  final String? amcPlanId;
  final double pricePerVisit;
  final String recurrenceInterval;
  final String? packageDuration;
  final String? serviceInterval;
  final int? numVisits;
  final double? originalTotal;
  final String? discountType;
  final double? discountValue;
  final double? discountAmount;
  final double? finalPrice;
  final int quantity;

  const AmcContractSummary({
    required this.contractId,
    required this.serviceId,
    required this.serviceName,
    required this.planName,
    required this.contractStatus,
    required this.totalVisits,
    required this.visitsCompleted,
    required this.visitBookings,
    required this.createdAt,
    this.amcPlanId,
    this.pricePerVisit = 0.0,
    this.recurrenceInterval = '',
    this.packageDuration,
    this.serviceInterval,
    this.numVisits,
    this.originalTotal,
    this.discountType,
    this.discountValue,
    this.discountAmount,
    this.finalPrice,
    this.quantity = 1,
  });

  int get remainingVisits => (totalVisits - visitsCompleted).clamp(0, 9999);

  bool get _hasOngoingVisit => visitBookings.any((b) => b.isOngoing);

  // Tab placement
  bool get isUpcoming =>
      (contractStatus == 'active' || contractStatus == 'paused') &&
      !_hasOngoingVisit;
  bool get isOngoing => contractStatus == 'active' && _hasOngoingVisit;
  bool get isCompleted => contractStatus == 'completed';
  bool get isCancelled => contractStatus == 'cancelled';
  bool get isCancellationRequested => contractStatus == 'cancellation_requested';

  // The next visit that hasn't been completed or cancelled, sorted by date
  // (unscheduled visits with null serviceDate appear after dated visits).
  MyBookingModel? get nextUpcomingVisit {
    final upcoming = visitBookings
        .where((b) => !b.isCompleted && !b.isCancelled)
        .toList()
      ..sort((a, b) {
        final dateA = a.serviceDate;
        final dateB = b.serviceDate;
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        return dateA.compareTo(dateB);
      });
    return upcoming.isEmpty ? null : upcoming.first;
  }

  // True when a trigger-created pending visit with no date exists.
  bool get hasUnscheduledVisit =>
      visitBookings.any((b) => b.status == 'pending' && b.serviceDate == null);
}
