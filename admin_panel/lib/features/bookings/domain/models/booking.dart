import 'package:flutter/material.dart';
import 'booking_addon.dart';
import 'booking_item.dart';

// ── AMC planned-date helpers ───────────────────────────────────────────────────

DateTime _addCalMonths(DateTime base, int months) {
  final total = (base.month - 1) + months;
  final targetYear = base.year + total ~/ 12;
  final targetMonth = total % 12 + 1;
  final daysInMonth = DateTime.utc(targetYear, targetMonth + 1, 0).day;
  return DateTime.utc(targetYear, targetMonth, base.day.clamp(1, daysInMonth));
}

DateTime? _amcVisitPlannedDate(
    DateTime contractCreatedAt, String? interval, int visitNumber) {
  if (interval == null) return null;
  final n = visitNumber - 1;
  final base = DateTime.utc(
      contractCreatedAt.year, contractCreatedAt.month, contractCreatedAt.day);
  return switch (interval) {
    'weekly'      => base.add(Duration(days: 7 * n)),
    'bi_weekly'   => base.add(Duration(days: 14 * n)),
    'monthly'     => _addCalMonths(base, n),
    'quarterly'   => _addCalMonths(base, 3 * n),
    'half_yearly' => _addCalMonths(base, 6 * n),
    'yearly'      => _addCalMonths(base, 12 * n),
    _ => null,
  };
}

class BookingReview {
  final String id;
  final int rating;
  final String reviewText;
  final DateTime? createdAt;

  const BookingReview({
    required this.id,
    required this.rating,
    required this.reviewText,
    this.createdAt,
  });

  factory BookingReview.fromMap(Map<String, dynamic> map) {
    return BookingReview(
      id: map['id'] as String,
      rating: ((map['rating'] as num?)?.round()) ?? 0,
      reviewText: map['review_text'] as String? ?? '',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }
}

class Booking {
  final String id;
  final String bookingNumber;
  final String customerId;
  final String vendorId;
  final String vendorName;
  final String dodoTeamId;
  final String assignmentType; // 'Unassigned' | 'External Vendor' | 'DODO Team'
  final DateTime? serviceDate;
  final String status;
  final String dispatchStatus; // 'idle' | 'dispatching' | 'accepted' | 'exhausted'
  final double subtotal;
  final double discountAmount;
  final double totalAmount;
  final String? address;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final BookingReview? review;
  final String? rejectionReason;
  final DateTime? rejectedAt;
  final List<BookingItem> items;
  final List<BookingAddon> addons;
  final double? latitude;
  final double? longitude;
  final String? completionOtp;
  final String paymentMethod; // 'cash' | 'cod' | 'online' — mirrors DB default 'cash'
  final bool isAmc;
  final String? amcPlanName;
  final String? amcRecurrenceInterval;
  final String? amcContractId;
  final int? amcVisitNumber;
  final int? amcVisitsCompleted;
  final int? amcTotalVisits; // effective: num_visits ?? total_visits
  final DateTime? amcContractCreatedAt;
  final String? amcServiceInterval;
  final String? amcContractStatus;
  final String? cancellationReason;
  final String? cancellationRemarks;
  final DateTime? cancellationRequestedAt;
  final int amcQuantity;

  DateTime? get plannedDueDate {
    if (!isAmc || amcVisitNumber == null || amcContractCreatedAt == null) {
      return null;
    }
    return _amcVisitPlannedDate(
        amcContractCreatedAt!, amcServiceInterval, amcVisitNumber!);
  }

  const Booking({
    required this.id,
    required this.bookingNumber,
    required this.customerId,
    required this.vendorId,
    this.vendorName = '',
    this.dodoTeamId = '',
    this.assignmentType = 'Unassigned',
    this.serviceDate,
    required this.status,
    this.dispatchStatus = 'idle',
    required this.subtotal,
    required this.discountAmount,
    required this.totalAmount,
    this.address,
    this.notes,
    this.createdAt,
    this.updatedAt,
    this.review,
    this.rejectionReason,
    this.rejectedAt,
    this.items = const [],
    this.addons = const [],
    this.latitude,
    this.longitude,
    this.completionOtp,
    this.paymentMethod = 'cash',
    this.isAmc = false,
    this.amcPlanName,
    this.amcRecurrenceInterval,
    this.amcContractId,
    this.amcVisitNumber,
    this.amcVisitsCompleted,
    this.amcTotalVisits,
    this.amcContractCreatedAt,
    this.amcServiceInterval,
    this.amcContractStatus,
    this.cancellationReason,
    this.cancellationRemarks,
    this.cancellationRequestedAt,
    this.amcQuantity = 1,
  });

