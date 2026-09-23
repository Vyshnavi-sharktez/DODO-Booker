import 'package:flutter/material.dart';
import 'refund_transaction.dart';
import 'refund_status_event.dart';

enum RefundTicketStatus {
  submitted,
  underReview,
  moreInfoRequested,
  approved,
  partiallyApproved,
  rejected,
  processing,
  completed,
  failed,
  closed,
}

class RefundRequest {
  final String id;
  final String ticketNumber;
  final String bookingId;
  final String customerId;
  final String? paymentId;
  final String? issueCategoryId;

  final String? description;
  final double requestedAmount;
  final List<String> evidenceUrls;
  final int evidenceCount;

  final String paymentMethodSnapshot;
  final double amountPaidSnapshot;

  final RefundTicketStatus status;

  final double? approvedAmount;
  final String? adminNotes;
  final String? decisionNotes;
  final String? reviewedBy;
  final DateTime? reviewedAt;

  final double processedAmount;

  final DateTime? closedAt;
  final String? closedBy;

  final DateTime createdAt;
  final DateTime updatedAt;

  // COD bank/UPI details fields
  final DateTime? bankDetailsRequestedAt;
  final DateTime? bankDetailsSubmittedAt;
  final Map<String, dynamic>? bankUpiDetails;

  // Joined data (may be null if not fetched)
  final String? bookingNumber;
  final String? customerName;
  final String? customerPhone;
  final String? issueCategoryLabel;
  final List<RefundTransaction> transactions;
  final List<RefundStatusEvent> statusHistory;

  const RefundRequest({
    required this.id,
    required this.ticketNumber,
    required this.bookingId,
    required this.customerId,
    this.paymentId,
    this.issueCategoryId,
    this.description,
    required this.requestedAmount,
    required this.evidenceUrls,
    required this.evidenceCount,
    required this.paymentMethodSnapshot,
    required this.amountPaidSnapshot,
    required this.status,
    this.approvedAmount,
    this.adminNotes,
    this.decisionNotes,
    this.reviewedBy,
    this.reviewedAt,
    required this.processedAmount,
    this.closedAt,
    this.closedBy,
    required this.createdAt,
    required this.updatedAt,
    this.bankDetailsRequestedAt,
    this.bankDetailsSubmittedAt,
    this.bankUpiDetails,
    this.bookingNumber,
    this.customerName,
    this.customerPhone,
    this.issueCategoryLabel,
    this.transactions = const [],
    this.statusHistory = const [],
  });

  factory RefundRequest.fromMap(Map<String, dynamic> m) {
    final evidenceRaw = m['evidence_urls'];
    final List<String> evidence = evidenceRaw is List
        ? evidenceRaw.map((e) => e.toString()).toList()
        : [];

    return RefundRequest(
      id: m['id'] as String,
      ticketNumber: m['ticket_number'] as String,
      bookingId: m['booking_id'] as String,
      customerId: m['customer_id'] as String,
      paymentId: m['payment_id'] as String?,
      issueCategoryId: m['issue_category_id'] as String?,
      description: m['description'] as String?,
      requestedAmount: (m['requested_amount'] as num).toDouble(),
      evidenceUrls: evidence,
      evidenceCount: m['evidence_count'] as int? ?? 0,
      paymentMethodSnapshot: m['payment_method_snapshot'] as String,
      amountPaidSnapshot: (m['amount_paid_snapshot'] as num).toDouble(),
      status: _parseStatus(m['status'] as String? ?? 'submitted'),
      approvedAmount: m['approved_amount'] != null
          ? (m['approved_amount'] as num).toDouble()
          : null,
      adminNotes: m['admin_notes'] as String?,
      decisionNotes: m['decision_notes'] as String?,
      reviewedBy: m['reviewed_by'] as String?,
      reviewedAt: m['reviewed_at'] != null
          ? DateTime.parse(m['reviewed_at'] as String)
          : null,
      processedAmount: (m['processed_amount'] as num?)?.toDouble() ?? 0.0,
      closedAt: m['closed_at'] != null
          ? DateTime.parse(m['closed_at'] as String)
          : null,
      closedBy: m['closed_by'] as String?,
      createdAt: DateTime.parse(m['created_at'] as String),
      updatedAt: DateTime.parse(m['updated_at'] as String),
      bankDetailsRequestedAt: m['bank_details_requested_at'] != null
          ? DateTime.parse(m['bank_details_requested_at'] as String)
          : null,
      bankDetailsSubmittedAt: m['bank_details_submitted_at'] != null
          ? DateTime.parse(m['bank_details_submitted_at'] as String)
          : null,
      bankUpiDetails: m['bank_upi_details'] as Map<String, dynamic>?,
      bookingNumber: _extractBookingNumber(m),
      customerName: _extractCustomerName(m),
      customerPhone: _extractCustomerPhone(m),
      issueCategoryLabel: _extractCategoryLabel(m),
    );
  }

