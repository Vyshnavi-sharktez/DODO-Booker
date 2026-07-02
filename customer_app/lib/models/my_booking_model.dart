import 'package:flutter/foundation.dart';

import 'address_model.dart';
import 'booking_item.dart';
import 'booking_status_event.dart';

class BookingStatus {
  static const String pending = 'pending';
  static const String assigned = 'assigned';
  static const String assignedToDodoTeam = 'assigned_to_dodo_team';
  static const String accepted = 'accepted';
  static const String enRoute = 'en_route';
  static const String inProgress = 'in_progress';
  static const String started = 'started';
  static const String awaitingVerification = 'awaiting_verification';
  static const String completed = 'completed';
  static const String cancelled = 'cancelled';

  // Stages shown for bookings handled by an external vendor.
  static const List<(String, String)> orderedStages = [
    (pending, 'Booking Placed'),
    (assigned, 'Vendor Assigned'),
    (accepted, 'Vendor Accepted'),
    (enRoute, 'Technician En Route'),
    (inProgress, 'Service In Progress'),
    (awaitingVerification, 'OTP Verification'),
    (completed, 'Service Completed'),
  ];

  // Stages shown for bookings handled by DODO Team (no vendor accept step).
  static const List<(String, String)> dodoOrderedStages = [
    (pending, 'Booking Placed'),
    (assignedToDodoTeam, 'Assigned to DODO Team'),
    (inProgress, 'Service Started'),
    (awaitingVerification, 'OTP Verification'),
    (completed, 'Service Completed'),
  ];

  static String labelFor(String status, {String assignmentType = 'External Vendor'}) {
    final stages = assignmentType == 'DODO Team' ? dodoOrderedStages : orderedStages;
    for (final (s, label) in stages) {
      if (s == status) return label;
    }
    if (status == cancelled) return 'Cancelled';
    return status;
  }

  static List<BookingStatusEvent> buildTimeline(
    String currentStatus,
    DateTime base, {
    String assignmentType = 'External Vendor',
  }) {
    final isDodo = assignmentType == 'DODO Team';
    final stages = isDodo ? dodoOrderedStages : orderedStages;
    // 'started' is the vendor-app alias for 'in_progress'; treat identically.
    final lookupStatus = currentStatus == started ? inProgress : currentStatus;
    final currentIdx = stages.indexWhere((s) => s.$1 == lookupStatus);

    return List.generate(stages.length, (i) {
      final (status, label) = stages[i];
      final isReached =
          currentStatus != cancelled ? i <= currentIdx : i == 0;
      return BookingStatusEvent(
        status: status,
        label: label,
        isReached: isReached,
        // Only the first step (Booking Placed) uses the real createdAt timestamp.
        timestamp: isReached && i == 0 ? base : null,
      );
    });
  }
}

class MyBookingModel {
  final String id;
  final String serviceId;
  final String serviceName;
  final String? categoryName;
  final String? categoryIconKey;
  final String? subcategoryName;
  final List<BookingItem> items;
  final AddressModel address;
  final DateTime scheduledDate;
  final String timeSlot;
  final double baseAmount;
  final double taxAmount;
  final double totalAmount;
  final String status;
  final String assignmentType; // 'Unassigned' | 'External Vendor' | 'DODO Team'
  final DateTime createdAt;
  final String? vendorName;
  final String? vendorPhone;
  final String? completionOtp;
  final List<BookingStatusEvent> timeline;

  const MyBookingModel({
    required this.id,
    required this.serviceId,
    required this.serviceName,
    this.categoryName,
    this.categoryIconKey,
    this.subcategoryName,
    this.items = const [],
    required this.address,
    required this.scheduledDate,
    required this.timeSlot,
    required this.baseAmount,
    required this.taxAmount,
    required this.totalAmount,
    required this.status,
    this.assignmentType = 'Unassigned',
    required this.createdAt,
    this.vendorName,
    this.vendorPhone,
    this.completionOtp,
    this.timeline = const [],
  });

  bool get isDodoTeam => assignmentType == 'DODO Team';

  bool get isUpcoming =>
      status == BookingStatus.pending ||
      status == BookingStatus.assigned ||
      status == BookingStatus.assignedToDodoTeam ||
      status == BookingStatus.accepted;

  bool get isOngoing =>
      status == BookingStatus.enRoute ||
      status == BookingStatus.inProgress ||
      status == BookingStatus.started ||
      status == BookingStatus.awaitingVerification;

  bool get isCompleted => status == BookingStatus.completed;

  bool get isCancelled => status == BookingStatus.cancelled;

  bool get canCancel => isUpcoming;
  bool get canRebook => isCompleted || isCancelled;
  bool get canReview => isCompleted;