  bool get isUnassigned => assignmentType == 'Unassigned';
  // 'cash' is the canonical value written by the customer app ("Cash After Service").
  // 'cod' is accepted as an alias for backward compatibility.
  bool get isCod => paymentMethod == 'cash' || paymentMethod == 'cod';

  (String label, Color textColor, Color bgColor) get statusConfig {
    if (dispatchStatus == 'exhausted') {
      return ('No Vendor Accepted', const Color(0xFFE53E3E), const Color(0xFFFFF5F5));
    }
    if (dispatchStatus == 'dispatching' || (status == 'assigned' && dispatchStatus != 'accepted')) {
      return ('Waiting for Vendor Acceptance', const Color(0xFFDD6B20), const Color(0xFFFEEBC8));
    }
    if (status == 'accepted' || (status == 'assigned' && dispatchStatus == 'accepted')) {
      return ('Assigned', const Color(0xFF3182CE), const Color(0xFFEBF8FF));
    }
    if (status == 'assigned_to_dodo_team') {
      return ('DODO Assigned', const Color(0xFF6B46C1), const Color(0xFFF3E8FF));
    }
    return switch (status) {
      'pending'     => ('Pending', const Color(0xFFDD6B20), const Color(0xFFFEEBC8)),
      'assigned'    => ('Assigned', const Color(0xFF3182CE), const Color(0xFFEBF8FF)),
      'accepted'    => ('Assigned', const Color(0xFF3182CE), const Color(0xFFEBF8FF)),
      'on_the_way'  => ('On The Way', const Color(0xFF4A6FA5), const Color(0xFFEBF4FF)),
      'arrived'     => ('Arrived', const Color(0xFF6B46C1), const Color(0xFFF3E8FF)),
      'in_progress' => ('In Progress', const Color(0xFF805AD5), const Color(0xFFFAF5FF)),
      'completed'   => ('Completed', const Color(0xFF38A169), const Color(0xFFF0FFF4)),
      'rejected'    => ('Rejected', const Color(0xFFC05621), const Color(0xFFFEEBC8)),
      'cancelled'   => ('Cancelled', const Color(0xFFE53E3E), const Color(0xFFFFF5F5)),
      _             => (status, const Color(0xFF718096), const Color(0xFFEDF2F7)),
    };
  }