  static RefundTicketStatus _parseStatus(String s) => switch (s) {
        'under_review' => RefundTicketStatus.underReview,
        'more_info_requested' => RefundTicketStatus.moreInfoRequested,
        'approved' => RefundTicketStatus.approved,
        'partially_approved' => RefundTicketStatus.partiallyApproved,
        'rejected' => RefundTicketStatus.rejected,
        'processing' => RefundTicketStatus.processing,
        'completed' => RefundTicketStatus.completed,
        'failed' => RefundTicketStatus.failed,
        'closed' => RefundTicketStatus.closed,
        _ => RefundTicketStatus.submitted,
      };

  static String? _extractBookingNumber(Map<String, dynamic> m) {
    final b = m['bookings'];
    if (b is Map) return b['booking_number'] as String?;
    return null;
  }

  static String? _extractCustomerName(Map<String, dynamic> m) {
    final c = m['customers'];
    if (c is Map) return c['full_name'] as String?;
    return null;
  }

  static String? _extractCustomerPhone(Map<String, dynamic> m) {
    final c = m['customers'];
    if (c is Map) return c['phone'] as String?;
    return null;
  }

  static String? _extractCategoryLabel(Map<String, dynamic> m) {
    final cat = m['refund_issue_categories'];
    if (cat is Map) return cat['label'] as String?;
    return null;
  }

  RefundRequest copyWith({
    List<RefundTransaction>? transactions,
    List<RefundStatusEvent>? statusHistory,
  }) => RefundRequest(
        id: id,
        ticketNumber: ticketNumber,
        bookingId: bookingId,
        customerId: customerId,
        paymentId: paymentId,
        issueCategoryId: issueCategoryId,
        description: description,
        requestedAmount: requestedAmount,
        evidenceUrls: evidenceUrls,
        evidenceCount: evidenceCount,
        paymentMethodSnapshot: paymentMethodSnapshot,
        amountPaidSnapshot: amountPaidSnapshot,
        status: status,
        approvedAmount: approvedAmount,
        adminNotes: adminNotes,
        decisionNotes: decisionNotes,
        reviewedBy: reviewedBy,
        reviewedAt: reviewedAt,
        processedAmount: processedAmount,
        closedAt: closedAt,
        closedBy: closedBy,
        createdAt: createdAt,
        updatedAt: updatedAt,
        bankDetailsRequestedAt: bankDetailsRequestedAt,
        bankDetailsSubmittedAt: bankDetailsSubmittedAt,
        bankUpiDetails: bankUpiDetails,
        bookingNumber: bookingNumber,
        customerName: customerName,
        customerPhone: customerPhone,
        issueCategoryLabel: issueCategoryLabel,
        transactions: transactions ?? this.transactions,
        statusHistory: statusHistory ?? this.statusHistory,
      );

  // ── Display helpers ──────────────────────────────────────────────────────

  String get statusLabel => switch (status) {
        RefundTicketStatus.submitted => 'Submitted',
        RefundTicketStatus.underReview => 'Under Review',
        RefundTicketStatus.moreInfoRequested => 'More Info Needed',
        RefundTicketStatus.approved => 'Approved',
        RefundTicketStatus.partiallyApproved => 'Partially Approved',
        RefundTicketStatus.rejected => 'Rejected',
        RefundTicketStatus.processing => 'Processing',
        RefundTicketStatus.completed => 'Completed',
        RefundTicketStatus.failed => 'Failed',
        RefundTicketStatus.closed => 'Closed',
      };