  factory MyBookingModel.fromJson(Map<String, dynamic> json) {
    final createdAtStr = json['created_at'] as String;

    // ── Parse all booking_items ───────────────────────────────────────────
    final rawItems = json['booking_items'] as List<dynamic>? ?? [];
    final bookingItems = rawItems
        .map((e) => BookingItem.fromJson(e as Map<String, dynamic>))
        .toList();

    final firstItem =
        rawItems.isNotEmpty ? rawItems[0] as Map<String, dynamic> : null;
    final serviceData = firstItem?['services'] as Map<String, dynamic>?;
    final categoryData = serviceData?['categories'] as Map<String, dynamic>?;
    final subCategoryData =
        serviceData?['sub_categories'] as Map<String, dynamic>?;

    final notes = json['notes'] as String?;
    final serviceId = serviceData?['id'] as String? ??
        (json['service_id'] as String?) ??
        json['id'] as String;

    // For multi-item bookings: "AC Service + 2 more"
    final String serviceName;
    if (bookingItems.isEmpty) {
      serviceName = _serviceNameFromNotes(notes) ?? '';
    } else if (bookingItems.length == 1) {
      serviceName = bookingItems.first.serviceName.isNotEmpty
          ? bookingItems.first.serviceName
          : (_serviceNameFromNotes(notes) ?? '');
    } else {
      final first = bookingItems.first.serviceName;
      serviceName = first.isNotEmpty
          ? '$first + ${bookingItems.length - 1} more'
          : '${bookingItems.length} services';
    }

    // ── Time slot from notes: "Service Name · 10:00 AM" or just the slot ─
    final timeSlot =
        (json['time_slot'] as String?) ?? _timeSlotFromNotes(notes) ?? '';

    // ── Address from text column ──────────────────────────────────────────
    final rawAddress = json['address'];
    final address = rawAddress is Map<String, dynamic>
        ? AddressModel.fromJson(rawAddress)
        : _parseTextAddress((rawAddress as String?) ?? '');

    final assignmentType =
        json['assignment_type'] as String? ?? 'Unassigned';
    final status = json['status'] as String;
    final rawOtp = json['completion_otp'];
    debugPrint('[OTP][Model] id=${json['id']}  status=$status  '
        'json[completion_otp]=$rawOtp  (type: ${rawOtp.runtimeType})');

    return MyBookingModel(
      id: json['id'] as String,
      serviceId: serviceId,
      serviceName: serviceName,
      categoryName: categoryData?['name'] as String?,
      subcategoryName: subCategoryData?['name'] as String?,
      items: bookingItems,
      address: address,
      scheduledDate: DateTime.parse(
        ((json['scheduled_date'] ?? json['service_date']) as String?) ??
            DateTime.now().toIso8601String(),
      ),
      timeSlot: timeSlot,
      baseAmount:
          ((json['base_amount'] ?? json['subtotal']) as num?)?.toDouble() ??
              0.0,
      taxAmount: (json['tax_amount'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      status: status,
      assignmentType: assignmentType,
      createdAt: DateTime.parse(createdAtStr),
      vendorName: (json['vendors'] as Map<String, dynamic>?)?['business_name'] as String?,
      vendorPhone: (json['vendors'] as Map<String, dynamic>?)?['phone'] as String?,
      completionOtp: rawOtp as String?,
      timeline: (json['timeline'] as List<dynamic>?)
              ?.map((e) =>
                  BookingStatusEvent.fromJson(e as Map<String, dynamic>))
              .toList() ??
          BookingStatus.buildTimeline(
            status,
            DateTime.parse(createdAtStr),
            assignmentType: assignmentType,
          ),
    );
  }

  // "Service Name · 10:00 AM" → "10:00 AM"
  static String? _timeSlotFromNotes(String? notes) {
    if (notes == null || !notes.contains(' · ')) return null;
    final parts = notes.split(' · ');
    return parts.length >= 2 ? parts.last : null;
  }

  // "Service Name · 10:00 AM" → "Service Name"
  static String? _serviceNameFromNotes(String? notes) {
    if (notes == null || !notes.contains(' · ')) return null;
    return notes.split(' · ').first;
  }

  // Parse fullAddress text format: "line1[, line2], city, state, pincode"
  // The last 3 comma-separated parts are always city, state, pincode.
  static AddressModel _parseTextAddress(String text) {
    if (text.isEmpty) {
      return const AddressModel(
          id: '', label: '', line1: '', city: '', state: '', pincode: '');
    }
    final parts = text.split(', ');
    if (parts.length >= 3) {
      final pincode = parts.last;
      final state = parts[parts.length - 2];
      final city = parts[parts.length - 3];
      final line1 = parts.sublist(0, parts.length - 3).join(', ');
      return AddressModel(
        id: '',
        label: '',
        line1: line1.isNotEmpty ? line1 : text,
        city: city,
        state: state,
        pincode: pincode,
      );
    }
    return AddressModel(
        id: '', label: '', line1: text, city: '', state: '', pincode: '');
  }
}
