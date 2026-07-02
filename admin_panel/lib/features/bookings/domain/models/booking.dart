import 'package:flutter/foundation.dart';
import 'booking_item.dart';

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
      rating: (map['rating'] as int?) ?? 0,
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
  final String dodoTeamId;
  final String assignmentType; // 'Unassigned' | 'External Vendor' | 'DODO Team'
  final DateTime? serviceDate;
  final String status;
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
  final double? latitude;
  final double? longitude;
  final String? completionOtp;

  const Booking({
    required this.id,
    required this.bookingNumber,
    required this.customerId,
    required this.vendorId,
    this.dodoTeamId = '',
    this.assignmentType = 'Unassigned',
    this.serviceDate,
    required this.status,
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
    this.latitude,
    this.longitude,
    this.completionOtp,
  });

  bool get isUnassigned => assignmentType == 'Unassigned';

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

    return Booking(
      id: map['id'] as String,
      bookingNumber: map['booking_number'] as String? ?? '',
      customerId: map['customer_id'] as String? ?? '',
      vendorId: map['vendor_id'] as String? ?? '',
      dodoTeamId: map['dodo_team_id'] as String? ?? '',
      assignmentType: map['assignment_type'] as String? ?? 'Unassigned',
      serviceDate: map['service_date'] != null
          ? DateTime.tryParse(map['service_date'] as String)
          : null,
      status: map['status'] as String? ?? 'pending',
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
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      completionOtp: map['completion_otp'] as String?,
    );
  }

  Booking copyWith({
    String? vendorId,
    String? dodoTeamId,
    String? assignmentType,
    DateTime? serviceDate,
    String? status,
    String? notes,
    String? completionOtp,
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
      latitude: latitude,
      longitude: longitude,
      completionOtp: completionOtp ?? this.completionOtp,
    );
  }
}