  String get statusDbValue => switch (status) {
        RefundTicketStatus.submitted => 'submitted',
        RefundTicketStatus.underReview => 'under_review',
        RefundTicketStatus.moreInfoRequested => 'more_info_requested',
        RefundTicketStatus.approved => 'approved',
        RefundTicketStatus.partiallyApproved => 'partially_approved',
        RefundTicketStatus.rejected => 'rejected',
        RefundTicketStatus.processing => 'processing',
        RefundTicketStatus.completed => 'completed',
        RefundTicketStatus.failed => 'failed',
        RefundTicketStatus.closed => 'closed',
      };

  Color get statusColor => switch (status) {
        RefundTicketStatus.submitted => const Color(0xFF718096),
        RefundTicketStatus.underReview => const Color(0xFF3182CE),
        RefundTicketStatus.moreInfoRequested => const Color(0xFFDD6B20),
        RefundTicketStatus.approved => const Color(0xFF38A169),
        RefundTicketStatus.partiallyApproved => const Color(0xFF38A169),
        RefundTicketStatus.rejected => const Color(0xFFE53E3E),
        RefundTicketStatus.processing => const Color(0xFF805AD5),
        RefundTicketStatus.completed => const Color(0xFF2F855A),
        RefundTicketStatus.failed => const Color(0xFFE53E3E),
        RefundTicketStatus.closed => const Color(0xFF718096),
      };

  Color get statusBgColor => statusColor.withAlpha(30);

  bool get canMarkUnderReview =>
      status == RefundTicketStatus.submitted ||
      status == RefundTicketStatus.moreInfoRequested;

  bool get canRequestMoreInfo =>
      status == RefundTicketStatus.submitted ||
      status == RefundTicketStatus.underReview;

  bool get canApprove =>
      status == RefundTicketStatus.submitted ||
      status == RefundTicketStatus.underReview ||
      status == RefundTicketStatus.moreInfoRequested;

  bool get canReject => canApprove;

  bool get isCodBooking =>
      paymentMethodSnapshot == 'cod' || paymentMethodSnapshot == 'cash';

  bool get hasBankDetailsRequested => bankDetailsRequestedAt != null;

  bool get hasBankDetailsSubmitted => bankDetailsSubmittedAt != null;

  bool get _isInitiableStatus =>
      status == RefundTicketStatus.approved ||
      status == RefundTicketStatus.partiallyApproved ||
      status == RefundTicketStatus.failed;

  // COD: show "Request Bank Details" when approved/partially_approved/failed,
  // customer has not yet submitted, regardless of whether already requested
  // (allows re-sending the request).
  bool get canRequestBankDetails =>
      isCodBooking && _isInitiableStatus && !hasBankDetailsSubmitted;

  // COD: show "Awaiting Bank Details" indicator once requested but not submitted.
  bool get isAwaitingBankDetails =>
      isCodBooking && hasBankDetailsRequested && !hasBankDetailsSubmitted;

  bool get canInitiateTransaction {
    if (!_isInitiableStatus) return false;
    if (isCodBooking) return hasBankDetailsSubmitted;
    return true;
  }

  bool get canClose =>
      status != RefundTicketStatus.processing &&
      status != RefundTicketStatus.closed;

  double get remainingRefundable {
    // Effective ceiling: approved_amount caps the limit when set.
    // Mirrors get_refundable_balance RPC logic.
    final effectiveLimit = approvedAmount != null
        ? (approvedAmount! < amountPaidSnapshot
            ? approvedAmount!
            : amountPaidSnapshot)
        : amountPaidSnapshot;
    // Count completed, pending, and processing transactions.
    // In-flight amounts are included so the getter agrees with what the RPC
    // will accept, preventing over-initiation warnings on repeat attempts.
    final used = transactions
        .where((t) =>
            t.status == RefundTransactionStatus.completed ||
            t.status == RefundTransactionStatus.pending ||
            t.status == RefundTransactionStatus.processing)
        .fold(0.0, (sum, t) => sum + t.amount);
    return (effectiveLimit - used).clamp(0.0, double.infinity);
  }

  String get paymentMethodLabel => switch (paymentMethodSnapshot) {
        'cod' || 'cash' => 'Cash on Delivery',
        'online' => 'Online Payment',
        _ => paymentMethodSnapshot,
      };
}
