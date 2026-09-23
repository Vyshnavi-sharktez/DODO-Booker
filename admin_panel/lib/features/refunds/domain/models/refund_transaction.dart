import 'package:flutter/material.dart';

enum RefundTransactionStatus { pending, processing, completed, failed }

class RefundTransaction {
  final String id;
  final String refundRequestId;
  final double amount;
  final String gateway;
  final String? gatewayRefundId;
  final RefundTransactionStatus status;
  final String? failureReason;
  final String refundMethod;
  final String initiatedBy;
  final DateTime initiatedAt;
  final DateTime? completedAt;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  const RefundTransaction({
    required this.id,
    required this.refundRequestId,
    required this.amount,
    required this.gateway,
    this.gatewayRefundId,
    required this.status,
    this.failureReason,
    required this.refundMethod,
    required this.initiatedBy,
    required this.initiatedAt,
    this.completedAt,
    required this.metadata,
    required this.createdAt,
  });

  factory RefundTransaction.fromMap(Map<String, dynamic> m) =>
      RefundTransaction(
        id: m['id'] as String,
        refundRequestId: m['refund_request_id'] as String,
        amount: (m['amount'] as num).toDouble(),
        gateway: m['gateway'] as String,
        gatewayRefundId: m['gateway_refund_id'] as String?,
        status: _parseStatus(m['status'] as String? ?? 'pending'),
        failureReason: m['failure_reason'] as String?,
        refundMethod: m['refund_method'] as String,
        initiatedBy: m['initiated_by'] as String,
        initiatedAt: DateTime.parse(m['initiated_at'] as String),
        completedAt: m['completed_at'] != null
            ? DateTime.parse(m['completed_at'] as String)
            : null,
        metadata: (m['metadata'] as Map<String, dynamic>?) ?? {},
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  static RefundTransactionStatus _parseStatus(String s) => switch (s) {
        'processing' => RefundTransactionStatus.processing,
        'completed' => RefundTransactionStatus.completed,
        'failed' => RefundTransactionStatus.failed,
        _ => RefundTransactionStatus.pending,
      };

  Color get statusColor => switch (status) {
        RefundTransactionStatus.completed => const Color(0xFF38A169),
        RefundTransactionStatus.failed => const Color(0xFFE53E3E),
        RefundTransactionStatus.processing => const Color(0xFF3182CE),
        RefundTransactionStatus.pending => const Color(0xFFDD6B20),
      };

  String get statusLabel => switch (status) {
        RefundTransactionStatus.completed => 'Completed',
        RefundTransactionStatus.failed => 'Failed',
        RefundTransactionStatus.processing => 'Processing',
        RefundTransactionStatus.pending => 'Pending',
      };

  String get gatewayLabel => switch (gateway) {
        'razorpay' => 'Razorpay',
        'manual' => 'Manual',
        'cod_cash_return' => 'Cash Return',
        _ => gateway,
      };

  String get refundMethodLabel => switch (refundMethod) {
        'original_payment_method' => 'Original Payment Method',
        'manual' => 'Manual Transfer',
        'cod_cash_return' => 'Cash Returned',
        _ => refundMethod,
      };

  bool get canProcessViaRazorpay =>
      status == RefundTransactionStatus.pending && gateway == 'razorpay';
}