  factory Booking.fromMap(Map<String, dynamic> map) {
    BookingReview? review;
    final reviewData = map['customer_reviews'];
    if (reviewData is List && reviewData.isNotEmpty) {
      review = BookingReview.fromMap(reviewData.first as Map<String, dynamic>);
    } else if (reviewData is Map<String, dynamic>) {
      review = BookingReview.fromMap(reviewData);
    }

    final bookingNum = map['booking_number'] ?? map['id'];
    debugPrint(
      '[DODO][Bookings] Review status resolved: booking $bookingNum — '
      '${review != null ? 'reviewed (${review.rating}★)' : 'not reviewed'}',
    );

    final rawItems = map['booking_items'] as List<dynamic>? ?? [];
    final items = rawItems
        .map((e) => BookingItem.fromMap(e as Map<String, dynamic>))
        .toList();

    final rawAddons = map['booking_addons'] as List<dynamic>? ?? [];
    final addons = rawAddons
        .map((e) => BookingAddon.fromMap(e as Map<String, dynamic>))
        .toList();

    final vendorData = map['vendors'] as Map<String, dynamic>?;
    final vendorName = (vendorData?['business_name'] as String?) ?? '';

    return Booking(
      id: map['id'] as String,
      bookingNumber: map['booking_number'] as String? ?? '',
      customerId: map['customer_id'] as String? ?? '',
      vendorId: map['vendor_id'] as String? ?? '',
      vendorName: vendorName,
      dodoTeamId: map['dodo_team_id'] as String? ?? '',
      assignmentType: map['assignment_type'] as String? ?? 'Unassigned',
      serviceDate: map['service_date'] != null
          ? DateTime.tryParse(map['service_date'] as String)
          : null,
      status: map['status'] as String? ?? 'pending',
      dispatchStatus: map['dispatch_status'] as String? ?? 'idle',
      subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0.0,
      discountAmount: (map['discount_amount'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0.0,
      address: map['address'] as String?,
      notes: map['notes'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
      review: review,
      rejectionReason: map['rejection_reason'] as String?,
      rejectedAt: map['rejected_at'] != null
          ? DateTime.tryParse(map['rejected_at'] as String)
          : null,
      items: items,
      addons: addons,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      completionOtp: map['completion_otp'] as String?,
      paymentMethod: map['payment_method'] as String? ?? 'cash',
      isAmc: map['is_amc'] as bool? ?? false,
      amcPlanName: map['amc_plan_name'] as String?,
      amcRecurrenceInterval: map['amc_recurrence_interval'] as String?,
      amcContractId: map['amc_contract_id'] as String?,
      amcVisitNumber: (map['amc_visit_number'] as num?)?.toInt(),
      amcVisitsCompleted: () {
        final c = map['amc_contracts'];
        if (c is! Map) return null;
        return (c['visits_completed'] as num?)?.toInt();
      }(),
      amcTotalVisits: () {
        final c = map['amc_contracts'];
        if (c is! Map) return null;
        return ((c['num_visits'] as num?)?.toInt()) ??
            (c['total_visits'] as num?)?.toInt();
      }(),
      amcContractCreatedAt: () {
        final c = map['amc_contracts'];
        if (c is! Map) return null;
        return DateTime.tryParse(c['created_at'] as String? ?? '');
      }(),
      amcServiceInterval: () {
        final c = map['amc_contracts'];
        if (c is! Map) return null;
        return c['service_interval'] as String?;
      }(),
      amcContractStatus: () {
        final c = map['amc_contracts'];
        if (c is! Map) return null;
        return c['status'] as String?;
      }(),
      cancellationReason: () {
        final c = map['amc_contracts'];
        if (c is! Map) return null;
        return c['cancellation_reason'] as String?;
      }(),
      cancellationRemarks: () {
        final c = map['amc_contracts'];
        if (c is! Map) return null;
        return c['cancellation_remarks'] as String?;
      }(),
      cancellationRequestedAt: () {
        final c = map['amc_contracts'];
        if (c is! Map) return null;
        final s = c['cancellation_requested_at'] as String?;
        return s != null ? DateTime.tryParse(s) : null;
      }(),
      amcQuantity: () {
        final c = map['amc_contracts'];
        if (c is! Map) return 1;
        return (c['quantity'] as num?)?.toInt() ?? 1;
      }(),
    );
  }

  Booking copyWith({
    String? vendorId,
    String? dodoTeamId,
    String? assignmentType,
    DateTime? serviceDate,
    String? status,
    String? dispatchStatus,
    String? notes,
    String? completionOtp,
    List<BookingAddon>? addons,
  }) {
    return Booking(
      id: id,
      bookingNumber: bookingNumber,
      customerId: customerId,
      vendorId: vendorId ?? this.vendorId,
      dodoTeamId: dodoTeamId ?? this.dodoTeamId,
      assignmentType: assignmentType ?? this.assignmentType,
      serviceDate: serviceDate ?? this.serviceDate,
      status: status ?? this.status,
      dispatchStatus: dispatchStatus ?? this.dispatchStatus,
      subtotal: subtotal,
      discountAmount: discountAmount,
      totalAmount: totalAmount,
      address: address,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt,
      review: review,
      rejectionReason: rejectionReason,
      rejectedAt: rejectedAt,
      items: items,
      addons: addons ?? this.addons,
      latitude: latitude,
      longitude: longitude,
      completionOtp: completionOtp ?? this.completionOtp,
      paymentMethod: paymentMethod,
      isAmc: isAmc,
      amcPlanName: amcPlanName,
      amcRecurrenceInterval: amcRecurrenceInterval,
      amcContractId: amcContractId,
      amcVisitsCompleted: amcVisitsCompleted,
      amcTotalVisits: amcTotalVisits,
      amcQuantity: amcQuantity,
    );
  }
}
