import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import 'refund_status_event_model.dart';
import 'refund_transaction_model.dart';
import 'refund_message_model.dart';

class CustomerRefundModel {
  final String id;
  final String ticketNumber;
  final String bookingId;
  final String customerId;
  final String? paymentId;
  final String? issueCategoryId;
  final String? issueCategoryLabel;
  final String? description;
  final double requestedAmount;
  final List<String> evidenceUrls;
  final int evidenceCount;
  final String paymentMethodSnapshot;
  final double amountPaidSnapshot;
  final String status;
  final double? approvedAmount;
  final String? decisionNotes;
  final double processedAmount;
  final DateTime createdAt;
  final DateTime updatedAt;

  // COD bank details tracking
  final DateTime? bankDetailsRequestedAt;
  final DateTime? bankDetailsSubmittedAt;

  // Joined from bookings
  final String? bookingNumber;
  final String? serviceName;
  final DateTime? scheduledDate;

  final List<RefundTransactionModel> transactions;
  final List<RefundStatusEventModel> statusHistory;
  final List<RefundMessageModel> messages;

  const CustomerRefundModel({
    required this.id,
    required this.ticketNumber,
    required this.bookingId,
    required this.customerId,
    this.paymentId,
    this.issueCategoryId,
    this.issueCategoryLabel,
    this.description,
    required this.requestedAmount,
    required this.evidenceUrls,
    required this.evidenceCount,
    required this.paymentMethodSnapshot,
    required this.amountPaidSnapshot,
    required this.status,
    this.approvedAmount,
    this.decisionNotes,
    required this.processedAmount,
    required this.createdAt,
    required this.updatedAt,
    this.bankDetailsRequestedAt,
    this.bankDetailsSubmittedAt,
    this.bookingNumber,
    this.serviceName,
    this.scheduledDate,
    this.transactions = const [],
    this.statusHistory = const [],
    this.messages = const [],
  });

  bool get isTerminal =>
      status == 'completed' || status == 'rejected' || status == 'closed';

  bool get isCodBooking =>
      paymentMethodSnapshot == 'cod' || paymentMethodSnapshot == 'cash';

  bool get needsBankDetails =>
      isCodBooking &&
      bankDetailsRequestedAt != null &&
      bankDetailsSubmittedAt == null;

  bool get needsCustomerAction =>
      status == 'more_info_requested' || needsBankDetails;

  bool get canSendMessage =>
      status != 'closed' && status != 'completed' && status != 'rejected';

  String get statusLabel {
    switch (status) {
      case 'submitted':         return 'Submitted';
      case 'under_review':      return 'Under Review';
      case 'more_info_requested': return 'Info Requested';
      case 'approved':          return 'Approved';
      case 'partially_approved': return 'Partially Approved';
      case 'rejected':          return 'Rejected';
      case 'processing':        return 'Processing';
      case 'completed':         return 'Completed';
      case 'failed':            return 'Retrying';
      case 'closed':            return 'Closed';
      default:                  return status;
    }
  }

  Color statusColor(BuildContext context) {
    switch (status) {
      case 'completed':          return AppColors.success;
      case 'approved':
      case 'partially_approved': return const Color(0xFF1A73E8);
      case 'rejected':
      case 'failed':             return AppColors.error;
      case 'more_info_requested': return AppColors.warning;
      case 'processing':         return const Color(0xFF9C27B0);
      case 'under_review':       return AppColors.gold;
      case 'closed':             return AppColors.textHint;
      default:                   return AppColors.textSecondary;
    }
  }

  Color statusBgColor(BuildContext context) {
    switch (status) {
      case 'completed':          return AppColors.success.withAlpha(18);
      case 'approved':
      case 'partially_approved': return const Color(0xFF1A73E8).withAlpha(16);
      case 'rejected':
      case 'failed':             return AppColors.error.withAlpha(16);
      case 'more_info_requested': return AppColors.warning.withAlpha(24);
      case 'processing':         return const Color(0xFF9C27B0).withAlpha(14);
      case 'under_review':       return AppColors.goldLight;
      case 'closed':             return AppColors.shimmerBase;
      default:                   return AppColors.surfaceVariant;
    }
  }

  factory CustomerRefundModel.fromMap(
    Map<String, dynamic> map, {
    List<RefundStatusEventModel> statusHistory = const [],
    List<RefundTransactionModel> transactions = const [],
    List<RefundMessageModel> messages = const [],
  }) {
    final rawEvidence = map['evidence_urls'];
    final evidenceUrls = rawEvidence is List
        ? rawEvidence.map((e) => e.toString()).toList()
        : <String>[];

    // Joined bookings data
    final bookingData = map['bookings'] as Map<String, dynamic>?;
    Map<String, dynamic>? catNode;
    if (bookingData != null) {
      final items = bookingData['booking_items'];
      if (items is List && items.isNotEmpty) {
        final firstItem = items.first as Map<String, dynamic>?;
        catNode = firstItem?['catalog_nodes'] as Map<String, dynamic>?;
      }
    }

    // Issue category join
    final catMap =
        map['refund_issue_categories'] as Map<String, dynamic>?;

    return CustomerRefundModel(
      id: map['id'] as String,
      ticketNumber: map['ticket_number'] as String,
      bookingId: map['booking_id'] as String,
      customerId: map['customer_id'] as String,
      paymentId: map['payment_id'] as String?,
      issueCategoryId: map['issue_category_id'] as String?,
      issueCategoryLabel: catMap?['label'] as String?,
      description: map['description'] as String?,
      requestedAmount: (map['requested_amount'] as num).toDouble(),
      evidenceUrls: evidenceUrls,
      evidenceCount: (map['evidence_count'] as num?)?.toInt() ?? 0,
      paymentMethodSnapshot:
          map['payment_method_snapshot'] as String? ?? 'cash',
      amountPaidSnapshot:
          (map['amount_paid_snapshot'] as num?)?.toDouble() ?? 0.0,
      status: map['status'] as String? ?? 'submitted',
      approvedAmount: (map['approved_amount'] as num?)?.toDouble(),
      decisionNotes: map['decision_notes'] as String?,
      processedAmount:
          (map['processed_amount'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      bankDetailsRequestedAt: map['bank_details_requested_at'] != null
          ? DateTime.parse(map['bank_details_requested_at'] as String)
          : null,
      bankDetailsSubmittedAt: map['bank_details_submitted_at'] != null
          ? DateTime.parse(map['bank_details_submitted_at'] as String)
          : null,
      bookingNumber: bookingData?['booking_number'] as String?,
      serviceName: catNode?['name'] as String?,
      scheduledDate: bookingData?['service_date'] != null
          ? DateTime.tryParse(bookingData!['service_date'] as String)
          : null,
      statusHistory: statusHistory,
      transactions: transactions,
      messages: messages,
    );
  }
}
