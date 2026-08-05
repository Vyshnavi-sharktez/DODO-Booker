import 'package:flutter/material.dart';
import 'customer.dart';
import 'customer_address.dart';

class CustomerBookingReview {
  final String id;
  final double rating;
  final String? reviewText;
  final DateTime? createdAt;

  const CustomerBookingReview({
    required this.id,
    required this.rating,
    this.reviewText,
    this.createdAt,
  });

  factory CustomerBookingReview.fromMap(Map<String, dynamic> map) {
    return CustomerBookingReview(
      id: map['id'] as String,
      rating: (map['rating'] as num).toDouble(),
      reviewText: map['review_text'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }
}

class CustomerBookingItem {
  final String serviceId;
  final String serviceName;
  final String categoryName;
  final String subCategoryName;
  final int quantity;
  final double unitPrice;
  final double totalPrice;

  const CustomerBookingItem({
    required this.serviceId,
    required this.serviceName,
    required this.categoryName,
    required this.subCategoryName,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });

  factory CustomerBookingItem.fromMap(Map<String, dynamic> map) {
    final service = (map['catalog_nodes'] ?? map['services'])
        as Map<String, dynamic>? ?? const <String, dynamic>{};
    return CustomerBookingItem(
      serviceId: (map['service_id'] as String?) ?? '',
      serviceName: (service['name'] as String?) ?? '',
      categoryName: '',
      subCategoryName: '',
      quantity: (map['quantity'] as int?) ?? 1,
      unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0.0,
      totalPrice: (map['total_price'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class CustomerBooking {
  final String id;
  final String? bookingNumber;
  final String? vendorId;
  final String vendorName;
  final String? dodoTeamId;
  final String dodoTeamName;
  final String assignmentType;
  final DateTime? serviceDate;
  final String status;
  final String dispatchStatus;
  final double subtotal;
  final double discountAmount;
  final double totalAmount;
  final String? address;
  final String? notes;
  final DateTime createdAt;
  final List<CustomerBookingItem> items;
  final CustomerBookingReview? review;

  const CustomerBooking({
    required this.id,
    this.bookingNumber,
    this.vendorId,
    required this.vendorName,
    this.dodoTeamId,
    required this.dodoTeamName,
    required this.assignmentType,
    this.serviceDate,
    required this.status,
    this.dispatchStatus = 'idle',
    required this.subtotal,
    required this.discountAmount,
    required this.totalAmount,
    this.address,
    this.notes,
    required this.createdAt,
    required this.items,
    this.review,
  });

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

  factory CustomerBooking.fromMap(Map<String, dynamic> map) {
    final vendor =
        map['vendors'] as Map<String, dynamic>?;
    final dodoTeam =
        map['dodo_teams'] as Map<String, dynamic>?;

    // PostgREST may return a single Map (to-one) or a List (to-many) depending
    // on whether it infers the FK join as singular. Normalise to a list.
    final reviewRaw = map['customer_reviews'];
    final List<dynamic> reviewList = reviewRaw is List
        ? reviewRaw
        : reviewRaw != null
            ? [reviewRaw]
            : const [];
    CustomerBookingReview? review;
    if (reviewList.isNotEmpty) {
      review = CustomerBookingReview.fromMap(
          reviewList.first as Map<String, dynamic>);
    }

    final itemsList = map['booking_items'] as List<dynamic>? ?? const [];

    return CustomerBooking(
      id: map['id'] as String,
      bookingNumber: map['booking_number'] as String?,
      vendorId: map['vendor_id'] as String?,
      vendorName: (vendor?['business_name'] as String?) ?? '',
      dodoTeamId: map['dodo_team_id'] as String?,
      dodoTeamName: (dodoTeam?['team_name'] as String?) ?? '',
      assignmentType: (map['assignment_type'] as String?) ?? 'Unassigned',
      serviceDate: map['service_date'] != null
          ? DateTime.tryParse(map['service_date'] as String)
          : null,
      status: (map['status'] as String?) ?? 'pending',
      dispatchStatus: (map['dispatch_status'] as String?) ?? 'idle',
      subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0.0,
      discountAmount: (map['discount_amount'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0.0,
      address: map['address'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      items: itemsList
          .map((r) => CustomerBookingItem.fromMap(r as Map<String, dynamic>))
          .toList(),
      review: review,
    );
  }

  String get assigneeName {
    if (vendorName.isNotEmpty) return vendorName;
    if (dodoTeamName.isNotEmpty) return dodoTeamName;
    return '';
  }
}

class CustomerProfile {
  final Customer customer;
  final List<CustomerAddress> addresses;
  final List<CustomerBooking> bookings;

  const CustomerProfile({
    required this.customer,
    required this.addresses,
    required this.bookings,
  });

  int get totalBookings => bookings.length;

  int get completedBookings =>
      bookings.where((b) => b.status == 'completed').length;

  int get pendingBookings =>
      bookings.where((b) => b.status == 'pending').length;

  int get cancelledBookings =>
      bookings.where((b) => b.status == 'cancelled').length;

  double get totalSpent => bookings
      .where((b) => b.status == 'completed')
      .fold(0.0, (sum, b) => sum + b.totalAmount);

  DateTime? get lastBookingDate =>
      bookings.isEmpty ? null : bookings.first.createdAt;

  String? get mostBookedService {
    final freq = <String, int>{};
    for (final b in bookings) {
      for (final item in b.items) {
        if (item.serviceName.isNotEmpty) {
          freq[item.serviceName] =
              (freq[item.serviceName] ?? 0) + item.quantity;
        }
      }
    }
    if (freq.isEmpty) return null;
    return freq.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  CustomerAddress? get defaultAddress {
    final defaults = addresses.where((a) => a.isDefault);
    if (defaults.isNotEmpty) return defaults.first;
    return addresses.isEmpty ? null : addresses.first;
  }
}
